using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddServiceRequestSourceAccountRegion : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "PartnerId",
                table: "ServiceRequests",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "PartnerName",
                table: "ServiceRequests",
                type: "character varying(200)",
                maxLength: 200,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "RegionName",
                table: "ServiceRequests",
                type: "character varying(200)",
                maxLength: 200,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "RegionRef",
                table: "ServiceRequests",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "SourceAccountId",
                table: "ServiceRequests",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "SourceAccountLabel",
                table: "ServiceRequests",
                type: "character varying(200)",
                maxLength: 200,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "SourceAccountType",
                table: "ServiceRequests",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            // ملاحظة: الفهرسان IX_ServiceRequests_CompanyId_RegionRef و
            // IX_ServiceRequests_CompanyId_SourceAccountType_SourceAccountId
            // يُنشآن يدوياً على الإنتاج عبر CREATE INDEX CONCURRENTLY
            // (deploy/indexes_concurrent_tasks_source.sql) لتفادي قفل الكتابة
            // على جدول ServiceRequests الحيّ الكبير. EF لا يعرف عنهما.
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "PartnerId",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "PartnerName",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "RegionName",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "RegionRef",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "SourceAccountId",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "SourceAccountLabel",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "SourceAccountType",
                table: "ServiceRequests");
        }
    }
}
