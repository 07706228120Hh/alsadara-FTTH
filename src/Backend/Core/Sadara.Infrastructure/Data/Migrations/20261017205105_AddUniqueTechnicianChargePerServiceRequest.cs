using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <summary>
    /// Phase 1 / Stream F (B): DB-level guard against charging the same task fee twice.
    /// Partial unique index on TechnicianTransactions(ServiceRequestId, Category)
    ///   WHERE ServiceRequestId IS NOT NULL AND NOT IsDeleted AND Type = 0 (TechnicianTransactionType.Charge).
    /// Mirrors the application rule in ServiceRequestsController.RegisterFeeOnUser ("one live fee per task+category").
    /// Payments/discounts/adjustments and soft-deleted (reversed) charges are outside the predicate.
    ///
    /// Same safety design as AddUniqueSubscriptionLogFtthTransaction (lock_timeout, SHARE lock, loud abort on
    /// duplicates, idempotent if pre-built). Pre-requisite: docs/tasks-finance-fix/sql/01_resolve_duplicate_task_fee.sql
    /// (production had 1 duplicate pair on the 2026-08-19 mirror) — otherwise this migration aborts the deploy.
    /// </summary>
    public partial class AddUniqueTechnicianChargePerServiceRequest : Migration
    {
        public const string IndexName = "UX_TechnicianTransactions_ServiceRequest_Category_Charge";

        internal const string UpSql = """
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

        internal const string DownSql = """
DROP INDEX IF EXISTS "UX_TechnicianTransactions_ServiceRequest_Category_Charge";
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
