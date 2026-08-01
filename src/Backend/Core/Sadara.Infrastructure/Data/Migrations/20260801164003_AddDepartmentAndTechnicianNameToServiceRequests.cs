using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddDepartmentAndTechnicianNameToServiceRequests : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Department",
                table: "ServiceRequests",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "TechnicianName",
                table: "ServiceRequests",
                type: "character varying(150)",
                maxLength: 150,
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // الفهارس على العمودين الجديدين تُنشأ يدوياً CONCURRENTLY على الإنتاج (خارج هذا الـmigration).
            // نُسقطها هنا صراحةً قبل حذف الأعمدة لأن EF لا يعرف بوجودها (لم تُعرَّف عبر HasIndex).
            migrationBuilder.Sql("DROP INDEX IF EXISTS \"IX_ServiceRequests_Department\";");
            migrationBuilder.Sql("DROP INDEX IF EXISTS \"IX_ServiceRequests_TechnicianName\";");
            migrationBuilder.Sql("DROP INDEX IF EXISTS \"IX_ServiceRequests_Company_Dept_Tech_Status_Created\";");

            migrationBuilder.DropColumn(
                name: "Department",
                table: "ServiceRequests");

            migrationBuilder.DropColumn(
                name: "TechnicianName",
                table: "ServiceRequests");
        }
    }
}
