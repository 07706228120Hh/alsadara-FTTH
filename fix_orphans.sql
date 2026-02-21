-- تنظيف أسطر القيود اليتيمة (حذف ناعم)
BEGIN;

-- حذف ناعم للأسطر المرتبطة بقيود محذوفة
UPDATE "JournalEntryLines" jl
SET "IsDeleted" = true, "DeletedAt" = NOW()
FROM "JournalEntries" je
WHERE jl."JournalEntryId" = je."Id"
  AND je."IsDeleted" = true
  AND jl."IsDeleted" = false;

-- تحديث اسم حساب الوكيل (إزالة بادئة "ذمة وكيل")
UPDATE "Accounts"
SET "Name" = REPLACE("Name", 'ذمة وكيل ', '')
WHERE "Name" LIKE 'ذمة وكيل %'
  AND "Code" LIKE '1150%'
  AND "Code" != '1150';

COMMIT;

-- التحقق
SELECT 'Remaining orphaned lines' AS check_type, COUNT(*) AS cnt
FROM "JournalEntryLines" jl
JOIN "JournalEntries" je ON jl."JournalEntryId" = je."Id"
WHERE je."IsDeleted" = true AND jl."IsDeleted" = false;

SELECT "Code", "Name", "CurrentBalance"
FROM "Accounts"
WHERE "Code" LIKE '1150%'
ORDER BY "Code";
