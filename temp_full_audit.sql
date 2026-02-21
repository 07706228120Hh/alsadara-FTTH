-- Check agent transactions
SELECT "Id", "AgentId", "Type", "Amount", "BalanceAfter", "Description", "CreatedAt"
FROM "AgentTransactions"
WHERE "IsDeleted" = false
ORDER BY "CreatedAt";

-- Check technician transactions
SELECT "Id", "TechnicianId", "Type", "Amount", "BalanceAfter", "Description", "CreatedAt"
FROM "TechnicianTransactions"
WHERE "IsDeleted" = false
ORDER BY "CreatedAt";

-- Check if there are ALL journal entries including soft-deleted
SELECT je."Id", je."EntryNumber", je."Description", je."TotalDebit", je."IsDeleted", je."CreatedAt"
FROM "JournalEntries" je
ORDER BY je."CreatedAt";

-- Check ALL journal entry lines including soft-deleted
SELECT je."EntryNumber", jel."Description", jel."DebitAmount", jel."CreditAmount", a."Code", jel."IsDeleted"
FROM "JournalEntryLines" jel
JOIN "JournalEntries" je ON jel."JournalEntryId" = je."Id"
JOIN "Accounts" a ON jel."AccountId" = a."Id"
ORDER BY je."CreatedAt", jel."DebitAmount" DESC;

-- Check service requests
SELECT "Id", "Status", "Amount", "CollectionType", "AgentId", "AssignedTechnicianId", "CreatedAt"
FROM "ServiceRequests"
WHERE "IsDeleted" = false
ORDER BY "CreatedAt";

-- Look at cash transactions
SELECT * FROM "CashTransactions" WHERE "IsDeleted" = false LIMIT 5;
