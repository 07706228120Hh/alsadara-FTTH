using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddCompanyIdToAgentTransaction : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "CompanyId",
                table: "AgentTransactions",
                type: "uuid",
                nullable: false,
                defaultValue: new Guid("00000000-0000-0000-0000-000000000000"));

            migrationBuilder.CreateIndex(
                name: "IX_AgentTransactions_CompanyId",
                table: "AgentTransactions",
                column: "CompanyId");

            // Backfill: اشتقاق CompanyId للصفوف الموجودة من الوكيل المرتبط (idempotent — يُحدّث الفارغ فقط)
            migrationBuilder.Sql(@"
                UPDATE ""AgentTransactions"" t
                SET ""CompanyId"" = a.""CompanyId""
                FROM ""Agents"" a
                WHERE a.""Id"" = t.""AgentId""
                  AND t.""CompanyId"" = '00000000-0000-0000-0000-000000000000';");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_AgentTransactions_CompanyId",
                table: "AgentTransactions");

            migrationBuilder.DropColumn(
                name: "CompanyId",
                table: "AgentTransactions");
        }
    }
}
