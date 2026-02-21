-- هل المصروف الوحيد بدون قيد هو الوحيد أم توجد مصروفات أخرى بقيود؟
SELECT 'إجمالي المصروفات النشطة' AS info, COUNT(*) AS cnt FROM "Expenses" WHERE "IsDeleted" = false;
SELECT 'إجمالي المصروفات بقيود' AS info, COUNT(*) AS cnt FROM "Expenses" WHERE "IsDeleted" = false AND "JournalEntryId" IS NOT NULL;

-- هل التحصيل بدون قيد وحيد؟
SELECT 'إجمالي التحصيلات النشطة' AS info, COUNT(*) AS cnt FROM "TechnicianCollections" WHERE "IsDeleted" = false;
SELECT 'إجمالي التحصيلات بقيود' AS info, COUNT(*) AS cnt FROM "TechnicianCollections" WHERE "IsDeleted" = false AND "JournalEntryId" IS NOT NULL;

-- هل الراتب بدون قيد وحيد؟
SELECT 'إجمالي الرواتب النشطة' AS info, COUNT(*) AS cnt FROM "EmployeeSalaries" WHERE "IsDeleted" = false;
SELECT 'إجمالي الرواتب بقيود' AS info, COUNT(*) AS cnt FROM "EmployeeSalaries" WHERE "IsDeleted" = false AND "JournalEntryId" IS NOT NULL;

-- اسم الموظف صاحب الراتب اليتيم
SELECT 'اسم الموظف' AS info, u."Name", u."PhoneNumber", es."NetSalary", es."Month", es."Year"
FROM "EmployeeSalaries" es
JOIN "Users" u ON es."UserId" = u."Id"
WHERE es."Id" = 1 AND es."IsDeleted" = false;

-- تفاصيل سجلي الاشتراكات اليتيمين - هل لهما أثر مالي؟
SELECT sl."Id", sl."CustomerName", sl."PlanPrice", sl."LinkedAgentId",
  CASE WHEN sl."LinkedAgentId" IS NOT NULL THEN (SELECT u."Name" FROM "Users" u WHERE u."Id" = sl."LinkedAgentId") END AS agent_name
FROM "SubscriptionLogs" sl
WHERE sl."Id" IN (5, 6) AND sl."IsDeleted" = false;
