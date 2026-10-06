using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddPropertyLocationHierarchy : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "Address2Id",
                table: "Properties",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "Address3Id",
                table: "Properties",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "RegionId",
                table: "Properties",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "PropertyAddress2s",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: false),
                    RegionId = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "text", nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PropertyAddress2s", x => x.Id);
                    table.ForeignKey(
                        name: "FK_PropertyAddress2s_SasRegions_RegionId",
                        column: x => x.RegionId,
                        principalTable: "SasRegions",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "PropertyAddress3s",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: false),
                    Address2Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "text", nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PropertyAddress3s", x => x.Id);
                    table.ForeignKey(
                        name: "FK_PropertyAddress3s_PropertyAddress2s_Address2Id",
                        column: x => x.Address2Id,
                        principalTable: "PropertyAddress2s",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Properties_Address2Id",
                table: "Properties",
                column: "Address2Id");

            migrationBuilder.CreateIndex(
                name: "IX_Properties_Address3Id",
                table: "Properties",
                column: "Address3Id");

            migrationBuilder.CreateIndex(
                name: "IX_Properties_RegionId",
                table: "Properties",
                column: "RegionId");

            migrationBuilder.CreateIndex(
                name: "IX_PropertyAddress2s_CompanyId_RegionId",
                table: "PropertyAddress2s",
                columns: new[] { "CompanyId", "RegionId" });

            migrationBuilder.CreateIndex(
                name: "IX_PropertyAddress2s_RegionId",
                table: "PropertyAddress2s",
                column: "RegionId");

            migrationBuilder.CreateIndex(
                name: "IX_PropertyAddress3s_Address2Id",
                table: "PropertyAddress3s",
                column: "Address2Id");

            migrationBuilder.CreateIndex(
                name: "IX_PropertyAddress3s_CompanyId_Address2Id",
                table: "PropertyAddress3s",
                columns: new[] { "CompanyId", "Address2Id" });

            migrationBuilder.AddForeignKey(
                name: "FK_Properties_PropertyAddress2s_Address2Id",
                table: "Properties",
                column: "Address2Id",
                principalTable: "PropertyAddress2s",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);

            migrationBuilder.AddForeignKey(
                name: "FK_Properties_PropertyAddress3s_Address3Id",
                table: "Properties",
                column: "Address3Id",
                principalTable: "PropertyAddress3s",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);

            migrationBuilder.AddForeignKey(
                name: "FK_Properties_SasRegions_RegionId",
                table: "Properties",
                column: "RegionId",
                principalTable: "SasRegions",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_Properties_PropertyAddress2s_Address2Id",
                table: "Properties");

            migrationBuilder.DropForeignKey(
                name: "FK_Properties_PropertyAddress3s_Address3Id",
                table: "Properties");

            migrationBuilder.DropForeignKey(
                name: "FK_Properties_SasRegions_RegionId",
                table: "Properties");

            migrationBuilder.DropTable(
                name: "PropertyAddress3s");

            migrationBuilder.DropTable(
                name: "PropertyAddress2s");

            migrationBuilder.DropIndex(
                name: "IX_Properties_Address2Id",
                table: "Properties");

            migrationBuilder.DropIndex(
                name: "IX_Properties_Address3Id",
                table: "Properties");

            migrationBuilder.DropIndex(
                name: "IX_Properties_RegionId",
                table: "Properties");

            migrationBuilder.DropColumn(
                name: "Address2Id",
                table: "Properties");

            migrationBuilder.DropColumn(
                name: "Address3Id",
                table: "Properties");

            migrationBuilder.DropColumn(
                name: "RegionId",
                table: "Properties");
        }
    }
}
