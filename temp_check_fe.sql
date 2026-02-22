SELECT p."Id", p."FixedExpenseId", fe."Name", fe."Category", p."Month", p."Year", p."Amount", p."IsPaid", p."PaidAt"
FROM "FixedExpensePayments" p
JOIN "FixedExpenses" fe ON fe."Id" = p."FixedExpenseId"
WHERE p."IsDeleted" = false
ORDER BY p."Year" DESC, p."Month" DESC
LIMIT 20;
