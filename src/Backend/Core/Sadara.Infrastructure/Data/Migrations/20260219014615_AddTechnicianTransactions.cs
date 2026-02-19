using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddTechnicianTransactions : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<decimal>(
                name: "TechNetBalance",
                table: "Users",
                type: "numeric",
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<decimal>(
                name: "TechTotalCharges",
                table: "Users",
                type: "numeric",
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<decimal>(
                name: "TechTotalPayments",
                table: "Users",
                type: "numeric",
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.CreateTable(
                name: "TechnicianTransactions",
                columns: table => new
                {
                    Id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    TechnicianId = table.Column<Guid>(type: "uuid", nullable: false),
                    Type = table.Column<int>(type: "integer", nullable: false),
                    Category = table.Column<int>(type: "integer", nullable: false),
                    Amount = table.Column<decimal>(type: "numeric", nullable: false),
                    BalanceAfter = table.Column<decimal>(type: "numeric", nullable: false),
                    Description = table.Column<string>(type: "text", nullable: false),
                    ReferenceNumber = table.Column<string>(type: "text", nullable: true),
                    ServiceRequestId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedById = table.Column<Guid>(type: "uuid", nullable: true),
                    Notes = table.Column<string>(type: "text", nullable: true),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TechnicianTransactions", x => x.Id);
                    table.ForeignKey(
                        name: "FK_TechnicianTransactions_Companies_CompanyId",
                        column: x => x.CompanyId,
                        principalTable: "Companies",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_TechnicianTransactions_ServiceRequests_ServiceRequestId",
                        column: x => x.ServiceRequestId,
                        principalTable: "ServiceRequests",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_TechnicianTransactions_Users_TechnicianId",
                        column: x => x.TechnicianId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_TechnicianTransactions_CompanyId",
                table: "TechnicianTransactions",
                column: "CompanyId");

            migrationBuilder.CreateIndex(
                name: "IX_TechnicianTransactions_ServiceRequestId",
                table: "TechnicianTransactions",
                column: "ServiceRequestId");

            migrationBuilder.CreateIndex(
                name: "IX_TechnicianTransactions_TechnicianId",
                table: "TechnicianTransactions",
                column: "TechnicianId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "TechnicianTransactions");

            migrationBuilder.DropColumn(
                name: "TechNetBalance",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "TechTotalCharges",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "TechTotalPayments",
                table: "Users");
        }
    }
}
