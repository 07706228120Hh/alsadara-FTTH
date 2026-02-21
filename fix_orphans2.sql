-- إصلاح السجلات اليتيمة
-- ==============================

-- 1. حذف المصروف اليتيم (Id=3, "ؤىلى", 1000, بدون قيد)
UPDATE "Expenses" SET "IsDeleted" = true, "DeletedAt" = NOW() WHERE "Id" = 3 AND "IsDeleted" = false;

-- 2. حذف التحصيل اليتيم (Id=1, "نت", 40000, بدون قيد)
UPDATE "TechnicianCollections" SET "IsDeleted" = true, "DeletedAt" = NOW() WHERE "Id" = 1 AND "IsDeleted" = false;

-- 3. حذف الراتب اليتيم (Id=1, "علي علي", 10000, بدون قيد)
UPDATE "EmployeeSalaries" SET "IsDeleted" = true, "DeletedAt" = NOW() WHERE "Id" = 1 AND "IsDeleted" = false;

-- 4. حذف سجلي الاشتراكات المرتبطين بقيود محذوفة
UPDATE "SubscriptionLogs" SET "IsDeleted" = true, "DeletedAt" = NOW() WHERE "Id" IN (5, 6) AND "IsDeleted" = false;

-- ==============================
-- التحقق بعد الإصلاح
-- ==============================

SELECT 'مصروفات يتيمة' AS check_type, COUNT(*) AS remaining
FROM "Expenses" e WHERE e."IsDeleted" = false 
  AND (e."JournalEntryId" IS NULL OR NOT EXISTS (SELECT 1 FROM "JournalEntries" je WHERE je."Id" = e."JournalEntryId"));

SELECT 'تحصيلات يتيمة' AS check_type, COUNT(*) AS remaining
FROM "TechnicianCollections" tc WHERE tc."IsDeleted" = false 
  AND (tc."JournalEntryId" IS NULL OR NOT EXISTS (SELECT 1 FROM "JournalEntries" je WHERE je."Id" = tc."JournalEntryId"));

SELECT 'رواتب يتيمة' AS check_type, COUNT(*) AS remaining
FROM "EmployeeSalaries" es WHERE es."IsDeleted" = false 
  AND (es."JournalEntryId" IS NULL OR NOT EXISTS (SELECT 1 FROM "JournalEntries" je WHERE je."Id" = es."JournalEntryId"));

SELECT 'سجلات اشتراك بقيد محذوف' AS check_type, COUNT(*) AS remaining
FROM "SubscriptionLogs" sl
INNER JOIN "JournalEntries" je ON sl."JournalEntryId" = je."Id"
WHERE sl."IsDeleted" = false AND je."IsDeleted" = true;
