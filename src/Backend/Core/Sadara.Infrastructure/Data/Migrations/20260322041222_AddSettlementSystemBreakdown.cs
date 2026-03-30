using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddSettlementSystemBreakdown : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<decimal>(
                name: "NetCashAmount",
                table: "DailySettlementReports",
                type: "numeric",
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<decimal>(
                name: "SystemAgentTotal",
                table: "DailySettlementReports",
                type: "numeric",
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<decimal>(
                name: "SystemCashTotal",
                table: "DailySettlementReports",
                type: "numeric",
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<decimal>(
                name: "SystemCreditTotal",
                table: "DailySettlementReports",
                type: "numeric",
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<decimal>(
                name: "SystemMasterTotal",
                table: "DailySettlementReports",
                type: "numeric",
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<decimal>(
                name: "SystemTechTotal",
                table: "DailySettlementReports",
                type: "numeric",
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<decimal>(
                name: "SystemTotal",
                table: "DailySettlementReports",
                type: "numeric",
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<decimal>(
                name: "TotalExpenses",
                table: "DailySettlementReports",
                type: "numeric",
                nullable: false,
                defaultValue: 0m);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "NetCashAmount",
                table: "DailySettlementReports");

            migrationBuilder.DropColumn(
                name: "SystemAgentTotal",
                table: "DailySettlementReports");

            migrationBuilder.DropColumn(
                name: "SystemCashTotal",
                table: "DailySettlementReports");

            migrationBuilder.DropColumn(
                name: "SystemCreditTotal",
                table: "DailySettlementReports");

            migrationBuilder.DropColumn(
                name: "SystemMasterTotal",
                table: "DailySettlementReports");

            migrationBuilder.DropColumn(
                name: "SystemTechTotal",
                table: "DailySettlementReports");

            migrationBuilder.DropColumn(
                name: "SystemTotal",
                table: "DailySettlementReports");

            migrationBuilder.DropColumn(
                name: "TotalExpenses",
                table: "DailySettlementReports");
        }
    }
}
