-- تنظيف سجلات الدفع اليتيمة (مرتبطة بمصاريف ثابتة محذوفة)
UPDATE "FixedExpensePayments" 
SET "IsDeleted" = true, "DeletedAt" = NOW()
WHERE "IsDeleted" = false 
AND "FixedExpenseId" IN (
    SELECT "Id" FROM "FixedExpenses" WHERE "IsDeleted" = true
);
