using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddInvoiceItemExpiryBatch : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "BatchNumber",
                table: "InvoiceItems",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "ExpiryDate",
                table: "InvoiceItems",
                type: "timestamp with time zone",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "BatchNumber",
                table: "InvoiceItems");

            migrationBuilder.DropColumn(
                name: "ExpiryDate",
                table: "InvoiceItems");
        }
    }
}
