-- ═══ التحقق النهائي من تطابق جميع الطبقات ═══

-- 1. أرصدة الحسابات (يجب أن تتطابق مع القيود)
SELECT 'Account Balances' as layer, a."Code", a."Name", a."CurrentBalance"
FROM "Accounts" a
WHERE a."CurrentBalance" != 0 AND a."IsActive" AND NOT a."IsDeleted"
ORDER BY a."Code";

-- 2. مجاميع القيود المحاسبية
SELECT 'JE Totals' as layer, COUNT(*) as count, SUM("TotalDebit") as total_debit
FROM "JournalEntries" WHERE NOT "IsDeleted";

-- 3. الوكلاء (denormalized)
SELECT 'Agents' as layer, "Name", "TotalCharges", "TotalPayments", "NetBalance"
FROM "Agents" WHERE NOT "IsDeleted";

-- 4. الفنيون (denormalized)
SELECT 'Technicians' as layer, "FullName", "TechTotalCharges", "TechTotalPayments", "TechNetBalance"
FROM "Users" WHERE NOT "IsDeleted" AND ("TechTotalCharges" > 0 OR "TechTotalPayments" > 0);

-- 5. سجلات بدون قيد (يحتاج retry)
SELECT 'Orphan Logs' as layer, "Id", "CollectionType", "PlanPrice"
FROM "SubscriptionLogs"
WHERE NOT "IsDeleted" AND "JournalEntryId" IS NULL AND "CollectionType" IS NOT NULL;

-- 6. الحسابات الجديدة
SELECT 'New Accounts' as layer, "Code", "Name"
FROM "Accounts"
WHERE "Code" IN ('1160', '1170', '4110', '4120') AND NOT "IsDeleted";
