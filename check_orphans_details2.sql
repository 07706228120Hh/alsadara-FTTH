-- تفاصيل التحصيل بدون قيد
SELECT 'تحصيل بدون قيد' AS type, tc."Id", tc."Description", tc."Amount", tc."CollectionDate", tc."JournalEntryId", tc."IsDelivered", tc."CreatedAt"
FROM "TechnicianCollections" tc
WHERE tc."IsDeleted" = false 
  AND (tc."JournalEntryId" IS NULL OR NOT EXISTS (SELECT 1 FROM "JournalEntries" je WHERE je."Id" = tc."JournalEntryId"));

-- تفاصيل الراتب بدون قيد
SELECT 'راتب بدون قيد' AS type, es."Id", es."UserId", es."Month", es."Year", es."NetSalary", es."JournalEntryId", es."Status", es."CreatedAt"
FROM "EmployeeSalaries" es
WHERE es."IsDeleted" = false 
  AND (es."JournalEntryId" IS NULL OR NOT EXISTS (SELECT 1 FROM "JournalEntries" je WHERE je."Id" = es."JournalEntryId"));

-- تفاصيل سجلات الاشتراكات المرتبطة بقيود محذوفة
SELECT 'سجل اشتراك بقيد محذوف' AS type, sl."Id", sl."CustomerName", sl."PlanName", sl."PlanPrice", sl."OperationType", sl."PaymentMethod", sl."JournalEntryId", sl."CreatedAt",
       je."EntryNumber", je."Status" AS je_status, je."IsDeleted" AS je_deleted, je."DeletedAt" AS je_deleted_at
FROM "SubscriptionLogs" sl
INNER JOIN "JournalEntries" je ON sl."JournalEntryId" = je."Id"
WHERE sl."IsDeleted" = false AND je."IsDeleted" = true;
