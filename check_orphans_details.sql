-- تفاصيل المصروف بدون قيد
SELECT '=== مصروف بدون قيد ===' AS section;
SELECT e."Id", e."Description", e."Amount", e."ExpenseDate", e."JournalEntryId", e."CreatedAt"
FROM "Expenses" e
WHERE e."IsDeleted" = false 
  AND (e."JournalEntryId" IS NULL OR NOT EXISTS (SELECT 1 FROM "JournalEntries" je WHERE je."Id" = e."JournalEntryId"));

-- تفاصيل التحصيل بدون قيد
SELECT '=== تحصيل بدون قيد ===' AS section;
SELECT tc."Id", tc."TechnicianName", tc."Amount", tc."CollectionDate", tc."JournalEntryId", tc."IsDelivered", tc."CreatedAt"
FROM "TechnicianCollections" tc
WHERE tc."IsDeleted" = false 
  AND (tc."JournalEntryId" IS NULL OR NOT EXISTS (SELECT 1 FROM "JournalEntries" je WHERE je."Id" = tc."JournalEntryId"));

-- تفاصيل الراتب بدون قيد
SELECT '=== راتب بدون قيد ===' AS section;
SELECT es."Id", es."EmployeeName", es."Amount", es."SalaryMonth", es."JournalEntryId", es."CreatedAt"
FROM "EmployeeSalaries" es
WHERE es."IsDeleted" = false 
  AND (es."JournalEntryId" IS NULL OR NOT EXISTS (SELECT 1 FROM "JournalEntries" je WHERE je."Id" = es."JournalEntryId"));

-- تفاصيل سجلات الاشتراكات المرتبطة بقيود محذوفة
SELECT '=== سجل اشتراك مرتبط بقيد محذوف ===' AS section;
SELECT sl."Id", sl."SubscriberName", sl."Amount", sl."OperationType", sl."PaymentMethod", sl."JournalEntryId", sl."CreatedAt",
       je."EntryNumber", je."Status", je."IsDeleted" AS je_deleted, je."DeletedAt" AS je_deleted_at
FROM "SubscriptionLogs" sl
INNER JOIN "JournalEntries" je ON sl."JournalEntryId" = je."Id"
WHERE sl."IsDeleted" = false AND je."IsDeleted" = true;
