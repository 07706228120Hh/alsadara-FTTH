using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddFtthPartnersAndOperatorUsername : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "OperatorUsername",
                table: "SubscriptionLogs",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "PartnerId",
                table: "FtthAccounts",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "FtthPartners",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "text", nullable: false),
                    MainUsername = table.Column<string>(type: "text", nullable: false),
                    MainPasswordEncrypted = table.Column<string>(type: "text", nullable: false),
                    PartnerAccountId = table.Column<string>(type: "text", nullable: true),
                    ServerUrl = table.Column<string>(type: "text", nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    Status = table.Column<string>(type: "text", nullable: true),
                    LastVerifiedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_FtthPartners", x => x.Id);
                    table.ForeignKey(
                        name: "FK_FtthPartners_Companies_CompanyId",
                        column: x => x.CompanyId,
                        principalTable: "Companies",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_FtthAccounts_CompanyId_PartnerId",
                table: "FtthAccounts",
                columns: new[] { "CompanyId", "PartnerId" });

            migrationBuilder.CreateIndex(
                name: "IX_FtthPartners_CompanyId_Name",
                table: "FtthPartners",
                columns: new[] { "CompanyId", "Name" },
                unique: true,
                filter: "\"IsDeleted\" = false");

            migrationBuilder.CreateIndex(
                name: "IX_FtthPartners_CompanyId_PartnerAccountId",
                table: "FtthPartners",
                columns: new[] { "CompanyId", "PartnerAccountId" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "FtthPartners");

            migrationBuilder.DropIndex(
                name: "IX_FtthAccounts_CompanyId_PartnerId",
                table: "FtthAccounts");

            migrationBuilder.DropColumn(
                name: "OperatorUsername",
                table: "SubscriptionLogs");

            migrationBuilder.DropColumn(
                name: "PartnerId",
                table: "FtthAccounts");
        }
    }
}
