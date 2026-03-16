using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddIptvSubscribers : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<TimeOnly>(
                name: "CustomWorkEndTime",
                table: "Users",
                type: "time without time zone",
                nullable: true);

            migrationBuilder.AddColumn<TimeOnly>(
                name: "CustomWorkStartTime",
                table: "Users",
                type: "time without time zone",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "WorkScheduleId",
                table: "Users",
                type: "integer",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "IptvSubscribers",
                columns: table => new
                {
                    Id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    CompanyId = table.Column<string>(type: "text", nullable: false),
                    SubscriptionId = table.Column<string>(type: "text", nullable: true),
                    CustomerName = table.Column<string>(type: "text", nullable: false),
                    Phone = table.Column<string>(type: "text", nullable: true),
                    IptvUsername = table.Column<string>(type: "text", nullable: true),
                    IptvPassword = table.Column<string>(type: "text", nullable: true),
                    IptvCode = table.Column<string>(type: "text", nullable: true),
                    ActivationDate = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    DurationMonths = table.Column<int>(type: "integer", nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    Location = table.Column<string>(type: "text", nullable: true),
                    Notes = table.Column<string>(type: "text", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_IptvSubscribers", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Users_WorkScheduleId",
                table: "Users",
                column: "WorkScheduleId");

            migrationBuilder.AddForeignKey(
                name: "FK_Users_WorkSchedules_WorkScheduleId",
                table: "Users",
                column: "WorkScheduleId",
                principalTable: "WorkSchedules",
                principalColumn: "Id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_Users_WorkSchedules_WorkScheduleId",
                table: "Users");

            migrationBuilder.DropTable(
                name: "IptvSubscribers");

            migrationBuilder.DropIndex(
                name: "IX_Users_WorkScheduleId",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "CustomWorkEndTime",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "CustomWorkStartTime",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "WorkScheduleId",
                table: "Users");
        }
    }
}
