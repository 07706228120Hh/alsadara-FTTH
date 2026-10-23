-- ════════════════════════════════════════════════════════════════════════════
--  ██████  DRAFT — DO NOT RUN ON PRODUCTION  ██████
--  Phase 1 / Stream F — 03: cleanup of duplicate SUBSCRIPTION charges on technicians ("H").
--
--  BLOCKED ON: the owner's single-source decision for technician balances (PLAN.md "قرارات المالك" /
--  Phase 4) + accountant review of the 02 report. Not a pre-requisite of migrations A/B.
--
--  Safety latches (all three must be changed deliberately):
--    1) the APPLY block refuses to run unless the session setting finance_fix.approve_h_cleanup is
--       'yes-owner-approved' (set it with:  \set approve yes-owner-approved  — see below);
--    2) the transaction ends with ROLLBACK (dry run) — change to COMMIT only after approval;
--    3) expected_rows must equal the 02 report count of 'SOFT-DELETE (draft)' rows.
--
--  Scope (conservative): soft-delete ONLY charge rows in a duplicated group that (a) has exactly one row
--  whose journal entry is live+Posted (kept), and (b) whose own journal entry is hard-deleted or
--  soft-deleted/Voided. Ambiguous groups and rows with no / Draft JE are left for manual review.
--  Journal entries are not touched (they are already gone/voided).
--
--  Users.TechTotalCharges / TechNetBalance (cached totals): NOT changed here. If the owner chooses the ledger
--  (TechnicianTransactions) as the single source, those caches must be recomputed for ALL technicians in a
--  separate, approved Phase 4 step — not per row here (they already drift from the ledger independently).
-- ════════════════════════════════════════════════════════════════════════════
\pset footer off
\set expected_rows 247
\set approve 'NOT-APPROVED'
-- \set approve 'yes-owner-approved'      -- uncomment only with the owner's written approval

-- ───────────────────────── Step 1: PREVIEW (read-only) ─────────────────────────
\echo '== Preview: rows this draft would soft-delete'
WITH c AS (
  SELECT t."Id", t."CompanyId", t."TechnicianId", t."ReferenceNumber", t."Amount", t."CreatedAt",
         CASE WHEN t."JournalEntryId" IS NULL THEN 'no_je'
              WHEN je."Id" IS NULL THEN 'je_missing'
              WHEN je."IsDeleted" OR je."Status" = 2 THEN 'je_reversed'
              WHEN je."Status" = 1 THEN 'posted_live'
              ELSE 'je_other' END AS je_state,
         count(*) OVER (PARTITION BY t."CompanyId", t."ReferenceNumber") AS n
  FROM "TechnicianTransactions" t
  LEFT JOIN "JournalEntries" je ON je."Id" = t."JournalEntryId"
  WHERE NOT t."IsDeleted" AND t."Type" = 0 AND t."Category" = 4 AND t."ReferenceNumber" IS NOT NULL),
g AS (
  SELECT c.*, count(*) FILTER (WHERE je_state = 'posted_live') OVER (PARTITION BY "CompanyId", "ReferenceNumber") AS posted_in_group
  FROM c WHERE n > 1)
SELECT count(*) AS rows_to_soft_delete, coalesce(sum("Amount"), 0) AS amount,
       count(DISTINCT ("CompanyId", "ReferenceNumber")) AS logs, count(DISTINCT "TechnicianId") AS technicians
FROM g WHERE posted_in_group = 1 AND je_state IN ('je_missing', 'je_reversed');

-- ───────────────────────── Step 2: APPLY (transaction, DRAFT) ─────────────────────────
BEGIN;
SET LOCAL lock_timeout = '5s';
SELECT set_config('finance_fix.expected_rows', :'expected_rows', true);
SELECT set_config('finance_fix.approve_h_cleanup', :'approve', true);

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

DO $fix03$
DECLARE
    expected int := current_setting('finance_fix.expected_rows')::int;
    audited  int;
    updated  int;
BEGIN
    IF current_setting('finance_fix.approve_h_cleanup', true) IS DISTINCT FROM 'yes-owner-approved' THEN
        RAISE EXCEPTION '03 is a DRAFT and is not approved by the owner — nothing changed.';
    END IF;

    LOCK TABLE "TechnicianTransactions" IN SHARE ROW EXCLUSIVE MODE;

    CREATE TEMP TABLE fix03_victims ON COMMIT DROP AS
    WITH c AS (
      SELECT t."Id", t."CompanyId", t."ReferenceNumber",
             CASE WHEN t."JournalEntryId" IS NULL THEN 'no_je'
                  WHEN je."Id" IS NULL THEN 'je_missing'
                  WHEN je."IsDeleted" OR je."Status" = 2 THEN 'je_reversed'
                  WHEN je."Status" = 1 THEN 'posted_live'
                  ELSE 'je_other' END AS je_state,
             count(*) OVER (PARTITION BY t."CompanyId", t."ReferenceNumber") AS n
      FROM "TechnicianTransactions" t
      LEFT JOIN "JournalEntries" je ON je."Id" = t."JournalEntryId"
      WHERE NOT t."IsDeleted" AND t."Type" = 0 AND t."Category" = 4 AND t."ReferenceNumber" IS NOT NULL),
    g AS (
      SELECT c.*,
             count(*) FILTER (WHERE je_state = 'posted_live') OVER (PARTITION BY "CompanyId", "ReferenceNumber") AS posted_in_group,
             max(CASE WHEN je_state = 'posted_live' THEN "Id" END) OVER (PARTITION BY "CompanyId", "ReferenceNumber") AS keeper_id
      FROM c WHERE n > 1)
    SELECT "Id", keeper_id, je_state FROM g
    WHERE posted_in_group = 1 AND je_state IN ('je_missing', 'je_reversed');

    INSERT INTO finance_fix_audit.affected_rows (script, table_name, row_id, action, before_row, note)
    SELECT '03_cleanup_duplicate_subscription_charges', 'TechnicianTransactions', t."Id"::text, 'soft_delete',
           to_jsonb(t), v.je_state || '; kept #' || v.keeper_id
    FROM "TechnicianTransactions" t JOIN fix03_victims v ON v."Id" = t."Id";
    GET DIAGNOSTICS audited = ROW_COUNT;

    UPDATE "TechnicianTransactions" t
    SET "IsDeleted" = true,
        "DeletedAt" = now(),
        "UpdatedAt" = now(),
        "Notes"     = concat_ws(' | ', nullif(t."Notes", ''),
                      'إبطال شحن اشتراك مكرر (إصلاح المرحلة 1-F): قيده محذوف/ملغى؛ المعتمد الحركة #' || v.keeper_id)
    FROM fix03_victims v
    WHERE t."Id" = v."Id";
    GET DIAGNOSTICS updated = ROW_COUNT;

    RAISE NOTICE '03: audited % row(s), soft-deleted % row(s) (expected %)', audited, updated, expected;
    IF updated <> expected OR audited <> updated THEN
        RAISE EXCEPTION '03 aborted: soft-deleted %, audited %, expected % — nothing changed. Re-run 02.',
            updated, audited, expected;
    END IF;
END
$fix03$;

ROLLBACK;   -- DRAFT: keep ROLLBACK until the owner approves in writing.

-- ───────────────────────── UNDO (only if needed) ─────────────────────────
-- BEGIN;
-- UPDATE "TechnicianTransactions" t
-- SET "IsDeleted" = (a.before_row->>'IsDeleted')::boolean,
--     "DeletedAt" = (a.before_row->>'DeletedAt')::timestamptz,
--     "UpdatedAt" = (a.before_row->>'UpdatedAt')::timestamptz,
--     "Notes"     = a.before_row->>'Notes'
-- FROM finance_fix_audit.affected_rows a
-- WHERE a.script = '03_cleanup_duplicate_subscription_charges' AND a.table_name = 'TechnicianTransactions'
--   AND t."Id" = a.row_id::bigint;
-- DELETE FROM finance_fix_audit.affected_rows WHERE script = '03_cleanup_duplicate_subscription_charges';
-- COMMIT;
