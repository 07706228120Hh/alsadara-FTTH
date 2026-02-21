-- حذف السجلات اليتيمة (credit و master) التي فشل إنشاء قيدها
-- وإعادة حساب أرصدة الحسابات

-- 1. عرض السجلات اليتيمة أولاً
SELECT "Id", "CollectionType", "PlanPrice", "CustomerName", "JournalEntryId"
FROM "SubscriptionLogs"
WHERE "IsDeleted" = false AND "JournalEntryId" IS NULL;

-- 2. حذف ناعم للسجلات اليتيمة
UPDATE "SubscriptionLogs"
SET "IsDeleted" = true, "DeletedAt" = NOW()
WHERE "IsDeleted" = false AND "JournalEntryId" IS NULL;

-- 3. التحقق
SELECT COUNT(*) as "remaining_orphans"
FROM "SubscriptionLogs"
WHERE "IsDeleted" = false AND "JournalEntryId" IS NULL;
