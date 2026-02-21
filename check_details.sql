-- تفاصيل الأرصدة الحالية للحسابات المتأثرة
SELECT a."Code", a."Name", a."CurrentBalance", a."AccountType"
FROM "Accounts" a
WHERE a."Code" IN ('11502', '11501', '4100')
ORDER BY a."Code";

-- هل تم عكس الأرصدة أصلاً؟ نتحقق من حالة القيود المحذوفة
SELECT je."EntryNumber", je."Status", je."IsDeleted", je."DeletedAt",
       je."TotalDebit", je."TotalCredit"
FROM "JournalEntries" je
WHERE je."EntryNumber" IN ('JE-2026-0010', 'JE-2026-0011');

-- عدد كل القيود المحذوفة
SELECT COUNT(*) AS deleted_journals FROM "JournalEntries" WHERE "IsDeleted" = true;

-- هل يوجد أسطر قيود أخرى تؤثر على هذه الحسابات؟
SELECT jl."JournalEntryId", je."EntryNumber", je."IsDeleted" AS je_deleted,
       jl."IsDeleted" AS line_deleted,
       jl."DebitAmount", jl."CreditAmount",
       a."Code", a."Name"
FROM "JournalEntryLines" jl
JOIN "JournalEntries" je ON jl."JournalEntryId" = je."Id"
JOIN "Accounts" a ON jl."AccountId" = a."Id"
WHERE a."Code" IN ('11502', '11501')
ORDER BY je."EntryNumber";
