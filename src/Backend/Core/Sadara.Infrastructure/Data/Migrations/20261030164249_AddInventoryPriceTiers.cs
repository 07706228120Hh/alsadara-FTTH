using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddInventoryPriceTiers : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<decimal>(
                name: "BulkWholesaleMarginPercent",
                table: "InventoryItems",
                type: "numeric(5,2)",
                precision: 5,
                scale: 2,
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "BulkWholesalePrice",
                table: "InventoryItems",
                type: "numeric(18,2)",
                precision: 18,
                scale: 2,
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "RetailMarginPercent",
                table: "InventoryItems",
                type: "numeric(5,2)",
                precision: 5,
                scale: 2,
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "WholesaleMarginPercent",
                table: "InventoryItems",
                type: "numeric(5,2)",
                precision: 5,
                scale: 2,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "PriceTier",
                table: "InventoryCustomers",
                type: "integer",
                nullable: false,
                defaultValue: 0);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "BulkWholesaleMarginPercent",
                table: "InventoryItems");

            migrationBuilder.DropColumn(
                name: "BulkWholesalePrice",
                table: "InventoryItems");

            migrationBuilder.DropColumn(
                name: "RetailMarginPercent",
                table: "InventoryItems");

            migrationBuilder.DropColumn(
                name: "WholesaleMarginPercent",
                table: "InventoryItems");

            migrationBuilder.DropColumn(
                name: "PriceTier",
                table: "InventoryCustomers");
        }
    }
}
