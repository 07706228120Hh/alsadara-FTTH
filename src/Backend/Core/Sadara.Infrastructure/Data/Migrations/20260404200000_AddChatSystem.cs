using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations;

/// <summary>
/// إنشاء جداول نظام المحادثة الداخلي
/// </summary>
public partial class AddChatSystem : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        // ═══ ChatRooms ═══
        migrationBuilder.CreateTable(
            name: "ChatRooms",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                CompanyId = table.Column<Guid>(type: "uuid", nullable: false),
                Type = table.Column<int>(type: "integer", nullable: false),
                DepartmentId = table.Column<int>(type: "integer", nullable: true),
                Name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                AvatarUrl = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                CreatedByUserId = table.Column<Guid>(type: "uuid", nullable: false),
                LastMessageAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                LastMessagePreview = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: true),
                LastMessageSenderName = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_ChatRooms", x => x.Id);
                table.ForeignKey("FK_ChatRooms_Companies_CompanyId", x => x.CompanyId, "Companies", "Id", onDelete: ReferentialAction.Cascade);
                table.ForeignKey("FK_ChatRooms_Departments_DepartmentId", x => x.DepartmentId, "Departments", "Id", onDelete: ReferentialAction.SetNull);
                table.ForeignKey("FK_ChatRooms_Users_CreatedByUserId", x => x.CreatedByUserId, "Users", "Id", onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex("IX_ChatRooms_CompanyId", "ChatRooms", "CompanyId");
        migrationBuilder.CreateIndex("IX_ChatRooms_DepartmentId", "ChatRooms", "DepartmentId");
        migrationBuilder.CreateIndex("IX_ChatRooms_LastMessageAt", "ChatRooms", "LastMessageAt");
        migrationBuilder.CreateIndex("IX_ChatRooms_Type", "ChatRooms", "Type");

        // ═══ ChatRoomMembers ═══
        migrationBuilder.CreateTable(
            name: "ChatRoomMembers",
            columns: table => new
            {
                Id = table.Column<long>(type: "bigint", nullable: false)
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                ChatRoomId = table.Column<Guid>(type: "uuid", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false),
                JoinedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                LastReadAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                IsMuted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                IsAdmin = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_ChatRoomMembers", x => x.Id);
                table.ForeignKey("FK_ChatRoomMembers_ChatRooms_ChatRoomId", x => x.ChatRoomId, "ChatRooms", "Id", onDelete: ReferentialAction.Cascade);
                table.ForeignKey("FK_ChatRoomMembers_Users_UserId", x => x.UserId, "Users", "Id", onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex("IX_ChatRoomMembers_ChatRoomId", "ChatRoomMembers", "ChatRoomId");
        migrationBuilder.CreateIndex("IX_ChatRoomMembers_UserId", "ChatRoomMembers", "UserId");
        migrationBuilder.CreateIndex("IX_ChatRoomMembers_Unique", "ChatRoomMembers", new[] { "ChatRoomId", "UserId" }, unique: true);

        // ═══ ChatMessages ═══
        migrationBuilder.CreateTable(
            name: "ChatMessages",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                ChatRoomId = table.Column<Guid>(type: "uuid", nullable: false),
                SenderId = table.Column<Guid>(type: "uuid", nullable: false),
                MessageType = table.Column<int>(type: "integer", nullable: false),
                Content = table.Column<string>(type: "text", nullable: true),
                ReplyToMessageId = table.Column<Guid>(type: "uuid", nullable: true),
                IsForwarded = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_ChatMessages", x => x.Id);
                table.ForeignKey("FK_ChatMessages_ChatRooms_ChatRoomId", x => x.ChatRoomId, "ChatRooms", "Id", onDelete: ReferentialAction.Cascade);
                table.ForeignKey("FK_ChatMessages_Users_SenderId", x => x.SenderId, "Users", "Id", onDelete: ReferentialAction.Cascade);
                table.ForeignKey("FK_ChatMessages_ChatMessages_ReplyToMessageId", x => x.ReplyToMessageId, "ChatMessages", "Id", onDelete: ReferentialAction.SetNull);
            });

        migrationBuilder.CreateIndex("IX_ChatMessages_ChatRoomId_CreatedAt", "ChatMessages", new[] { "ChatRoomId", "CreatedAt" });
        migrationBuilder.CreateIndex("IX_ChatMessages_SenderId", "ChatMessages", "SenderId");
        migrationBuilder.CreateIndex("IX_ChatMessages_ReplyToMessageId", "ChatMessages", "ReplyToMessageId");

        // ═══ ChatAttachments ═══
        migrationBuilder.CreateTable(
            name: "ChatAttachments",
            columns: table => new
            {
                Id = table.Column<long>(type: "bigint", nullable: false)
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                ChatMessageId = table.Column<Guid>(type: "uuid", nullable: false),
                FileName = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: false),
                FilePath = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: false),
                FileSize = table.Column<long>(type: "bigint", nullable: false),
                MimeType = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                ThumbnailPath = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                DurationSeconds = table.Column<int>(type: "integer", nullable: true),
                CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_ChatAttachments", x => x.Id);
                table.ForeignKey("FK_ChatAttachments_ChatMessages_ChatMessageId", x => x.ChatMessageId, "ChatMessages", "Id", onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex("IX_ChatAttachments_ChatMessageId", "ChatAttachments", "ChatMessageId");

        // ═══ ChatMentions ═══
        migrationBuilder.CreateTable(
            name: "ChatMentions",
            columns: table => new
            {
                Id = table.Column<long>(type: "bigint", nullable: false)
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                ChatMessageId = table.Column<Guid>(type: "uuid", nullable: false),
                MentionedUserId = table.Column<Guid>(type: "uuid", nullable: false),
                IsNotified = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_ChatMentions", x => x.Id);
                table.ForeignKey("FK_ChatMentions_ChatMessages_ChatMessageId", x => x.ChatMessageId, "ChatMessages", "Id", onDelete: ReferentialAction.Cascade);
                table.ForeignKey("FK_ChatMentions_Users_MentionedUserId", x => x.MentionedUserId, "Users", "Id", onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex("IX_ChatMentions_ChatMessageId", "ChatMentions", "ChatMessageId");
        migrationBuilder.CreateIndex("IX_ChatMentions_MentionedUserId", "ChatMentions", "MentionedUserId");

        // ═══ ChatMessageReads ═══
        migrationBuilder.CreateTable(
            name: "ChatMessageReads",
            columns: table => new
            {
                Id = table.Column<long>(type: "bigint", nullable: false)
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                ChatMessageId = table.Column<Guid>(type: "uuid", nullable: false),
                UserId = table.Column<Guid>(type: "uuid", nullable: false),
                ReadAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_ChatMessageReads", x => x.Id);
                table.ForeignKey("FK_ChatMessageReads_ChatMessages_ChatMessageId", x => x.ChatMessageId, "ChatMessages", "Id", onDelete: ReferentialAction.Cascade);
                table.ForeignKey("FK_ChatMessageReads_Users_UserId", x => x.UserId, "Users", "Id", onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex("IX_ChatMessageReads_Unique", "ChatMessageReads", new[] { "ChatMessageId", "UserId" }, unique: true);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(name: "ChatMessageReads");
        migrationBuilder.DropTable(name: "ChatMentions");
        migrationBuilder.DropTable(name: "ChatAttachments");
        migrationBuilder.DropTable(name: "ChatMessages");
        migrationBuilder.DropTable(name: "ChatRoomMembers");
        migrationBuilder.DropTable(name: "ChatRooms");
    }
}
