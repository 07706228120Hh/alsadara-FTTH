using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddPropertyOwnerAndServiceFields : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "AccountNumber",
                table: "PropertyServices",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "AgentName",
                table: "PropertyServices",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "CivilIdPhotoPath",
                table: "PropertyServices",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "MasterPhotoPath",
                table: "PropertyServices",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Address2",
                table: "Properties",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Address3",
                table: "Properties",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "OwnerName",
                table: "Properties",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "OwnerPhone",
                table: "Properties",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "AccountNumber",
                table: "PropertyServices");

            migrationBuilder.DropColumn(
                name: "AgentName",
                table: "PropertyServices");

            migrationBuilder.DropColumn(
                name: "CivilIdPhotoPath",
                table: "PropertyServices");

            migrationBuilder.DropColumn(
                name: "MasterPhotoPath",
                table: "PropertyServices");

            migrationBuilder.DropColumn(
                name: "Address2",
                table: "Properties");

            migrationBuilder.DropColumn(
                name: "Address3",
                table: "Properties");

            migrationBuilder.DropColumn(
                name: "OwnerName",
                table: "Properties");

            migrationBuilder.DropColumn(
                name: "OwnerPhone",
                table: "Properties");
        }
    }
}
