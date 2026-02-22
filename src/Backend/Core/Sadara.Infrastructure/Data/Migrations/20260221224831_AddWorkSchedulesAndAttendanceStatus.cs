using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddWorkSchedulesAndAttendanceStatus : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "EarlyDepartureMinutes",
                table: "AttendanceRecords",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<TimeOnly>(
                name: "ExpectedEndTime",
                table: "AttendanceRecords",
                type: "time without time zone",
                nullable: true);

            migrationBuilder.AddColumn<TimeOnly>(
                name: "ExpectedStartTime",
                table: "AttendanceRecords",
                type: "time without time zone",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "LateMinutes",
                table: "AttendanceRecords",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "OvertimeMinutes",
                table: "AttendanceRecords",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "Status",
                table: "AttendanceRecords",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "WorkScheduleId",
                table: "AttendanceRecords",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "WorkedMinutes",
                table: "AttendanceRecords",
                type: "integer",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "WorkSchedules",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Name = table.Column<string>(type: "text", nullable: false),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: true),
                    CenterName = table.Column<string>(type: "text", nullable: true),
                    DayOfWeek = table.Column<int>(type: "integer", nullable: true),
                    WorkStartTime = table.Column<TimeOnly>(type: "time without time zone", nullable: false),
                    WorkEndTime = table.Column<TimeOnly>(type: "time without time zone", nullable: false),
                    LateGraceMinutes = table.Column<int>(type: "integer", nullable: false),
                    EarlyDepartureThresholdMinutes = table.Column<int>(type: "integer", nullable: false),
                    IsDefault = table.Column<bool>(type: "boolean", nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_WorkSchedules", x => x.Id);
                    table.ForeignKey(
                        name: "FK_WorkSchedules_Companies_CompanyId",
                        column: x => x.CompanyId,
                        principalTable: "Companies",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateIndex(
                name: "IX_AttendanceRecords_WorkScheduleId",
                table: "AttendanceRecords",
                column: "WorkScheduleId");

            migrationBuilder.CreateIndex(
                name: "IX_WorkSchedules_CompanyId",
                table: "WorkSchedules",
                column: "CompanyId");

            migrationBuilder.AddForeignKey(
                name: "FK_AttendanceRecords_WorkSchedules_WorkScheduleId",
                table: "AttendanceRecords",
                column: "WorkScheduleId",
                principalTable: "WorkSchedules",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_AttendanceRecords_WorkSchedules_WorkScheduleId",
                table: "AttendanceRecords");

            migrationBuilder.DropTable(
                name: "WorkSchedules");

            migrationBuilder.DropIndex(
                name: "IX_AttendanceRecords_WorkScheduleId",
                table: "AttendanceRecords");

            migrationBuilder.DropColumn(
                name: "EarlyDepartureMinutes",
                table: "AttendanceRecords");

            migrationBuilder.DropColumn(
                name: "ExpectedEndTime",
                table: "AttendanceRecords");

            migrationBuilder.DropColumn(
                name: "ExpectedStartTime",
                table: "AttendanceRecords");

            migrationBuilder.DropColumn(
                name: "LateMinutes",
                table: "AttendanceRecords");

            migrationBuilder.DropColumn(
                name: "OvertimeMinutes",
                table: "AttendanceRecords");

            migrationBuilder.DropColumn(
                name: "Status",
                table: "AttendanceRecords");

            migrationBuilder.DropColumn(
                name: "WorkScheduleId",
                table: "AttendanceRecords");

            migrationBuilder.DropColumn(
                name: "WorkedMinutes",
                table: "AttendanceRecords");
        }
    }
}
