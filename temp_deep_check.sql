-- Check all subscription logs with their CompanyId, UserId, and JournalEntryId
SELECT "Id", "OperationType", "PlanPrice", "CollectionType", "CompanyId", "UserId", "JournalEntryId", "LinkedAgentId", "LinkedTechnicianId"
FROM "SubscriptionLogs"
WHERE "IsDeleted" = false
ORDER BY "Id";

-- Check the actual JournalEntryLines amounts vs Account CurrentBalance
SELECT a."Code", a."Name", a."CurrentBalance",
    COALESCE(SUM(jel."DebitAmount"), 0) as total_debits,
    COALESCE(SUM(jel."CreditAmount"), 0) as total_credits,
    COALESCE(SUM(jel."DebitAmount"), 0) - COALESCE(SUM(jel."CreditAmount"), 0) as net_from_je
FROM "Accounts" a
LEFT JOIN "JournalEntryLines" jel ON jel."AccountId" = a."Id" AND jel."IsDeleted" = false
LEFT JOIN "JournalEntries" je ON jel."JournalEntryId" = je."Id" AND je."IsDeleted" = false
WHERE a."IsActive" = true AND a."IsDeleted" = false
GROUP BY a."Code", a."Name", a."CurrentBalance"
HAVING a."CurrentBalance" != 0 OR COALESCE(SUM(jel."DebitAmount"), 0) != 0 OR COALESCE(SUM(jel."CreditAmount"), 0) != 0
ORDER BY a."Code";

-- Check denormalized columns on agents
SELECT "Id", "Name", "TotalCharges", "TotalPayments", "NetBalance"
FROM "Agents"
WHERE "IsDeleted" = false;

-- Check denormalized columns on users (technicians)
SELECT "Id", "FullName", "TechTotalCharges", "TechTotalPayments", "TechNetBalance", "IsTechnician"
FROM "Users"
WHERE "IsDeleted" = false AND "IsTechnician" = true;
