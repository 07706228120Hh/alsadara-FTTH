using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddSettlementJournalLink : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "DeliveredToId",
                table: "DailySettlementReports",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "DeliveredToName",
                table: "DailySettlementReports",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "JournalEntryId",
                table: "DailySettlementReports",
                type: "uuid",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "DeliveredToId",
                table: "DailySettlementReports");

            migrationBuilder.DropColumn(
                name: "DeliveredToName",
                table: "DailySettlementReports");

            migrationBuilder.DropColumn(
                name: "JournalEntryId",
                table: "DailySettlementReports");
        }
    }
}
