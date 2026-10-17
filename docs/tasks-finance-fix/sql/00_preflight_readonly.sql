-- ════════════════════════════════════════════════════════════════════════════
--  Phase 1 / Stream F — PRE-FLIGHT (READ-ONLY). Safe on the mirror and on production.
--  Run:  psql -X -d sadara_db -v ON_ERROR_STOP=1 \
--             -c "SET default_transaction_read_only = on" -f 00_preflight_readonly.sql
--  (or with PGOPTIONS="-c default_transaction_read_only=on").
--  Nothing here writes. Decide from the output whether 01 must run before the migrations.
-- ════════════════════════════════════════════════════════════════════════════
\pset footer off
SET default_transaction_read_only = on;

\echo '== 1) Server version (NULLS NOT DISTINCT needs PostgreSQL >= 15)'
SELECT current_setting('server_version') AS server_version,
       current_setting('server_version_num')::int >= 150000 AS supports_nulls_not_distinct;

\echo '== 2) Do the new indexes already exist? (expected: 0 rows before the release)'
SELECT c.relname AS index_name, i.indisvalid, pg_get_indexdef(i.indexrelid) AS definition
FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
WHERE c.relname IN ('UX_SubscriptionLogs_Company_FtthTx', 'UX_TechnicianTransactions_ServiceRequest_Category_Charge');

\echo '== 3) Migration A blocker: live duplicate (CompanyId, FtthTransactionId) groups (must be 0)'
SELECT count(*) AS dup_groups, coalesce(sum(n), 0) AS dup_rows
FROM (SELECT count(*) AS n FROM "SubscriptionLogs"
      WHERE "FtthTransactionId" IS NOT NULL AND NOT "IsDeleted"
      GROUP BY "CompanyId", "FtthTransactionId" HAVING count(*) > 1) d;

\echo '== 3b) Context: SubscriptionLogs totals'
SELECT count(*) AS total_rows,
       count(*) FILTER (WHERE NOT "IsDeleted") AS live_rows,
       count(*) FILTER (WHERE NOT "IsDeleted" AND "FtthTransactionId" IS NULL) AS live_without_ftth_tx,
       count(*) FILTER (WHERE NOT "IsDeleted" AND "FtthTransactionId" IS NOT NULL AND "CompanyId" IS NULL) AS live_tx_null_company
FROM "SubscriptionLogs";

\echo '== 4) Migration B blocker: live duplicate task-fee charges (ServiceRequestId, Category, Type=Charge) (must be 0 after 01)'
SELECT t."ServiceRequestId", t."Category", count(*) AS n,
       array_agg(t."Id" ORDER BY t."CreatedAt", t."Id") AS ids,
       array_agg(t."Amount" ORDER BY t."CreatedAt", t."Id") AS amounts,
       min(t."CreatedAt") AS first_at, max(t."CreatedAt") AS last_at
FROM "TechnicianTransactions" t
WHERE t."ServiceRequestId" IS NOT NULL AND NOT t."IsDeleted" AND t."Type" = 0
GROUP BY t."ServiceRequestId", t."Category" HAVING count(*) > 1
ORDER BY first_at;

\echo '== 5) (Not a migration blocker) duplicate SUBSCRIPTION charges per subscription log — see 02/03'
--    "extra" = rows whose journal entry is missing/deleted/voided while another row of the same log has a
--    live Posted JE (the amounts inside a group can differ — the log was re-posted after an edit).
WITH c AS (
  SELECT t."CompanyId", t."ReferenceNumber", t."Amount",
         (je."Id" IS NOT NULL AND NOT je."IsDeleted" AND je."Status" = 1) AS posted_live,
         (t."JournalEntryId" IS NOT NULL AND (je."Id" IS NULL OR je."IsDeleted" OR je."Status" = 2)) AS reversed,
         count(*) OVER (PARTITION BY t."CompanyId", t."ReferenceNumber") AS n
  FROM "TechnicianTransactions" t
  LEFT JOIN "JournalEntries" je ON je."Id" = t."JournalEntryId"
  WHERE NOT t."IsDeleted" AND t."Type" = 0 AND t."Category" = 4 AND t."ReferenceNumber" IS NOT NULL),
g AS (SELECT c.*, count(*) FILTER (WHERE posted_live) OVER (PARTITION BY "CompanyId", "ReferenceNumber") AS posted_in_group
      FROM c WHERE n > 1)
SELECT count(DISTINCT ("CompanyId", "ReferenceNumber")) AS logs_with_duplicates,
       count(*) AS rows_in_duplicated_groups,
       count(*) FILTER (WHERE posted_in_group = 1 AND reversed) AS extra_rows,
       coalesce(sum("Amount") FILTER (WHERE posted_in_group = 1 AND reversed), 0) AS extra_amount,
       count(DISTINCT ("CompanyId", "ReferenceNumber")) FILTER (WHERE posted_in_group <> 1) AS ambiguous_logs
FROM g;

\echo '== 6) Lock risk: open transactions older than 30s (should be none at deploy time)'
SELECT pid, usename, application_name, state, now() - xact_start AS xact_age, left(query, 80) AS query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL AND now() - xact_start > interval '30 seconds' AND pid <> pg_backend_pid()
ORDER BY xact_start;

\echo '== 7) Table sizes (index build time scales with these)'
SELECT 'SubscriptionLogs' AS table_name, (SELECT count(*) FROM "SubscriptionLogs") AS row_count,
       pg_size_pretty(pg_total_relation_size('"SubscriptionLogs"')) AS total_size
UNION ALL
SELECT 'TechnicianTransactions', (SELECT count(*) FROM "TechnicianTransactions"),
       pg_size_pretty(pg_total_relation_size('"TechnicianTransactions"'));

\echo '== 8) Migration history tail (deploy-backend.sh applies EVERY pending migration, not only these two)'
SELECT "MigrationId" FROM "__EFMigrationsHistory" ORDER BY "MigrationId" DESC LIMIT 5;
