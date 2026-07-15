using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddTenantCompanyIdToStragglers : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "CompanyId",
                table: "WhatsAppBatchReports",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "CompanyId",
                table: "ReminderSettings",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "CompanyId",
                table: "ReminderExecutionLogs",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "CompanyId",
                table: "EmployeeLocationLogs",
                type: "uuid",
                nullable: true);

            // ملاحظة: عمودا SlaHours (DepartmentTasks) و IsMasterSyncEnabled (CompanyFtthSettings)
            // هما drift قديم من الإصدار v2.2.21 (commit cf3520b) موجودان فعلاً في قاعدة الإنتاج،
            // فأُزيلا يدوياً من هذا الـ migration لتجنّب فشل "column already exists" عند التطبيق.
            // الـ snapshot يحتفظ بهما (تبنّي الـ drift) فلا يُعاد توليدهما. هذا الـ migration
            // مقصور على أعمدة عزل الشركة (CompanyId) الجديدة فقط.
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "CompanyId",
                table: "WhatsAppBatchReports");

            migrationBuilder.DropColumn(
                name: "CompanyId",
                table: "ReminderSettings");

            migrationBuilder.DropColumn(
                name: "CompanyId",
                table: "ReminderExecutionLogs");

            migrationBuilder.DropColumn(
                name: "CompanyId",
                table: "EmployeeLocationLogs");
        }
    }
}
