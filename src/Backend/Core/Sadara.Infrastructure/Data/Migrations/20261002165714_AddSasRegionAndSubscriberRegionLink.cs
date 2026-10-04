using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddSasRegionAndSubscriberRegionLink : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "RegionId",
                table: "SasSubscriberProfiles",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "SasRegions",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "text", nullable: false),
                    Code = table.Column<string>(type: "text", nullable: true),
                    Governorate = table.Column<string>(type: "text", nullable: true),
                    City = table.Column<string>(type: "text", nullable: true),
                    MaintenanceFee = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    Notes = table.Column<string>(type: "text", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SasRegions", x => x.Id);
                    table.ForeignKey(
                        name: "FK_SasRegions_Companies_CompanyId",
                        column: x => x.CompanyId,
                        principalTable: "Companies",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_SasSubscriberProfiles_CompanyId_RegionId",
                table: "SasSubscriberProfiles",
                columns: new[] { "CompanyId", "RegionId" });

            migrationBuilder.CreateIndex(
                name: "IX_SasSubscriberProfiles_RegionId",
                table: "SasSubscriberProfiles",
                column: "RegionId");

            migrationBuilder.CreateIndex(
                name: "IX_SasRegions_CompanyId_Name",
                table: "SasRegions",
                columns: new[] { "CompanyId", "Name" },
                unique: true);

            migrationBuilder.AddForeignKey(
                name: "FK_SasSubscriberProfiles_SasRegions_RegionId",
                table: "SasSubscriberProfiles",
                column: "RegionId",
                principalTable: "SasRegions",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_SasSubscriberProfiles_SasRegions_RegionId",
                table: "SasSubscriberProfiles");

            migrationBuilder.DropTable(
                name: "SasRegions");

            migrationBuilder.DropIndex(
                name: "IX_SasSubscriberProfiles_CompanyId_RegionId",
                table: "SasSubscriberProfiles");

            migrationBuilder.DropIndex(
                name: "IX_SasSubscriberProfiles_RegionId",
                table: "SasSubscriberProfiles");

            migrationBuilder.DropColumn(
                name: "RegionId",
                table: "SasSubscriberProfiles");
        }
    }
}
