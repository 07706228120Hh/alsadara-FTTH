using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddSasSourceToSubscriptionLog : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "SasAccountId",
                table: "SubscriptionLogs",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "Source",
                table: "SubscriptionLogs",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "SubscriberUid",
                table: "SubscriptionLogs",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "SubscriberUsername",
                table: "SubscriptionLogs",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "SasAccountId",
                table: "SubscriptionLogs");

            migrationBuilder.DropColumn(
                name: "Source",
                table: "SubscriptionLogs");

            migrationBuilder.DropColumn(
                name: "SubscriberUid",
                table: "SubscriptionLogs");

            migrationBuilder.DropColumn(
                name: "SubscriberUsername",
                table: "SubscriptionLogs");
        }
    }
}
