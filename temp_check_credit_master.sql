-- التحقق من وجود حسابات الآجل والماستر
SELECT "Code", "Name", "AccountType", "CurrentBalance", "IsActive", "IsDeleted"
FROM "Accounts"
WHERE "Code" IN ('1160', '1170')
ORDER BY "Code";

-- التحقق من آخر عمليات آجل/ماستر وهل لها قيد
SELECT sl."Id", sl."CollectionType", sl."PlanPrice", sl."CustomerName", 
       sl."JournalEntryId", sl."IsDeleted",
       CASE WHEN sl."JournalEntryId" IS NOT NULL THEN 'نعم' ELSE 'لا' END as "has_je"
FROM "SubscriptionLogs" sl
WHERE sl."CollectionType" IN ('credit', 'master')
ORDER BY sl."CreatedAt" DESC
LIMIT 10;
