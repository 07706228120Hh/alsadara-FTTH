UPDATE "OperationTypes" SET "NameAr" = 'تسديد حساب' WHERE "Id" = 11;
SELECT "Id", "NameAr" FROM "OperationTypes" WHERE "Id" IN (10, 11, 12);
