using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddEmployeeDeductionBonusAndSalaryFields : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<decimal>(
                name: "ManualBonuses",
                table: "EmployeeSalaries",
                type: "numeric(18,2)",
                precision: 18,
                scale: 2,
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<decimal>(
                name: "ManualDeductions",
                table: "EmployeeSalaries",
                type: "numeric(18,2)",
                precision: 18,
                scale: 2,
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.CreateTable(
                name: "EmployeeDeductionBonuses",
                columns: table => new
                {
                    Id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: false),
                    Type = table.Column<int>(type: "integer", nullable: false),
                    Category = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    Amount = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    Month = table.Column<int>(type: "integer", nullable: false),
                    Year = table.Column<int>(type: "integer", nullable: false),
                    Description = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: false),
                    Notes = table.Column<string>(type: "text", nullable: true),
                    IsApplied = table.Column<bool>(type: "boolean", nullable: false),
                    AppliedToSalaryId = table.Column<long>(type: "bigint", nullable: true),
                    CreatedById = table.Column<Guid>(type: "uuid", nullable: false),
                    IsRecurring = table.Column<bool>(type: "boolean", nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EmployeeDeductionBonuses", x => x.Id);
                    table.ForeignKey(
                        name: "FK_EmployeeDeductionBonuses_Companies_CompanyId",
                        column: x => x.CompanyId,
                        principalTable: "Companies",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_EmployeeDeductionBonuses_EmployeeSalaries_AppliedToSalaryId",
                        column: x => x.AppliedToSalaryId,
                        principalTable: "EmployeeSalaries",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_EmployeeDeductionBonuses_Users_CreatedById",
                        column: x => x.CreatedById,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_EmployeeDeductionBonuses_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_EmployeeDeductionBonuses_AppliedToSalaryId",
                table: "EmployeeDeductionBonuses",
                column: "AppliedToSalaryId");

            migrationBuilder.CreateIndex(
                name: "IX_EmployeeDeductionBonuses_CompanyId",
                table: "EmployeeDeductionBonuses",
                column: "CompanyId");

            migrationBuilder.CreateIndex(
                name: "IX_EmployeeDeductionBonuses_CreatedById",
                table: "EmployeeDeductionBonuses",
                column: "CreatedById");

            migrationBuilder.CreateIndex(
                name: "IX_EmployeeDeductionBonuses_Type",
                table: "EmployeeDeductionBonuses",
                column: "Type");

            migrationBuilder.CreateIndex(
                name: "IX_EmployeeDeductionBonuses_UserId_Year_Month",
                table: "EmployeeDeductionBonuses",
                columns: new[] { "UserId", "Year", "Month" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "EmployeeDeductionBonuses");

            migrationBuilder.DropColumn(
                name: "ManualBonuses",
                table: "EmployeeSalaries");

            migrationBuilder.DropColumn(
                name: "ManualDeductions",
                table: "EmployeeSalaries");
        }
    }
}
