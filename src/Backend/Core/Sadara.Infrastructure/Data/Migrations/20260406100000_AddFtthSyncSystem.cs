using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations;

/// <summary>
/// إنشاء جداول نظام مزامنة FTTH
/// CompanyFtthSettings: إعدادات المزامنة لكل شركة
/// FtthSubscriberCaches: كاش بيانات المشتركين
/// FtthSyncLogs: سجل عمليات المزامنة
/// </summary>
public partial class AddFtthSyncSystem : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        // ═══ CompanyFtthSettings ═══
        migrationBuilder.CreateTable(
            name: "CompanyFtthSettings",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                CompanyId = table.Column<Guid>(type: "uuid", nullable: false),
                FtthUsername = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                FtthPassword = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: false),
                SyncIntervalMinutes = table.Column<int>(type: "integer", nullable: false, defaultValue: 60),
                IsAutoSyncEnabled = table.Column<bool>(type: "boolean", nullable: false, defaultValue: true),
                SyncStartHour = table.Column<int>(type: "integer", nullable: false, defaultValue: 6),
                SyncEndHour = table.Column<int>(type: "integer", nullable: false, defaultValue: 23),
                LastSyncAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                LastSyncError = table.Column<string>(type: "text", nullable: true),
                IsSyncInProgress = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                CurrentDbCount = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                ConsecutiveFailures = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_CompanyFtthSettings", x => x.Id);
                table.ForeignKey("FK_CompanyFtthSettings_Companies_CompanyId", x => x.CompanyId, "Companies", "Id", onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex("IX_CompanyFtthSettings_CompanyId", "CompanyFtthSettings", "CompanyId", unique: true);

        // ═══ FtthSubscriberCaches ═══
        migrationBuilder.CreateTable(
            name: "FtthSubscriberCaches",
            columns: table => new
            {
                Id = table.Column<long>(type: "bigint", nullable: false)
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                CompanyId = table.Column<Guid>(type: "uuid", nullable: false),
                SubscriptionId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                CustomerId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                Username = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                DisplayName = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: false),
                Status = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                AutoRenew = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                ProfileName = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: false),
                BundleId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                ZoneId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                ZoneName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                StartedAt = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                Expires = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                CommitmentPeriod = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                Phone = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                LockedMac = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                FdtName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                FatName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                DeviceSerial = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                GpsLat = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: true),
                GpsLng = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: true),
                IsTrial = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                IsPending = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                IsSuspended = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                SuspensionReason = table.Column<string>(type: "text", nullable: true),
                DetailsFetched = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                DetailsFetchedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                ServicesJson = table.Column<string>(type: "jsonb", nullable: true),
                CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_FtthSubscriberCaches", x => x.Id);
                table.ForeignKey("FK_FtthSubscriberCaches_Companies_CompanyId", x => x.CompanyId, "Companies", "Id", onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex("IX_FtthSubscriberCaches_CompanyId_SubscriptionId", "FtthSubscriberCaches", new[] { "CompanyId", "SubscriptionId" }, unique: true);
        migrationBuilder.CreateIndex("IX_FtthSubscriberCaches_CompanyId_CustomerId", "FtthSubscriberCaches", new[] { "CompanyId", "CustomerId" });
        migrationBuilder.CreateIndex("IX_FtthSubscriberCaches_CompanyId_UpdatedAt", "FtthSubscriberCaches", new[] { "CompanyId", "UpdatedAt" });
        migrationBuilder.CreateIndex("IX_FtthSubscriberCaches_CompanyId_ZoneName", "FtthSubscriberCaches", new[] { "CompanyId", "ZoneName" });
        migrationBuilder.CreateIndex("IX_FtthSubscriberCaches_CompanyId_Status", "FtthSubscriberCaches", new[] { "CompanyId", "Status" });

        // ═══ FtthSyncLogs ═══
        migrationBuilder.CreateTable(
            name: "FtthSyncLogs",
            columns: table => new
            {
                Id = table.Column<long>(type: "bigint", nullable: false)
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                CompanyId = table.Column<Guid>(type: "uuid", nullable: false),
                StartedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                CompletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                Status = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                SubscribersCount = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                PhonesCount = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                DetailsCount = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                NewCount = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                UpdatedCount = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                ErrorMessage = table.Column<string>(type: "text", nullable: true),
                DurationSeconds = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                IsIncremental = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                TriggerSource = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false, defaultValue: "Auto"),
                CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_FtthSyncLogs", x => x.Id);
                table.ForeignKey("FK_FtthSyncLogs_Companies_CompanyId", x => x.CompanyId, "Companies", "Id", onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex("IX_FtthSyncLogs_CompanyId_StartedAt", "FtthSyncLogs", new[] { "CompanyId", "StartedAt" });
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(name: "FtthSyncLogs");
        migrationBuilder.DropTable(name: "FtthSubscriberCaches");
        migrationBuilder.DropTable(name: "CompanyFtthSettings");
    }
}
