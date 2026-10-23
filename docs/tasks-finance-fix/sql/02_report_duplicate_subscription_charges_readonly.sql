-- ════════════════════════════════════════════════════════════════════════════
--  Phase 1 / Stream F — 02: REPORT (READ-ONLY) of duplicate SUBSCRIPTION charges on technicians ("H").
--  Safe on the mirror and on production (read-only session).
--
--  Shape of the problem (mirror 2026-08-19): 148 subscription logs carry 2–3 live technician charges
--  (TechnicianTransactions Type=Charge(0), Category=Subscription(4), ReferenceNumber = SubscriptionLogs.Id)
--  instead of one ⇒ 247 extra rows, 9,691,000 IQD.
--    - exactly ONE row per log points to a live, Posted journal entry (the real posting);
--    - the extra rows point to journal entries that were hard-deleted (246) or soft-deleted+Voided (1),
--      i.e. the accounting side was reversed but the technician charge row was left live.
--  These rows inflate any technician balance computed from TechnicianTransactions. Whether and how they are
--  cleaned up depends on the owner's single-source decision for technician balances (PLAN.md Phase 4);
--  see the DRAFT 03 script.
--
--  Run:  psql -X -d sadara_db -v ON_ERROR_STOP=1 -c "SET default_transaction_read_only = on" \
--             -f 02_report_duplicate_subscription_charges_readonly.sql
--  CSV:  add  -A -F ',' -o h_report.csv  (or wrap section 2 with \copy ( ... ) TO 'h_report.csv' CSV HEADER).
-- ════════════════════════════════════════════════════════════════════════════
\pset footer off
SET default_transaction_read_only = on;

-- Classification used by 02 and 03:
--   posted_live  = JE exists, not deleted, Status = Posted(1)
--   je_missing   = JournalEntryId set but the JE row does not exist (hard-deleted)
--   je_reversed  = JE soft-deleted or Status = Voided(2)
--   no_je        = JournalEntryId IS NULL
--   je_other     = anything else (e.g. Draft) — never auto-classified as extra
\echo '== 1) Summary'
WITH c AS (
  SELECT t."Id", t."CompanyId", t."ReferenceNumber", t."Amount",
         CASE WHEN t."JournalEntryId" IS NULL THEN 'no_je'
              WHEN je."Id" IS NULL THEN 'je_missing'
              WHEN je."IsDeleted" OR je."Status" = 2 THEN 'je_reversed'
              WHEN je."Status" = 1 THEN 'posted_live'
              ELSE 'je_other' END AS je_state,
         count(*) OVER (PARTITION BY t."CompanyId", t."ReferenceNumber") AS n
  FROM "TechnicianTransactions" t
  LEFT JOIN "JournalEntries" je ON je."Id" = t."JournalEntryId"
  WHERE NOT t."IsDeleted" AND t."Type" = 0 AND t."Category" = 4 AND t."ReferenceNumber" IS NOT NULL)
SELECT je_state, count(*) AS rows, sum("Amount") AS amount,
       count(DISTINCT ("CompanyId", "ReferenceNumber")) AS logs
FROM c WHERE n > 1 GROUP BY je_state ORDER BY je_state;

\echo '== 2) Detail: one line per charge row in a duplicated group (proposed = what DRAFT 03 would do)'
WITH c AS (
  SELECT t."Id", t."CompanyId", t."TechnicianId", t."ReferenceNumber", t."Amount", t."BalanceAfter",
         t."CreatedAt", t."JournalEntryId", t."Description",
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
SELECT g."CompanyId", g."ReferenceNumber" AS subscription_log_id, g."Id" AS technician_tx_id,
       u."FullName" AS technician, g."Amount", g."CreatedAt", g.je_state, g.n AS rows_in_group, g.posted_in_group,
       CASE WHEN g.posted_in_group <> 1 THEN 'MANUAL REVIEW (ambiguous group)'
            WHEN g.je_state = 'posted_live' THEN 'KEEP'
            WHEN g.je_state IN ('je_missing', 'je_reversed') THEN 'SOFT-DELETE (draft)'
            ELSE 'MANUAL REVIEW' END AS proposed,
       sl."IsDeleted" AS log_deleted, sl."CustomerName", sl."PlanName", sl."ActivationDate"
FROM g
LEFT JOIN "Users" u ON u."Id" = g."TechnicianId"
LEFT JOIN "SubscriptionLogs" sl ON g."ReferenceNumber" ~ '^[0-9]+$' AND sl."Id" = g."ReferenceNumber"::bigint
ORDER BY g."CompanyId", g."ReferenceNumber", g."CreatedAt", g."Id";

\echo '== 3) Per-technician effect if the SOFT-DELETE (draft) rows were removed'
WITH c AS (
  SELECT t."Id", t."CompanyId", t."TechnicianId", t."ReferenceNumber", t."Amount",
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
SELECT g."CompanyId", g."TechnicianId", u."FullName", count(*) AS extra_rows, sum(g."Amount") AS extra_amount,
       u."TechTotalCharges" AS cached_total_charges, u."TechNetBalance" AS cached_net_balance
FROM g LEFT JOIN "Users" u ON u."Id" = g."TechnicianId"
WHERE g.posted_in_group = 1 AND g.je_state IN ('je_missing', 'je_reversed')
GROUP BY g."CompanyId", g."TechnicianId", u."FullName", u."TechTotalCharges", u."TechNetBalance"
ORDER BY extra_amount DESC;
