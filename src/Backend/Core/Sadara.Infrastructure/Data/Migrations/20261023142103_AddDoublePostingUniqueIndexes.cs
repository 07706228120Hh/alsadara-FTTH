using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <summary>
    /// Phase 1 / Stream F (A+B): DB-level guards against double posting, re-based on top of the
    /// current production migration chain (after AddForceLogoutRevocationAndAudit).
    ///
    ///  A: partial unique index SubscriptionLogs(CompanyId, FtthTransactionId) NULLS NOT DISTINCT
    ///     WHERE FtthTransactionId IS NOT NULL AND NOT IsDeleted  — one post per admin.ftth.iq operation.
    ///  B: partial unique index TechnicianTransactions(ServiceRequestId, Category)
    ///     WHERE ServiceRequestId IS NOT NULL AND NOT IsDeleted AND Type = 0 (Charge) — one live fee per task+category.
    ///
    /// Safety design (see docs/tasks-finance-fix/PHASE1_MIGRATIONS.md):
    ///  - Not CONCURRENTLY: deploy/deploy-backend.sh runs the EF idempotent script in ONE transaction with every
    ///    statement in a DO block, where CREATE INDEX CONCURRENTLY is impossible. The tables are small (~22k / ~17k rows),
    ///    so a plain build holds a SHARE lock (reads OK, writes wait) for milliseconds.
    ///  - lock_timeout 5s: fail instead of queueing behind a long transaction (which would stall readers behind us).
    ///  - Explicit duplicate check under the same SHARE lock: aborts loudly (whole deploy transaction rolls back),
    ///    never a bare 23505 or a half-applied state.
    ///  - Idempotent: a valid pre-built index (e.g. CONCURRENTLY by the owner) is kept; an INVALID one aborts with a hint.
    ///  - Pre-requisite for B: docs/tasks-finance-fix/sql/01_resolve_duplicate_task_fee.sql (owner-approved) if the
    ///    pre-flight shows live duplicate task-fee groups — otherwise this migration aborts the deploy by design.
    /// </summary>
    public partial class AddDoublePostingUniqueIndexes : Migration
    {
        public const string SubscriptionLogIndexName = "UX_SubscriptionLogs_Company_FtthTx";
        public const string TechnicianChargeIndexName = "UX_TechnicianTransactions_ServiceRequest_Category_Charge";

        internal const string SubscriptionLogUpSql = """
DO $ux_sublog_ftthtx$
DECLARE
    prev_lock_timeout text := current_setting('lock_timeout');
    existing_valid    boolean;
    dup_groups        bigint;
    dup_rows          bigint;
BEGIN
    SELECT i.indisvalid INTO existing_valid
    FROM pg_index i
    WHERE i.indexrelid = to_regclass('"UX_SubscriptionLogs_Company_FtthTx"');

    IF existing_valid IS TRUE THEN
        RAISE NOTICE 'UX_SubscriptionLogs_Company_FtthTx already exists and is valid - skipping creation.';
        RETURN;
    ELSIF existing_valid IS FALSE THEN
        RAISE EXCEPTION 'UX_SubscriptionLogs_Company_FtthTx exists but is INVALID (failed CONCURRENTLY build). Migration aborted, nothing applied.'
            USING HINT = 'Run: DROP INDEX CONCURRENTLY IF EXISTS "UX_SubscriptionLogs_Company_FtthTx"; then re-run the migration.';
    END IF;

    PERFORM set_config('lock_timeout', '5s', true);
    -- Same lock CREATE INDEX takes anyway; taken first so the duplicate check and the build see the same rows.
    LOCK TABLE "SubscriptionLogs" IN SHARE MODE;

    SELECT count(*), coalesce(sum(n), 0) INTO dup_groups, dup_rows
    FROM (
        SELECT count(*) AS n
        FROM "SubscriptionLogs"
        WHERE "FtthTransactionId" IS NOT NULL AND NOT "IsDeleted"
        GROUP BY "CompanyId", "FtthTransactionId"
        HAVING count(*) > 1
    ) d;

    IF dup_groups > 0 THEN
        RAISE EXCEPTION 'UX_SubscriptionLogs_Company_FtthTx: % duplicate live (CompanyId, FtthTransactionId) groups (% rows). Migration aborted, nothing applied. / توجد عمليات مكررة؛ لم يُطبَّق شيء.', dup_groups, dup_rows
            USING HINT = 'Review and resolve with docs/tasks-finance-fix/sql/ (owner-approved), then re-run the migration.';
    END IF;

    CREATE UNIQUE INDEX "UX_SubscriptionLogs_Company_FtthTx"
        ON "SubscriptionLogs" ("CompanyId", "FtthTransactionId") NULLS NOT DISTINCT
        WHERE "FtthTransactionId" IS NOT NULL AND NOT "IsDeleted";

    PERFORM set_config('lock_timeout', prev_lock_timeout, true);
END
$ux_sublog_ftthtx$;
""";

        internal const string TechnicianChargeUpSql = """
DO $ux_techtx_charge$
DECLARE
    prev_lock_timeout text := current_setting('lock_timeout');
    existing_valid    boolean;
    dup_groups        bigint;
    dup_rows          bigint;
BEGIN
    SELECT i.indisvalid INTO existing_valid
    FROM pg_index i
    WHERE i.indexrelid = to_regclass('"UX_TechnicianTransactions_ServiceRequest_Category_Charge"');

    IF existing_valid IS TRUE THEN
        RAISE NOTICE 'UX_TechnicianTransactions_ServiceRequest_Category_Charge already exists and is valid - skipping creation.';
        RETURN;
    ELSIF existing_valid IS FALSE THEN
        RAISE EXCEPTION 'UX_TechnicianTransactions_ServiceRequest_Category_Charge exists but is INVALID (failed CONCURRENTLY build). Migration aborted, nothing applied.'
            USING HINT = 'Run: DROP INDEX CONCURRENTLY IF EXISTS "UX_TechnicianTransactions_ServiceRequest_Category_Charge"; then re-run the migration.';
    END IF;

    PERFORM set_config('lock_timeout', '5s', true);
    LOCK TABLE "TechnicianTransactions" IN SHARE MODE;

    SELECT count(*), coalesce(sum(n), 0) INTO dup_groups, dup_rows
    FROM (
        SELECT count(*) AS n
        FROM "TechnicianTransactions"
        WHERE "ServiceRequestId" IS NOT NULL AND NOT "IsDeleted" AND "Type" = 0
        GROUP BY "ServiceRequestId", "Category"
        HAVING count(*) > 1
    ) d;

    IF dup_groups > 0 THEN
        RAISE EXCEPTION 'UX_TechnicianTransactions_ServiceRequest_Category_Charge: % duplicate live task-fee charge groups (% rows). Migration aborted, nothing applied. / توجد أجور مهام مكررة؛ لم يُطبَّق شيء.', dup_groups, dup_rows
            USING HINT = 'Run docs/tasks-finance-fix/sql/01_resolve_duplicate_task_fee.sql (owner-approved), then re-run the migration.';
    END IF;

    CREATE UNIQUE INDEX "UX_TechnicianTransactions_ServiceRequest_Category_Charge"
        ON "TechnicianTransactions" ("ServiceRequestId", "Category")
        WHERE "ServiceRequestId" IS NOT NULL AND NOT "IsDeleted" AND "Type" = 0;

    PERFORM set_config('lock_timeout', prev_lock_timeout, true);
END
$ux_techtx_charge$;
""";

        internal const string SubscriptionLogDownSql = """
DROP INDEX IF EXISTS "UX_SubscriptionLogs_Company_FtthTx";
""";

        internal const string TechnicianChargeDownSql = """
DROP INDEX IF EXISTS "UX_TechnicianTransactions_ServiceRequest_Category_Charge";
""";

        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // A then B. Each aborts the whole deploy transaction loudly if live duplicates exist.
            migrationBuilder.Sql(SubscriptionLogUpSql);
            migrationBuilder.Sql(TechnicianChargeUpSql);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(TechnicianChargeDownSql);
            migrationBuilder.Sql(SubscriptionLogDownSql);
        }
    }
}
