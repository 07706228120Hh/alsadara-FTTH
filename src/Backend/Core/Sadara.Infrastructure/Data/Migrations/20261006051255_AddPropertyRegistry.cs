using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddPropertyRegistry : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "Properties",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: false),
                    CreatedByUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    QrToken = table.Column<string>(type: "text", nullable: false),
                    Npn = table.Column<string>(type: "text", nullable: false),
                    NpnDisplay = table.Column<string>(type: "text", nullable: false),
                    IqPin = table.Column<string>(type: "text", nullable: true),
                    IqPinDisplay = table.Column<string>(type: "text", nullable: true),
                    GovCode = table.Column<int>(type: "integer", nullable: false),
                    Governorate = table.Column<string>(type: "text", nullable: false),
                    Area = table.Column<string>(type: "text", nullable: false),
                    District = table.Column<string>(type: "text", nullable: false),
                    Landmark = table.Column<string>(type: "text", nullable: true),
                    AddressDetails = table.Column<string>(type: "text", nullable: true),
                    Latitude = table.Column<double>(type: "double precision", nullable: true),
                    Longitude = table.Column<double>(type: "double precision", nullable: true),
                    PropertyType = table.Column<int>(type: "integer", nullable: false),
                    Ownership = table.Column<int>(type: "integer", nullable: false),
                    PhotoPath = table.Column<string>(type: "text", nullable: true),
                    Notes = table.Column<string>(type: "text", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Properties", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Properties_Companies_CompanyId",
                        column: x => x.CompanyId,
                        principalTable: "Companies",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "PropertyNpnCounters",
                columns: table => new
                {
                    GovCode = table.Column<int>(type: "integer", nullable: false),
                    LastSeq = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PropertyNpnCounters", x => x.GovCode);
                });

            migrationBuilder.CreateTable(
                name: "PropertyResidents",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: false),
                    PropertyId = table.Column<Guid>(type: "uuid", nullable: false),
                    CitizenId = table.Column<Guid>(type: "uuid", nullable: false),
                    Relationship = table.Column<int>(type: "integer", nullable: false),
                    IsPrimary = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PropertyResidents", x => x.Id);
                    table.ForeignKey(
                        name: "FK_PropertyResidents_Citizens_CitizenId",
                        column: x => x.CitizenId,
                        principalTable: "Citizens",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_PropertyResidents_Properties_PropertyId",
                        column: x => x.PropertyId,
                        principalTable: "Properties",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "PropertyServices",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: false),
                    PropertyId = table.Column<Guid>(type: "uuid", nullable: false),
                    ServiceType = table.Column<int>(type: "integer", nullable: false),
                    ProviderType = table.Column<int>(type: "integer", nullable: false),
                    ProviderRefId = table.Column<string>(type: "text", nullable: true),
                    SubscriberRef = table.Column<string>(type: "text", nullable: true),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    StartDate = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    EndDate = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    Notes = table.Column<string>(type: "text", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PropertyServices", x => x.Id);
                    table.ForeignKey(
                        name: "FK_PropertyServices_Properties_PropertyId",
                        column: x => x.PropertyId,
                        principalTable: "Properties",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Properties_CompanyId_CreatedByUserId",
                table: "Properties",
                columns: new[] { "CompanyId", "CreatedByUserId" });

            migrationBuilder.CreateIndex(
                name: "IX_Properties_CompanyId_Npn",
                table: "Properties",
                columns: new[] { "CompanyId", "Npn" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Properties_QrToken",
                table: "Properties",
                column: "QrToken",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_PropertyResidents_CitizenId",
                table: "PropertyResidents",
                column: "CitizenId");

            migrationBuilder.CreateIndex(
                name: "IX_PropertyResidents_CompanyId_PropertyId",
                table: "PropertyResidents",
                columns: new[] { "CompanyId", "PropertyId" });

            migrationBuilder.CreateIndex(
                name: "IX_PropertyResidents_PropertyId_CitizenId",
                table: "PropertyResidents",
                columns: new[] { "PropertyId", "CitizenId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_PropertyServices_CompanyId_PropertyId",
                table: "PropertyServices",
                columns: new[] { "CompanyId", "PropertyId" });

            migrationBuilder.CreateIndex(
                name: "IX_PropertyServices_PropertyId_ServiceType",
                table: "PropertyServices",
                columns: new[] { "PropertyId", "ServiceType" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "PropertyNpnCounters");

            migrationBuilder.DropTable(
                name: "PropertyResidents");

            migrationBuilder.DropTable(
                name: "PropertyServices");

            migrationBuilder.DropTable(
                name: "Properties");
        }
    }
}
