-- Query accounts under 1110
SELECT "Code", "Name" FROM "Accounts" WHERE "Code" LIKE '1110%' AND "IsDeleted" = false ORDER BY "Code";

-- Rename the account "الصندوق" to "رصيد الصفحة" 
UPDATE "Accounts" SET "Name" = 'رصيد الصفحة', "UpdatedAt" = NOW() WHERE "Code" LIKE '1110%' AND "Name" = 'الصندوق' AND "IsDeleted" = false;

-- Also check for "صندوق الشركة الرئيسي"
UPDATE "Accounts" SET "Name" = 'رصيد الصفحة', "UpdatedAt" = NOW() WHERE "Code" LIKE '1110%' AND "Name" = 'صندوق الشركة الرئيسي' AND "IsDeleted" = false;

-- Verify result
SELECT "Code", "Name" FROM "Accounts" WHERE "Code" LIKE '1110%' AND "IsDeleted" = false ORDER BY "Code";
