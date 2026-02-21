using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddLinkedTechnicianId : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "FtthPasswordEncrypted",
                table: "Users",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "FtthUsername",
                table: "Users",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "CollectionType",
                table: "SubscriptionLogs",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "FtthTransactionId",
                table: "SubscriptionLogs",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "IsReconciled",
                table: "SubscriptionLogs",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<Guid>(
                name: "JournalEntryId",
                table: "SubscriptionLogs",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "LinkedAgentId",
                table: "SubscriptionLogs",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "LinkedTechnicianId",
                table: "SubscriptionLogs",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "ReconciliationNotes",
                table: "SubscriptionLogs",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "ServiceRequestId",
                table: "SubscriptionLogs",
                type: "uuid",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "FtthPasswordEncrypted",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "FtthUsername",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "CollectionType",
                table: "SubscriptionLogs");

            migrationBuilder.DropColumn(
                name: "FtthTransactionId",
                table: "SubscriptionLogs");

            migrationBuilder.DropColumn(
                name: "IsReconciled",
                table: "SubscriptionLogs");

            migrationBuilder.DropColumn(
                name: "JournalEntryId",
                table: "SubscriptionLogs");

            migrationBuilder.DropColumn(
                name: "LinkedAgentId",
                table: "SubscriptionLogs");

            migrationBuilder.DropColumn(
                name: "LinkedTechnicianId",
                table: "SubscriptionLogs");

            migrationBuilder.DropColumn(
                name: "ReconciliationNotes",
                table: "SubscriptionLogs");

            migrationBuilder.DropColumn(
                name: "ServiceRequestId",
                table: "SubscriptionLogs");
        }
    }
}
