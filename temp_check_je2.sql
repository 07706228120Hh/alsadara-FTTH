-- Check all journal entries
SELECT je."Id", je."EntryNumber", je."Description", je."TotalDebit", je."TotalCredit", je."Status", je."CreatedAt"
FROM "JournalEntries" je
WHERE je."IsDeleted" = false
ORDER BY je."CreatedAt";

-- Check all journal entry lines
SELECT je."EntryNumber", jel."Description", jel."DebitAmount", jel."CreditAmount", a."Code", a."Name"
FROM "JournalEntryLines" jel
JOIN "JournalEntries" je ON jel."JournalEntryId" = je."Id"
JOIN "Accounts" a ON jel."AccountId" = a."Id"
WHERE je."IsDeleted" = false AND jel."IsDeleted" = false
ORDER BY je."CreatedAt", jel."DebitAmount" DESC;

-- Check subscription logs
SELECT "Id", "OperationType", "PlanName", "PlanPrice", "CollectionType", "LinkedAgentId", "LinkedTechnicianId", "ActivationDate"
FROM "SubscriptionLogs"
WHERE "IsDeleted" = false
ORDER BY "ActivationDate";
