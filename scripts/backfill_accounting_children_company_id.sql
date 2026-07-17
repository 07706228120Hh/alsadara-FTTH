-- ═══════════════════════════════════════════════════════════════════════════
-- Backfill: تعبئة CompanyId لأبناء المحاسبة من آبائهم (الطبقة ٢ — تحصين العزل).
-- آمن وقابل لإعادة التشغيل (idempotent): يعبّئ الفارغ فقط.
-- يُشغَّل بعد هجرة إضافة عمود CompanyId (القابل لـ null) لهذين الجدولين.
-- الآباء (JournalEntries / CashBoxes) عُبّئت CompanyId فيهم مسبقاً في نشر الطبقة ١،
-- فكل الأبناء ذوي الأب الصحيح سيأخذون شركة أبيهم.
-- ═══════════════════════════════════════════════════════════════════════════
BEGIN;

-- سطور القيود ← من القيد الأب
UPDATE "JournalEntryLines" c
SET    "CompanyId" = p."CompanyId"
FROM   "JournalEntries" p
WHERE  c."JournalEntryId" = p."Id"
  AND  c."CompanyId" IS NULL;

-- حركات الصندوق ← من الصندوق الأب
UPDATE "CashTransactions" c
SET    "CompanyId" = p."CompanyId"
FROM   "CashBoxes" p
WHERE  c."CashBoxId" = p."Id"
  AND  c."CompanyId" IS NULL;

COMMIT;

-- ═══ التحقّق: يجب أن يكون العمودان صفراً (لا ابن بلا شركة) ═══
SELECT 'JournalEntryLines' AS table_name, count(*) AS null_company_rows
FROM   "JournalEntryLines" WHERE "CompanyId" IS NULL
UNION ALL
SELECT 'CashTransactions', count(*)
FROM   "CashTransactions" WHERE "CompanyId" IS NULL;

-- ملاحظة: إن ظهر أي صفّ فارغ (ابن بأب مفقود/محذوف)، عالِجه يدوياً — أو فعّل
-- الختم بالشركة الافتراضية (استبدل <DEFAULT_COMPANY_ID> بمعرّف رمز الصدارة):
-- UPDATE "JournalEntryLines" SET "CompanyId" = '<DEFAULT_COMPANY_ID>' WHERE "CompanyId" IS NULL;
-- UPDATE "CashTransactions"  SET "CompanyId" = '<DEFAULT_COMPANY_ID>' WHERE "CompanyId" IS NULL;
