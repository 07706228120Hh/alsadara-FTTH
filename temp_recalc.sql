-- Check all user columns related to technician
SELECT column_name FROM information_schema.columns 
WHERE table_name = 'Users' AND column_name LIKE '%Tech%' OR column_name LIKE '%tech%';

-- Check technician users
SELECT "Id", "FullName", "TechTotalCharges", "TechTotalPayments", "TechNetBalance"
FROM "Users"
WHERE "IsDeleted" = false AND "TechTotalCharges" > 0;

-- Check accounting dashboard endpoint data source
-- What does /api/accounting/dashboard read?

-- Recalculate what account balances SHOULD be based on JE lines
SELECT a."Code", a."Name", a."CurrentBalance" as actual_balance,
    CASE 
        WHEN a."AccountType" IN (1, 5) THEN COALESCE(SUM(jel."DebitAmount" - jel."CreditAmount"), 0)
        ELSE COALESCE(SUM(jel."CreditAmount" - jel."DebitAmount"), 0)
    END as expected_balance,
    a."CurrentBalance" - CASE 
        WHEN a."AccountType" IN (1, 5) THEN COALESCE(SUM(jel."DebitAmount" - jel."CreditAmount"), 0)
        ELSE COALESCE(SUM(jel."CreditAmount" - jel."DebitAmount"), 0)
    END as difference
FROM "Accounts" a
LEFT JOIN "JournalEntryLines" jel ON jel."AccountId" = a."Id" AND jel."IsDeleted" = false
LEFT JOIN "JournalEntries" je ON jel."JournalEntryId" = je."Id" AND je."IsDeleted" = false
WHERE a."IsActive" = true AND a."IsDeleted" = false
GROUP BY a."Id", a."Code", a."Name", a."CurrentBalance", a."AccountType"
HAVING a."CurrentBalance" != 0
ORDER BY a."Code";
