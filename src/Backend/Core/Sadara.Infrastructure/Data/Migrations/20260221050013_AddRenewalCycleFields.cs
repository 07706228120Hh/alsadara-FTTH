using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddRenewalCycleFields : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "JournalEntryId",
                table: "TechnicianTransactions",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "NextRenewalDate",
                table: "SubscriptionLogs",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "PaidMonths",
                table: "SubscriptionLogs",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "RenewalCycleMonths",
                table: "SubscriptionLogs",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "JournalEntryId",
                table: "AgentTransactions",
                type: "uuid",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "JournalEntryId",
                table: "TechnicianTransactions");

            migrationBuilder.DropColumn(
                name: "NextRenewalDate",
                table: "SubscriptionLogs");

            migrationBuilder.DropColumn(
                name: "PaidMonths",
                table: "SubscriptionLogs");

            migrationBuilder.DropColumn(
                name: "RenewalCycleMonths",
                table: "SubscriptionLogs");

            migrationBuilder.DropColumn(
                name: "JournalEntryId",
                table: "AgentTransactions");
        }
    }
}
