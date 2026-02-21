-- حذف سجلات العمليات + البيانات المحاسبية
DELETE FROM "SubscriptionLogs";

-- 2. حذف جداول المعاملات
DELETE FROM "CashTransactions";
DELETE FROM "TechnicianCollections";
DELETE FROM "TechnicianTransactions";
DELETE FROM "AgentTransactions";
DELETE FROM "Expenses";
DELETE FROM "EmployeeSalaries";

-- 3. حذف القيود المحاسبية
DELETE FROM "JournalEntries";

-- 4. تصفير أرصدة الصناديق
UPDATE "CashBoxes" SET "CurrentBalance" = 0;

-- 5. تصفير أرصدة شجرة الحسابات
UPDATE "Accounts" SET "CurrentBalance" = 0;

-- 6. تصفير أرصدة الفنيين
UPDATE "Users" SET "TechTotalCharges" = 0, "TechTotalPayments" = 0, "TechNetBalance" = 0;

-- 7. تصفير أرصدة الوكلاء
UPDATE "Agents" SET "TotalCharges" = 0, "TotalPayments" = 0, "NetBalance" = 0;
