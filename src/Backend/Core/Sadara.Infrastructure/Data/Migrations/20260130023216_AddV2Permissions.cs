using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddV2Permissions : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "FirstSystemPermissionsV2",
                table: "Users",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "SecondSystemPermissionsV2",
                table: "Users",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "EnabledFirstSystemFeaturesV2",
                table: "Companies",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "EnabledSecondSystemFeaturesV2",
                table: "Companies",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "FirstSystemPermissionsV2",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "SecondSystemPermissionsV2",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "EnabledFirstSystemFeaturesV2",
                table: "Companies");

            migrationBuilder.DropColumn(
                name: "EnabledSecondSystemFeaturesV2",
                table: "Companies");
        }
    }
}
