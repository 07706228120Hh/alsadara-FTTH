-- 1. مصروفات تظهر لكن قيدها محذوف
SELECT 'Expenses_with_deleted_JE' AS check_type, COUNT(*) AS cnt
FROM "Expenses" e
INNER JOIN "JournalEntries" je ON e."JournalEntryId" = je."Id"
WHERE e."IsDeleted" = false AND je."IsDeleted" = true;

-- 2. تحصيلات فنيين تظهر لكن قيدها محذوف
SELECT 'Collections_with_deleted_JE' AS check_type, COUNT(*) AS cnt
FROM "TechnicianCollections" tc
INNER JOIN "JournalEntries" je ON tc."JournalEntryId" = je."Id"
WHERE tc."IsDeleted" = false AND je."IsDeleted" = true;

-- 3. حركات صندوق تظهر لكن قيدها محذوف
SELECT 'CashTx_with_deleted_JE' AS check_type, COUNT(*) AS cnt
FROM "CashTransactions" ct
INNER JOIN "JournalEntries" je ON ct."JournalEntryId" = je."Id"
WHERE ct."IsDeleted" = false AND je."IsDeleted" = true;

-- 4. رواتب تظهر لكن قيدها محذوف
SELECT 'Salaries_with_deleted_JE' AS check_type, COUNT(*) AS cnt
FROM "EmployeeSalaries" es
INNER JOIN "JournalEntries" je ON es."JournalEntryId" = je."Id"
WHERE es."IsDeleted" = false AND je."IsDeleted" = true;

-- 5. مصروفات بدون قيد أصلاً (JournalEntryId = NULL أو غير موجود)
SELECT 'Expenses_no_JE' AS check_type, COUNT(*) AS cnt
FROM "Expenses" e
WHERE e."IsDeleted" = false 
  AND (e."JournalEntryId" IS NULL OR NOT EXISTS (SELECT 1 FROM "JournalEntries" je WHERE je."Id" = e."JournalEntryId"));

-- 6. تحصيلات بدون قيد
SELECT 'Collections_no_JE' AS check_type, COUNT(*) AS cnt
FROM "TechnicianCollections" tc
WHERE tc."IsDeleted" = false 
  AND (tc."JournalEntryId" IS NULL OR NOT EXISTS (SELECT 1 FROM "JournalEntries" je WHERE je."Id" = tc."JournalEntryId"));

-- 7. حركات صندوق بدون قيد
SELECT 'CashTx_no_JE' AS check_type, COUNT(*) AS cnt
FROM "CashTransactions" ct
WHERE ct."IsDeleted" = false 
  AND (ct."JournalEntryId" IS NULL OR NOT EXISTS (SELECT 1 FROM "JournalEntries" je WHERE je."Id" = ct."JournalEntryId"));

-- 8. رواتب بدون قيد
SELECT 'Salaries_no_JE' AS check_type, COUNT(*) AS cnt
FROM "EmployeeSalaries" es
WHERE es."IsDeleted" = false 
  AND (es."JournalEntryId" IS NULL OR NOT EXISTS (SELECT 1 FROM "JournalEntries" je WHERE je."Id" = es."JournalEntryId"));

-- 9. سجلات اشتراكات FTTH تظهر لكن قيدها محذوف
SELECT 'SubLogs_with_deleted_JE' AS check_type, COUNT(*) AS cnt
FROM "SubscriptionLogs" sl
INNER JOIN "JournalEntries" je ON sl."JournalEntryId" = je."Id"
WHERE sl."IsDeleted" = false AND je."IsDeleted" = true;
