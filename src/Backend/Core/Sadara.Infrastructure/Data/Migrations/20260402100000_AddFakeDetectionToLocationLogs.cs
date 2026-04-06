using Microsoft.EntityFrameworkCore.Migrations;

namespace Sadara.Infrastructure.Data.Migrations;

public partial class AddFakeDetectionToLocationLogs : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<double>(
            name: "Accuracy",
            table: "EmployeeLocationLogs",
            type: "double precision",
            nullable: true);

        migrationBuilder.AddColumn<double>(
            name: "Altitude",
            table: "EmployeeLocationLogs",
            type: "double precision",
            nullable: true);

        migrationBuilder.AddColumn<double>(
            name: "Speed",
            table: "EmployeeLocationLogs",
            type: "double precision",
            nullable: true);

        migrationBuilder.AddColumn<bool>(
            name: "IsMocked",
            table: "EmployeeLocationLogs",
            type: "boolean",
            nullable: false,
            defaultValue: false);

        migrationBuilder.AddColumn<bool>(
            name: "IsFakeDetected",
            table: "EmployeeLocationLogs",
            type: "boolean",
            nullable: false,
            defaultValue: false);

        migrationBuilder.AddColumn<string>(
            name: "FakeReasons",
            table: "EmployeeLocationLogs",
            type: "text",
            nullable: true);

        migrationBuilder.AddColumn<int>(
            name: "TeleportCount",
            table: "EmployeeLocationLogs",
            type: "integer",
            nullable: false,
            defaultValue: 0);

        migrationBuilder.AddColumn<int>(
            name: "FakeFlagCount",
            table: "EmployeeLocationLogs",
            type: "integer",
            nullable: false,
            defaultValue: 0);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(name: "Accuracy", table: "EmployeeLocationLogs");
        migrationBuilder.DropColumn(name: "Altitude", table: "EmployeeLocationLogs");
        migrationBuilder.DropColumn(name: "Speed", table: "EmployeeLocationLogs");
        migrationBuilder.DropColumn(name: "IsMocked", table: "EmployeeLocationLogs");
        migrationBuilder.DropColumn(name: "IsFakeDetected", table: "EmployeeLocationLogs");
        migrationBuilder.DropColumn(name: "FakeReasons", table: "EmployeeLocationLogs");
        migrationBuilder.DropColumn(name: "TeleportCount", table: "EmployeeLocationLogs");
        migrationBuilder.DropColumn(name: "FakeFlagCount", table: "EmployeeLocationLogs");
    }
}
