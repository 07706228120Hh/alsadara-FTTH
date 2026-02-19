using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddTaskAudit : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "InternetPlanId",
                table: "ServiceRequests",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "ProfitAmount",
                table: "InternetPlans",
                type: "numeric(18,2)",
                precision: 18,
                scale: 2,
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.CreateTable(
                name: "AgentCommissionRates",
                columns: table => new
                {
                    Id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    AgentId = table.Column<Guid>(type: "uuid", nullable: false),
                    InternetPlanId = table.Column<Guid>(type: "uuid", nullable: false),
                    CommissionPercentage = table.Column<decimal>(type: "numeric(5,2)", precision: 5, scale: 2, nullable: false),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    Notes = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AgentCommissionRates", x => x.Id);
                    table.ForeignKey(
                        name: "FK_AgentCommissionRates_Agents_AgentId",
                        column: x => x.AgentId,
                        principalTable: "Agents",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_AgentCommissionRates_Companies_CompanyId",
                        column: x => x.CompanyId,
                        principalTable: "Companies",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_AgentCommissionRates_InternetPlans_InternetPlanId",
                        column: x => x.InternetPlanId,
                        principalTable: "InternetPlans",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "TaskAudits",
                columns: table => new
                {
                    Id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    ServiceRequestId = table.Column<Guid>(type: "uuid", nullable: false),
                    RequestNumber = table.Column<string>(type: "text", nullable: true),
                    AuditStatus = table.Column<string>(type: "text", nullable: false),
                    Rating = table.Column<int>(type: "integer", nullable: false),
                    Notes = table.Column<string>(type: "text", nullable: true),
                    AuditedBy = table.Column<string>(type: "text", nullable: true),
                    AuditedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TaskAudits", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ServiceRequests_InternetPlanId",
                table: "ServiceRequests",
                column: "InternetPlanId");

            migrationBuilder.CreateIndex(
                name: "IX_AgentCommissionRates_AgentId_InternetPlanId",
                table: "AgentCommissionRates",
                columns: new[] { "AgentId", "InternetPlanId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_AgentCommissionRates_CompanyId",
                table: "AgentCommissionRates",
                column: "CompanyId");

            migrationBuilder.CreateIndex(
                name: "IX_AgentCommissionRates_InternetPlanId",
                table: "AgentCommissionRates",
                column: "InternetPlanId");

            migrationBuilder.AddForeignKey(
                name: "FK_ServiceRequests_InternetPlans_InternetPlanId",
                table: "ServiceRequests",
                column: "InternetPlanId",
                principalTable: "InternetPlans",
                principalColumn: "Id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_ServiceRequests_InternetPlans_InternetPlanId",
                table: "ServiceRequests");

            migrationBuilder.DropTable(
                name: "AgentCommissionRates");

            migrationBuilder.DropTable(
                name: "TaskAudits");

            migrationBuilder.DropIndex(
                name: "IX_ServiceRequests_InternetPlanId",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "InternetPlanId",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "ProfitAmount",
                table: "InternetPlans");
        }
    }
}
