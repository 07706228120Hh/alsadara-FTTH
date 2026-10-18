using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <inheritdoc />
    public partial class NormalizeIptvSubscriberCompanyIdToGuid : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // تطبيع CompanyId من text (NOT NULL) إلى uuid (nullable).
            // تحويل آمن: القيم المطابقة لصيغة UUID تُحوَّل، وأي قيمة أخرى (فارغة/تالفة/غير UUID)
            // تُحوَّل إلى NULL بدل إسقاط الصف أو فشل الأمر بأكمله — لا يُحذف أي صف.
            // ملاحظة أمنية: الصفوف التي تصبح NULL تخرج من نطاق أي شركة حتى يُعاد ملؤها (backfill).
            migrationBuilder.Sql(@"
ALTER TABLE ""IptvSubscribers""
    ALTER COLUMN ""CompanyId"" DROP NOT NULL;

ALTER TABLE ""IptvSubscribers""
    ALTER COLUMN ""CompanyId"" TYPE uuid
    USING CASE
        WHEN ""CompanyId"" ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        THEN ""CompanyId""::uuid
        ELSE NULL
    END;
");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // إرجاع آمن إلى text NOT NULL (الوضع الأصلي). القيم NULL تُحوَّل إلى '' لتلبية NOT NULL.
            migrationBuilder.Sql(@"
ALTER TABLE ""IptvSubscribers""
    ALTER COLUMN ""CompanyId"" TYPE text
    USING COALESCE(""CompanyId""::text, '');

ALTER TABLE ""IptvSubscribers""
    ALTER COLUMN ""CompanyId"" SET DEFAULT '';

ALTER TABLE ""IptvSubscribers""
    ALTER COLUMN ""CompanyId"" SET NOT NULL;
");
        }
    }
}
