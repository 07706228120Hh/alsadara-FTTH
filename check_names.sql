-- اسم الموظف صاحب الراتب اليتيم
SELECT es."Id", u."FullName", u."PhoneNumber", es."NetSalary", es."Month", es."Year", es."Status"
FROM "EmployeeSalaries" es
JOIN "Users" u ON es."UserId" = u."Id"
WHERE es."Id" = 1 AND es."IsDeleted" = false;

-- تفاصيل سجلي الاشتراكات اليتيمين
SELECT sl."Id", sl."CustomerName", sl."PlanPrice", sl."LinkedAgentId",
  (SELECT u."FullName" FROM "Users" u WHERE u."Id" = sl."LinkedAgentId") AS agent_name
FROM "SubscriptionLogs" sl
WHERE sl."Id" IN (5, 6) AND sl."IsDeleted" = false;
