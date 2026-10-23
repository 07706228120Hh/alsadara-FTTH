-- ════════════════════════════════════════════════════════════════════════════
--  Phase 1 / Stream F — 01: resolve duplicate TASK-FEE charges (pre-requisite of migration B).
--  STATUS: prepared, NOT executed. Production run needs the owner's explicit approval
--          + a fresh backup (deploy-backend.sh step 3, or: sudo -u postgres pg_dump sadara_db | gzip > ...).
--
--  What it does
--    For every live (ServiceRequestId, Category, Type=Charge) group with more than one row, keeps the
--    EARLIEST row and soft-deletes the later ones (IsDeleted=true, DeletedAt=now()) with a reversal note.
--    Every touched row is copied in full (jsonb) to finance_fix_audit.affected_rows first ⇒ exact undo.
--
--  Mirror 2026-08-19: exactly 1 group — ServiceRequest d2f24743-62cc-4bc9-ac9c-934d6eed9006 (task 26072713341408),
--    Maintenance 2 × 1,000 IQD, ids 29314 (kept) / 29315 (soft-deleted), created 3 ms apart (double submit race),
--    both with BalanceAfter = 57,000 and no journal entry ⇒ no JE to reverse.
--
--  What it deliberately does NOT do
--    - Does not touch Users.TechTotalCharges / TechNetBalance. The two inserts raced on the same user snapshot
--      (identical BalanceAfter), so the cached total most likely counted the fee once already; the cached
--      totals also drift from the ledger in general (single-source decision pending — Phase 4).
--    - Does not touch journal entries (none exist for these rows).
--
--  Run:  psql -X -d sadara_db -v ON_ERROR_STOP=1 -f 01_resolve_duplicate_task_fee.sql
--        Step 1 (preview) is read-only. Step 2 ends with ROLLBACK by default — dry run.
--        After reviewing the dry run, set expected_rows to the preview count and change ROLLBACK → COMMIT.
-- ════════════════════════════════════════════════════════════════════════════
\pset footer off
\set expected_rows 1

-- ───────────────────────── Step 1: PREVIEW (read-only) ─────────────────────────
\echo '== Preview: rows that will be soft-deleted (rn > 1) and the row kept for each group (rn = 1)'
WITH g AS (
  SELECT t."Id", t."ServiceRequestId", t."Category", t."TechnicianId", t."CompanyId", t."Amount",
         t."BalanceAfter", t."JournalEntryId", t."CreatedAt", t."Description",
         row_number() OVER w AS rn, count(*) OVER (PARTITION BY t."ServiceRequestId", t."Category") AS n,
         first_value(t."Id") OVER w AS keeper_id
  FROM "TechnicianTransactions" t
  WHERE t."ServiceRequestId" IS NOT NULL AND NOT t."IsDeleted" AND t."Type" = 0
  WINDOW w AS (PARTITION BY t."ServiceRequestId", t."Category" ORDER BY t."CreatedAt", t."Id"))
SELECT CASE WHEN rn = 1 THEN 'KEEP' ELSE 'SOFT-DELETE' END AS action, g.*, sr."RequestNumber", sr."Status" AS task_status
FROM g LEFT JOIN "ServiceRequests" sr ON sr."Id" = g."ServiceRequestId"
WHERE n > 1
ORDER BY "ServiceRequestId", "Category", rn;

-- ───────────────────────── Step 2: APPLY (transaction) ─────────────────────────
BEGIN;
SET LOCAL lock_timeout = '5s';
SELECT set_config('finance_fix.expected_rows', :'expected_rows', true);

CREATE SCHEMA IF NOT EXISTS finance_fix_audit;
CREATE TABLE IF NOT EXISTS finance_fix_audit.affected_rows (
    id          bigserial PRIMARY KEY,
    script      text        NOT NULL,
    table_name  text        NOT NULL,
    row_id      text        NOT NULL,
    action      text        NOT NULL,
    before_row  jsonb       NOT NULL,
    note        text,
    applied_at  timestamptz NOT NULL DEFAULT now(),
    applied_by  text        NOT NULL DEFAULT current_user
);

DO $fix01$
DECLARE
    expected int := current_setting('finance_fix.expected_rows')::int;
    audited  int;
    updated  int;
BEGIN
    -- Block concurrent fee inserts for the few ms of this fix (reads stay allowed).
    LOCK TABLE "TechnicianTransactions" IN SHARE ROW EXCLUSIVE MODE;

    CREATE TEMP TABLE fix01_victims ON COMMIT DROP AS
    SELECT x."Id", x.keeper_id
    FROM (
        SELECT t."Id",
               row_number()  OVER w AS rn,
               first_value(t."Id") OVER w AS keeper_id
        FROM "TechnicianTransactions" t
        WHERE t."ServiceRequestId" IS NOT NULL AND NOT t."IsDeleted" AND t."Type" = 0
        WINDOW w AS (PARTITION BY t."ServiceRequestId", t."Category" ORDER BY t."CreatedAt", t."Id")
    ) x
    WHERE x.rn > 1;

    INSERT INTO finance_fix_audit.affected_rows (script, table_name, row_id, action, before_row, note)
    SELECT '01_resolve_duplicate_task_fee', 'TechnicianTransactions', t."Id"::text, 'soft_delete', to_jsonb(t),
           'duplicate of #' || v.keeper_id
    FROM "TechnicianTransactions" t JOIN fix01_victims v ON v."Id" = t."Id";
    GET DIAGNOSTICS audited = ROW_COUNT;

    UPDATE "TechnicianTransactions" t
    SET "IsDeleted" = true,
        "DeletedAt" = now(),
        "UpdatedAt" = now(),
        "Notes"     = concat_ws(' | ', nullif(t."Notes", ''),
                      'إبطال أجر مكرر (إصلاح المرحلة 1-F): نسخة مكررة من الحركة #' || v.keeper_id
                      || ' — لا أثر على القيود؛ لم يُعدَّل رصيد الفني المخزّن')
    FROM fix01_victims v
    WHERE t."Id" = v."Id";
    GET DIAGNOSTICS updated = ROW_COUNT;

    RAISE NOTICE '01: audited % row(s), soft-deleted % row(s) (expected %)', audited, updated, expected;
    IF updated <> expected OR audited <> updated THEN
        RAISE EXCEPTION '01 aborted: soft-deleted % row(s), audited %, expected % — nothing changed. Re-run the preview.',
            updated, audited, expected;
    END IF;
END
$fix01$;

\echo '== Post-check inside the transaction (must be 0 rows)'
SELECT t."ServiceRequestId", t."Category", count(*)
FROM "TechnicianTransactions" t
WHERE t."ServiceRequestId" IS NOT NULL AND NOT t."IsDeleted" AND t."Type" = 0
GROUP BY 1, 2 HAVING count(*) > 1;

ROLLBACK;   -- dry run by default. Change to COMMIT only with the owner's approval.

-- ───────────────────────── UNDO (only if needed) ─────────────────────────
-- Undo restores the soft-deleted rows from the audit copy. If migration B is already applied, the
-- unique index will (correctly) reject the restore — roll migration B back first (PHASE1_MIGRATIONS.md §6).
--
-- BEGIN;
-- UPDATE "TechnicianTransactions" t
-- SET "IsDeleted" = (a.before_row->>'IsDeleted')::boolean,
--     "DeletedAt" = (a.before_row->>'DeletedAt')::timestamptz,
--     "UpdatedAt" = (a.before_row->>'UpdatedAt')::timestamptz,
--     "Notes"     = a.before_row->>'Notes'
-- FROM finance_fix_audit.affected_rows a
-- WHERE a.script = '01_resolve_duplicate_task_fee' AND a.table_name = 'TechnicianTransactions'
--   AND t."Id" = a.row_id::bigint;
-- DELETE FROM finance_fix_audit.affected_rows WHERE script = '01_resolve_duplicate_task_fee';
-- COMMIT;
