-- ════════════════════════════════════════════════════════════════════════════
--  Phase 1 / Stream F — 99: EMERGENCY rollback of the two double-posting indexes.
--  Needs the owner's approval like any production change. Data is never touched — indexes only.
--
--  Preferred rollback (keeps EF history consistent), generated from the repo:
--    dotnet ef migrations script 20261017205105_AddUniqueTechnicianChargePerServiceRequest \
--        20261012203130_AddPropertyQrTokens --idempotent \
--        --project src/Backend/Core/Sadara.Infrastructure --startup-project src/Backend/API/Sadara.API -o rollback.sql
--    psql -X -d sadara_db -v ON_ERROR_STOP=1 -f rollback.sql
--  ⇒ DROP INDEX IF EXISTS ×2 + deletes the two __EFMigrationsHistory rows.
--  WARNING: Program.cs calls Database.MigrateAsync() at every API start. With the history rows deleted and the
--  NEW DLLs still deployed, the next restart re-creates the indexes. So: either also roll back the DLLs
--  (/root/backups/dll_<TS>), or use the emergency variant below which keeps the history rows.
--
--  Emergency variant (this file): drop the indexes WITHOUT blocking writes, keep the history rows
--  (so nothing re-creates them on restart). Re-enable later by re-running the migration's Up SQL by hand
--  (it is idempotent) — see PHASE1_MIGRATIONS.md §6.
--  DROP INDEX CONCURRENTLY cannot run inside a transaction: run this file with psql WITHOUT -1/--single-transaction.
-- ════════════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on
SET lock_timeout = '5s';

DROP INDEX CONCURRENTLY IF EXISTS "UX_SubscriptionLogs_Company_FtthTx";
DROP INDEX CONCURRENTLY IF EXISTS "UX_TechnicianTransactions_ServiceRequest_Category_Charge";

-- Verify (expected: 0 rows)
SELECT indexname FROM pg_indexes
WHERE indexname IN ('UX_SubscriptionLogs_Company_FtthTx', 'UX_TechnicianTransactions_ServiceRequest_Category_Charge');
