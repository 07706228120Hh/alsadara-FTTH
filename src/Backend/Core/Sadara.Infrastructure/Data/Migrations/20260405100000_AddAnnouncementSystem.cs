using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations;

/// <summary>
/// إنشاء جداول نظام الإعلانات والتبليغات
/// </summary>
public partial class AddAnnouncementSystem : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        // ═══ Announcements ═══
        migrationBuilder.CreateTable(
            name: "Announcements",
            columns: table => new
            {
                Id = table.Column<long>(type: "bigint", nullable: false)
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                CompanyId = table.Column<Guid>(type: "uuid", nullable: false),
                Title = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: false),
                Body = table.Column<string>(type: "text", nullable: false),
                ImageUrl = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                TargetType = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                TargetValue = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                IsPublished = table.Column<bool>(type: "boolean", nullable: false, defaultValue: true),
                ExpiresAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                CreatedByUserId = table.Column<Guid>(type: "uuid", nullable: false),
                CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "NOW()"),
                UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_Announcements", x => x.Id);
                table.ForeignKey("FK_Announcements_Companies_CompanyId", x => x.CompanyId, "Companies", "Id", onDelete: ReferentialAction.Cascade);
                table.ForeignKey("FK_Announcements_Users_CreatedByUserId", x => x.CreatedByUserId, "Users", "Id", onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex("IX_Announcements_CompanyId_IsPublished_CreatedAt", "Announcements", new[] { "CompanyId", "IsPublished", "CreatedAt" });

        // ═══ AnnouncementTargets ═══
        migrationBuilder.CreateTable(
            name: "AnnouncementTargets",
            columns: table => new
            {
                Id = table.Column<long>(type: "bigint", nullable: false)
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                AnnouncementId = table.Column<long>(type: "bigint", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false),
                CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "NOW()"),
                UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_AnnouncementTargets", x => x.Id);
                table.ForeignKey("FK_AnnouncementTargets_Announcements_AnnouncementId", x => x.AnnouncementId, "Announcements", "Id", onDelete: ReferentialAction.Cascade);
                table.ForeignKey("FK_AnnouncementTargets_Users_UserId", x => x.UserId, "Users", "Id", onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex("IX_AnnouncementTargets_AnnouncementId_UserId", "AnnouncementTargets", new[] { "AnnouncementId", "UserId" }, unique: true);

        // ═══ AnnouncementReads ═══
        migrationBuilder.CreateTable(
            name: "AnnouncementReads",
            columns: table => new
            {
                Id = table.Column<long>(type: "bigint", nullable: false)
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                AnnouncementId = table.Column<long>(type: "bigint", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false),
                ReadAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "NOW()"),
                CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "NOW()"),
                UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_AnnouncementReads", x => x.Id);
                table.ForeignKey("FK_AnnouncementReads_Announcements_AnnouncementId", x => x.AnnouncementId, "Announcements", "Id", onDelete: ReferentialAction.Cascade);
                table.ForeignKey("FK_AnnouncementReads_Users_UserId", x => x.UserId, "Users", "Id", onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex("IX_AnnouncementReads_AnnouncementId_UserId", "AnnouncementReads", new[] { "AnnouncementId", "UserId" }, unique: true);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(name: "AnnouncementReads");
        migrationBuilder.DropTable(name: "AnnouncementTargets");
        migrationBuilder.DropTable(name: "Announcements");
    }
}
