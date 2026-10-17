using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <summary>
    /// Phase 1 / Stream F (A): DB-level guard against posting the same admin.ftth.iq operation twice.
    /// Partial unique index on SubscriptionLogs(CompanyId, FtthTransactionId)
    ///   WHERE FtthTransactionId IS NOT NULL AND NOT IsDeleted   (NULLS NOT DISTINCT: a NULL CompanyId cannot bypass it).
    ///
    /// Safety design (see docs/tasks-finance-fix/PHASE1_MIGRATIONS.md):
    ///  - Not CONCURRENTLY: deploy/deploy-backend.sh runs the EF idempotent script, which wraps the whole run in
    ///    one transaction and every statement in a DO block — CREATE INDEX CONCURRENTLY is impossible there.
    ///    The table is small (~22k rows), so a plain build holds a SHARE lock (reads OK, writes wait) for milliseconds.
    ///  - lock_timeout 5s: never queue behind a long transaction (which would stall all readers behind us); fail instead.
    ///  - Explicit duplicate check under the same SHARE lock: aborts loudly (whole deploy transaction rolls back)
    ///    instead of failing with a bare 23505 or half-applying.
    ///  - Idempotent: if the index was pre-built manually (e.g. CONCURRENTLY by the owner) and is valid, it is kept.
    /// </summary>
    public partial class AddUniqueSubscriptionLogFtthTransaction : Migration
    {
        public const string IndexName = "UX_SubscriptionLogs_Company_FtthTx";

        internal const string UpSql = """
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

        internal const string DownSql = """
DROP INDEX IF EXISTS "UX_SubscriptionLogs_Company_FtthTx";
""";

        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(UpSql);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(DownSql);
        }
    }
}
