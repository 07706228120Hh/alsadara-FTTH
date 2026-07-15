-- ═══════════════════════════════════════════════════════════════════════════
-- apply_tenant_columns.sql
-- تطبيق أعمدة عزل الشركة (migration 20260715020420_AddTenantCompanyIdToStragglers)
-- بطريقة idempotent آمنة — مستقلة عن حالة سلسلة EF.
--
-- لماذا SQL خام بدل `dotnet ef database update`؟
--   سلسلة migrations في EF بها عدم اتساق معروف: الملف
--   20260528120000_AddSlaHoursToDepartmentTasks.cs موجود لكن بلا .Designer.cs،
--   فلا يعترف به EF (كُتب يدوياً لتوثيق ALTER TABLE يدوي). لذا الاعتماد على
--   `database update` غير موثوق هنا. هذا السكربت يضيف الأعمدة الأربعة الجديدة فقط.
--
-- آمن للتشغيل على: (1) قاعدة scratch مستعادة من dump (اختبار)، (2) الإنتاج لاحقاً.
--   • ADD COLUMN IF NOT EXISTS: لا يفشل لو العمود موجود، ولا يلمس أي بيانات.
--   • nullable: إضافة عمود قابل للـ null لا تحتاج default ولا تقفل الجدول طويلاً.
--   • يسجّل الـ migration في __EFMigrationsHistory حتى لا يحاول EF إعادته.
--
-- التشغيل:  sudo -u postgres psql -d <DB> -f apply_tenant_columns.sql
-- ⚠️ على الإنتاج (sadara_db) فقط بعد: نسخة احتياطية pg_dump + اختبار على scratch + موافقة صريحة.
-- ═══════════════════════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE "WhatsAppBatchReports"  ADD COLUMN IF NOT EXISTS "CompanyId" uuid NULL;
ALTER TABLE "ReminderSettings"      ADD COLUMN IF NOT EXISTS "CompanyId" uuid NULL;
ALTER TABLE "ReminderExecutionLogs" ADD COLUMN IF NOT EXISTS "CompanyId" uuid NULL;
ALTER TABLE "EmployeeLocationLogs"  ADD COLUMN IF NOT EXISTS "CompanyId" uuid NULL;

-- تسجيل الـ migration (يمنع EF من محاولة إعادة تطبيقه لاحقاً)
INSERT INTO "__EFMigrationsHistory" ("MigrationId", "ProductVersion")
VALUES ('20260715020420_AddTenantCompanyIdToStragglers', '9.0.2')
ON CONFLICT ("MigrationId") DO NOTHING;

COMMIT;

\echo 'تم تطبيق أعمدة CompanyId الأربعة (idempotent). الخطوة التالية: backfill_company_id.sql'
