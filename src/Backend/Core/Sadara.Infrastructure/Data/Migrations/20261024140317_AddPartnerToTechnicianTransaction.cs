using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddPartnerToTechnicianTransaction : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "OperatorUsername",
                table: "TechnicianTransactions",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "PartnerId",
                table: "TechnicianTransactions",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "OperatorUsername",
                table: "TechnicianTransactions");

            migrationBuilder.DropColumn(
                name: "PartnerId",
                table: "TechnicianTransactions");
        }
    }
}
