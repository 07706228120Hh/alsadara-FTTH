using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddAttendanceSecurityLayers : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Description",
                table: "WorkCenters",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "RegisteredDeviceFingerprint",
                table: "Users",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "DeviceFingerprint",
                table: "AttendanceRecords",
                type: "text",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "AttendanceAuditLogs",
                columns: table => new
                {
                    Id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    UserName = table.Column<string>(type: "text", nullable: false),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: true),
                    ActionType = table.Column<string>(type: "text", nullable: false),
                    IsSuccess = table.Column<bool>(type: "boolean", nullable: false),
                    RejectionReason = table.Column<string>(type: "text", nullable: true),
                    Latitude = table.Column<double>(type: "double precision", nullable: true),
                    Longitude = table.Column<double>(type: "double precision", nullable: true),
                    DistanceFromCenter = table.Column<double>(type: "double precision", nullable: true),
                    CenterName = table.Column<string>(type: "text", nullable: true),
                    DeviceFingerprint = table.Column<string>(type: "text", nullable: true),
                    RegisteredDeviceFingerprint = table.Column<string>(type: "text", nullable: true),
                    IpAddress = table.Column<string>(type: "text", nullable: true),
                    AttemptTime = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AttendanceAuditLogs", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_WorkCenters_CompanyId",
                table: "WorkCenters",
                column: "CompanyId");

            migrationBuilder.AddForeignKey(
                name: "FK_WorkCenters_Companies_CompanyId",
                table: "WorkCenters",
                column: "CompanyId",
                principalTable: "Companies",
                principalColumn: "Id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_WorkCenters_Companies_CompanyId",
                table: "WorkCenters");

            migrationBuilder.DropTable(
                name: "AttendanceAuditLogs");

            migrationBuilder.DropIndex(
                name: "IX_WorkCenters_CompanyId",
                table: "WorkCenters");

            migrationBuilder.DropColumn(
                name: "Description",
                table: "WorkCenters");

            migrationBuilder.DropColumn(
                name: "RegisteredDeviceFingerprint",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "DeviceFingerprint",
                table: "AttendanceRecords");
        }
    }
}
