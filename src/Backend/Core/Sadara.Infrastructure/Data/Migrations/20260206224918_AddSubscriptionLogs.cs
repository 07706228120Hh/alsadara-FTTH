using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddSubscriptionLogs : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "SubscriptionLogs",
                columns: table => new
                {
                    Id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    CustomerId = table.Column<string>(type: "text", nullable: true),
                    CustomerName = table.Column<string>(type: "text", nullable: true),
                    PhoneNumber = table.Column<string>(type: "text", nullable: true),
                    SubscriptionId = table.Column<string>(type: "text", nullable: true),
                    PlanName = table.Column<string>(type: "text", nullable: true),
                    PlanPrice = table.Column<decimal>(type: "numeric", nullable: true),
                    CommitmentPeriod = table.Column<int>(type: "integer", nullable: true),
                    BundleId = table.Column<string>(type: "text", nullable: true),
                    CurrentStatus = table.Column<string>(type: "text", nullable: true),
                    DeviceUsername = table.Column<string>(type: "text", nullable: true),
                    OperationType = table.Column<string>(type: "text", nullable: true),
                    ActivatedBy = table.Column<string>(type: "text", nullable: true),
                    ActivationDate = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    ActivationTime = table.Column<string>(type: "text", nullable: true),
                    SessionId = table.Column<string>(type: "text", nullable: true),
                    LastUpdateDate = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    ZoneId = table.Column<string>(type: "text", nullable: true),
                    ZoneName = table.Column<string>(type: "text", nullable: true),
                    FbgInfo = table.Column<string>(type: "text", nullable: true),
                    FatInfo = table.Column<string>(type: "text", nullable: true),
                    FdtInfo = table.Column<string>(type: "text", nullable: true),
                    WalletBalanceBefore = table.Column<decimal>(type: "numeric", nullable: true),
                    WalletBalanceAfter = table.Column<decimal>(type: "numeric", nullable: true),
                    PartnerWalletBalanceBefore = table.Column<decimal>(type: "numeric", nullable: true),
                    CustomerWalletBalanceBefore = table.Column<decimal>(type: "numeric", nullable: true),
                    Currency = table.Column<string>(type: "text", nullable: true),
                    PaymentMethod = table.Column<string>(type: "text", nullable: true),
                    PartnerName = table.Column<string>(type: "text", nullable: true),
                    PartnerId = table.Column<string>(type: "text", nullable: true),
                    UserId = table.Column<Guid>(type: "uuid", nullable: true),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: true),
                    IsPrinted = table.Column<bool>(type: "boolean", nullable: false),
                    IsWhatsAppSent = table.Column<bool>(type: "boolean", nullable: false),
                    SubscriptionNotes = table.Column<string>(type: "text", nullable: true),
                    StartDate = table.Column<string>(type: "text", nullable: true),
                    EndDate = table.Column<string>(type: "text", nullable: true),
                    ApiResponse = table.Column<string>(type: "text", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SubscriptionLogs", x => x.Id);
                });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "SubscriptionLogs");
        }
    }
}
