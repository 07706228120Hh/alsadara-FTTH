using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddAttendanceISPSubscriberZoneStatisticEntities : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_ServiceRequests_Citizens_CitizenId1",
                table: "ServiceRequests");

            migrationBuilder.DropForeignKey(
                name: "FK_ServiceRequests_Users_CitizenId",
                table: "ServiceRequests");

            migrationBuilder.DropForeignKey(
                name: "FK_ServiceRequestStatusHistories_Users_ChangedById",
                table: "ServiceRequestStatusHistories");

            migrationBuilder.DropIndex(
                name: "IX_ServiceRequests_CitizenId1",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "CitizenId1",
                table: "ServiceRequests");

            migrationBuilder.AddColumn<string>(
                name: "PaymentStatus",
                table: "SubscriptionLogs",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "TechnicianName",
                table: "SubscriptionLogs",
                type: "text",
                nullable: true);

            migrationBuilder.AlterColumn<Guid>(
                name: "ChangedById",
                table: "ServiceRequestStatusHistories",
                type: "uuid",
                nullable: true,
                oldClrType: typeof(Guid),
                oldType: "uuid");

            migrationBuilder.AlterColumn<Guid>(
                name: "CitizenId",
                table: "ServiceRequests",
                type: "uuid",
                nullable: true,
                oldClrType: typeof(Guid),
                oldType: "uuid");

            migrationBuilder.AddColumn<Guid>(
                name: "AgentId",
                table: "ServiceRequests",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "AttendanceRecords",
                columns: table => new
                {
                    Id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    UserName = table.Column<string>(type: "text", nullable: false),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: true),
                    Date = table.Column<DateOnly>(type: "date", nullable: false),
                    CheckInTime = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    CheckOutTime = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    CenterName = table.Column<string>(type: "text", nullable: true),
                    CheckInLatitude = table.Column<double>(type: "double precision", nullable: true),
                    CheckInLongitude = table.Column<double>(type: "double precision", nullable: true),
                    CheckOutLatitude = table.Column<double>(type: "double precision", nullable: true),
                    CheckOutLongitude = table.Column<double>(type: "double precision", nullable: true),
                    SecurityCode = table.Column<string>(type: "text", nullable: true),
                    Notes = table.Column<string>(type: "text", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AttendanceRecords", x => x.Id);
                    table.ForeignKey(
                        name: "FK_AttendanceRecords_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "ISPSubscribers",
                columns: table => new
                {
                    Id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Name = table.Column<string>(type: "text", nullable: false),
                    Region = table.Column<string>(type: "text", nullable: true),
                    Agent = table.Column<string>(type: "text", nullable: true),
                    Dash = table.Column<string>(type: "text", nullable: true),
                    MotherName = table.Column<string>(type: "text", nullable: true),
                    PhoneNumber = table.Column<string>(type: "text", nullable: true),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ISPSubscribers", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "WorkCenters",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Name = table.Column<string>(type: "text", nullable: false),
                    Latitude = table.Column<double>(type: "double precision", nullable: false),
                    Longitude = table.Column<double>(type: "double precision", nullable: false),
                    RadiusMeters = table.Column<double>(type: "double precision", nullable: false),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: true),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_WorkCenters", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "ZoneStatistics",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    ZoneName = table.Column<string>(type: "text", nullable: false),
                    Fats = table.Column<int>(type: "integer", nullable: false),
                    TotalUsers = table.Column<int>(type: "integer", nullable: false),
                    ActiveUsers = table.Column<int>(type: "integer", nullable: false),
                    InactiveUsers = table.Column<int>(type: "integer", nullable: false),
                    RegionName = table.Column<string>(type: "text", nullable: true),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ZoneStatistics", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ServiceRequests_AgentId",
                table: "ServiceRequests",
                column: "AgentId");

            migrationBuilder.CreateIndex(
                name: "IX_AttendanceRecords_UserId",
                table: "AttendanceRecords",
                column: "UserId");

            migrationBuilder.AddForeignKey(
                name: "FK_ServiceRequests_Agents_AgentId",
                table: "ServiceRequests",
                column: "AgentId",
                principalTable: "Agents",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);

            migrationBuilder.AddForeignKey(
                name: "FK_ServiceRequests_Users_CitizenId",
                table: "ServiceRequests",
                column: "CitizenId",
                principalTable: "Users",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);

            migrationBuilder.AddForeignKey(
                name: "FK_ServiceRequestStatusHistories_Users_ChangedById",
                table: "ServiceRequestStatusHistories",
                column: "ChangedById",
                principalTable: "Users",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_ServiceRequests_Agents_AgentId",
                table: "ServiceRequests");

            migrationBuilder.DropForeignKey(
                name: "FK_ServiceRequests_Users_CitizenId",
                table: "ServiceRequests");

            migrationBuilder.DropForeignKey(
                name: "FK_ServiceRequestStatusHistories_Users_ChangedById",
                table: "ServiceRequestStatusHistories");

            migrationBuilder.DropTable(
                name: "AttendanceRecords");

            migrationBuilder.DropTable(
                name: "ISPSubscribers");

            migrationBuilder.DropTable(
                name: "WorkCenters");

            migrationBuilder.DropTable(
                name: "ZoneStatistics");

            migrationBuilder.DropIndex(
                name: "IX_ServiceRequests_AgentId",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "PaymentStatus",
                table: "SubscriptionLogs");

            migrationBuilder.DropColumn(
                name: "TechnicianName",
                table: "SubscriptionLogs");

            migrationBuilder.DropColumn(
                name: "AgentId",
                table: "ServiceRequests");

            migrationBuilder.AlterColumn<Guid>(
                name: "ChangedById",
                table: "ServiceRequestStatusHistories",
                type: "uuid",
                nullable: false,
                defaultValue: new Guid("00000000-0000-0000-0000-000000000000"),
                oldClrType: typeof(Guid),
                oldType: "uuid",
                oldNullable: true);

            migrationBuilder.AlterColumn<Guid>(
                name: "CitizenId",
                table: "ServiceRequests",
                type: "uuid",
                nullable: false,
                defaultValue: new Guid("00000000-0000-0000-0000-000000000000"),
                oldClrType: typeof(Guid),
                oldType: "uuid",
                oldNullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "CitizenId1",
                table: "ServiceRequests",
                type: "uuid",
                nullable: false,
                defaultValue: new Guid("00000000-0000-0000-0000-000000000000"));

            migrationBuilder.CreateIndex(
                name: "IX_ServiceRequests_CitizenId1",
                table: "ServiceRequests",
                column: "CitizenId1");

            migrationBuilder.AddForeignKey(
                name: "FK_ServiceRequests_Citizens_CitizenId1",
                table: "ServiceRequests",
                column: "CitizenId1",
                principalTable: "Citizens",
                principalColumn: "Id",
                onDelete: ReferentialAction.Cascade);

            migrationBuilder.AddForeignKey(
                name: "FK_ServiceRequests_Users_CitizenId",
                table: "ServiceRequests",
                column: "CitizenId",
                principalTable: "Users",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_ServiceRequestStatusHistories_Users_ChangedById",
                table: "ServiceRequestStatusHistories",
                column: "ChangedById",
                principalTable: "Users",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }
    }
}
