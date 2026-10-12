using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddWhatsAppSettingsToCompanyFtthSettings : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "WhatsAppBulkSystem",
                table: "CompanyFtthSettings",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "WhatsAppN8nWebhookUrl",
                table: "CompanyFtthSettings",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "WhatsAppRenewalSystem",
                table: "CompanyFtthSettings",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "WhatsAppBulkSystem",
                table: "CompanyFtthSettings");

            migrationBuilder.DropColumn(
                name: "WhatsAppN8nWebhookUrl",
                table: "CompanyFtthSettings");

            migrationBuilder.DropColumn(
                name: "WhatsAppRenewalSystem",
                table: "CompanyFtthSettings");
        }
    }
}
