-- 1. أسطر قيود لقيود محذوفة
SELECT 'JournalEntryLines_orphaned' AS issue, COUNT(*) AS cnt
FROM "JournalEntryLines" jl
JOIN "JournalEntries" je ON jl."JournalEntryId" = je."Id"
WHERE je."IsDeleted" = true AND jl."IsDeleted" = false;

-- 2. مصروفات مرتبطة بقيود محذوفة
SELECT 'Expenses_orphaned' AS issue, COUNT(*) AS cnt
FROM "Expenses" e
JOIN "JournalEntries" je ON e."JournalEntryId" = je."Id"
WHERE je."IsDeleted" = true AND e."IsDeleted" = false;

-- 3. تحصيلات مرتبطة بقيود محذوفة
SELECT 'Collections_orphaned' AS issue, COUNT(*) AS cnt
FROM "TechnicianCollections" tc
JOIN "JournalEntries" je ON tc."JournalEntryId" = je."Id"
WHERE je."IsDeleted" = true AND tc."IsDeleted" = false;

-- 4. حركات صندوق مرتبطة بقيود محذوفة
SELECT 'CashTx_orphaned' AS issue, COUNT(*) AS cnt
FROM "CashTransactions" ct
JOIN "JournalEntries" je ON ct."JournalEntryId" = je."Id"
WHERE je."IsDeleted" = true AND ct."IsDeleted" = false;

-- 5. رواتب مرتبطة بقيود محذوفة
SELECT 'Salaries_orphaned' AS issue, COUNT(*) AS cnt
FROM "EmployeeSalaries" es
JOIN "JournalEntries" je ON es."JournalEntryId" = je."Id"
WHERE je."IsDeleted" = true AND es."IsDeleted" = false;

-- 6. قيود Voided لكن غير محذوفة
SELECT 'Voided_not_deleted' AS issue, COUNT(*) AS cnt
FROM "JournalEntries"
WHERE "Status" = 2 AND "IsDeleted" = false;

-- 7. تفاصيل أسطر القيود اليتيمة
SELECT je."EntryNumber", je."Description" AS journal_desc, je."DeletedAt",
       jl."Id" AS line_id, jl."DebitAmount", jl."CreditAmount",
       a."Name" AS account_name, a."Code" AS account_code
FROM "JournalEntryLines" jl
JOIN "JournalEntries" je ON jl."JournalEntryId" = je."Id"
LEFT JOIN "Accounts" a ON jl."AccountId" = a."Id"
WHERE je."IsDeleted" = true AND jl."IsDeleted" = false
ORDER BY je."DeletedAt" DESC
LIMIT 50;
