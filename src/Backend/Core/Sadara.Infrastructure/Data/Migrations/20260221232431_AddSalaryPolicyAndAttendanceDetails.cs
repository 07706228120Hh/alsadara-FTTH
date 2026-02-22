using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddSalaryPolicyAndAttendanceDetails : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "AbsentDays",
                table: "EmployeeSalaries",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<decimal>(
                name: "AbsentDeduction",
                table: "EmployeeSalaries",
                type: "numeric(18,2)",
                precision: 18,
                scale: 2,
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<int>(
                name: "AttendanceDays",
                table: "EmployeeSalaries",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<decimal>(
                name: "EarlyDepartureDeduction",
                table: "EmployeeSalaries",
                type: "numeric(18,2)",
                precision: 18,
                scale: 2,
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<int>(
                name: "ExpectedWorkDays",
                table: "EmployeeSalaries",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<decimal>(
                name: "LateDeduction",
                table: "EmployeeSalaries",
                type: "numeric(18,2)",
                precision: 18,
                scale: 2,
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<decimal>(
                name: "OvertimeBonus",
                table: "EmployeeSalaries",
                type: "numeric(18,2)",
                precision: 18,
                scale: 2,
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<int>(
                name: "PaidLeaveDays",
                table: "EmployeeSalaries",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "TotalEarlyDepartureMinutes",
                table: "EmployeeSalaries",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "TotalLateMinutes",
                table: "EmployeeSalaries",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "TotalOvertimeMinutes",
                table: "EmployeeSalaries",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "UnpaidLeaveDays",
                table: "EmployeeSalaries",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<decimal>(
                name: "UnpaidLeaveDeduction",
                table: "EmployeeSalaries",
                type: "numeric(18,2)",
                precision: 18,
                scale: 2,
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.CreateTable(
                name: "SalaryPolicies",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    IsDefault = table.Column<bool>(type: "boolean", nullable: false),
                    DeductionPerLateMinute = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    MaxLateDeductionPercent = table.Column<decimal>(type: "numeric(5,2)", precision: 5, scale: 2, nullable: false),
                    AbsentDayMultiplier = table.Column<decimal>(type: "numeric(5,2)", precision: 5, scale: 2, nullable: false),
                    DeductionPerEarlyDepartureMinute = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    OvertimeHourlyMultiplier = table.Column<decimal>(type: "numeric(5,2)", precision: 5, scale: 2, nullable: false),
                    MaxOvertimeHoursPerMonth = table.Column<int>(type: "integer", nullable: false),
                    UnpaidLeaveDayMultiplier = table.Column<decimal>(type: "numeric(5,2)", precision: 5, scale: 2, nullable: false),
                    WorkDaysPerMonth = table.Column<int>(type: "integer", nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SalaryPolicies", x => x.Id);
                    table.ForeignKey(
                        name: "FK_SalaryPolicies_Companies_CompanyId",
                        column: x => x.CompanyId,
                        principalTable: "Companies",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_SalaryPolicies_CompanyId",
                table: "SalaryPolicies",
                column: "CompanyId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "SalaryPolicies");

            migrationBuilder.DropColumn(
                name: "AbsentDays",
                table: "EmployeeSalaries");

            migrationBuilder.DropColumn(
                name: "AbsentDeduction",
                table: "EmployeeSalaries");

            migrationBuilder.DropColumn(
                name: "AttendanceDays",
                table: "EmployeeSalaries");

            migrationBuilder.DropColumn(
                name: "EarlyDepartureDeduction",
                table: "EmployeeSalaries");

            migrationBuilder.DropColumn(
                name: "ExpectedWorkDays",
                table: "EmployeeSalaries");

            migrationBuilder.DropColumn(
                name: "LateDeduction",
                table: "EmployeeSalaries");

            migrationBuilder.DropColumn(
                name: "OvertimeBonus",
                table: "EmployeeSalaries");

            migrationBuilder.DropColumn(
                name: "PaidLeaveDays",
                table: "EmployeeSalaries");

            migrationBuilder.DropColumn(
                name: "TotalEarlyDepartureMinutes",
                table: "EmployeeSalaries");

            migrationBuilder.DropColumn(
                name: "TotalLateMinutes",
                table: "EmployeeSalaries");

            migrationBuilder.DropColumn(
                name: "TotalOvertimeMinutes",
                table: "EmployeeSalaries");

            migrationBuilder.DropColumn(
                name: "UnpaidLeaveDays",
                table: "EmployeeSalaries");

            migrationBuilder.DropColumn(
                name: "UnpaidLeaveDeduction",
                table: "EmployeeSalaries");
        }
    }
}
