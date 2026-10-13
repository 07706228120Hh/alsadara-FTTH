using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddPropertyQrTokens : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "PropertyQrTokens",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: false),
                    CreatedByUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    BatchId = table.Column<Guid>(type: "uuid", nullable: false),
                    Serial = table.Column<int>(type: "integer", nullable: false),
                    QrToken = table.Column<string>(type: "text", nullable: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    PropertyId = table.Column<Guid>(type: "uuid", nullable: true),
                    Note = table.Column<string>(type: "text", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PropertyQrTokens", x => x.Id);
                    table.ForeignKey(
                        name: "FK_PropertyQrTokens_Companies_CompanyId",
                        column: x => x.CompanyId,
                        principalTable: "Companies",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_PropertyQrTokens_Properties_PropertyId",
                        column: x => x.PropertyId,
                        principalTable: "Properties",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateIndex(
                name: "IX_PropertyQrTokens_CompanyId_BatchId",
                table: "PropertyQrTokens",
                columns: new[] { "CompanyId", "BatchId" });

            migrationBuilder.CreateIndex(
                name: "IX_PropertyQrTokens_CompanyId_Status",
                table: "PropertyQrTokens",
                columns: new[] { "CompanyId", "Status" });

            migrationBuilder.CreateIndex(
                name: "IX_PropertyQrTokens_PropertyId",
                table: "PropertyQrTokens",
                column: "PropertyId");

            migrationBuilder.CreateIndex(
                name: "IX_PropertyQrTokens_QrToken",
                table: "PropertyQrTokens",
                column: "QrToken",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "PropertyQrTokens");
        }
    }
}
