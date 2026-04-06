using Microsoft.EntityFrameworkCore.Migrations;

namespace Sadara.Infrastructure.Data.Migrations;

public partial class AddCustomPermissionTemplatesToCompany : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<string>(
            name: "CustomPermissionTemplates",
            table: "Companies",
            type: "text",
            nullable: true);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(name: "CustomPermissionTemplates", table: "Companies");
    }
}
