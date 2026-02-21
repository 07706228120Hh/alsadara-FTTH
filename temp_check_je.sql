-- Reset ALL denormalized columns

-- Reset technician cached balances on Users table
UPDATE "Users" SET "TechTotalCharges" = 0, "TechTotalPayments" = 0, "TechNetBalance" = 0;

-- Reset agent cached balances on Agents table (ALL columns)
UPDATE "Agents" SET "TotalCharges" = 0, "TotalPayments" = 0, "NetBalance" = 0;

-- Verify
SELECT 'Users (tech)' as tbl, "FullName", "TechTotalCharges", "TechTotalPayments", "TechNetBalance" 
FROM "Users" WHERE "IsDeleted" = false;

SELECT 'Agents' as tbl, "Name", "TotalCharges", "TotalPayments", "NetBalance" 
FROM "Agents" WHERE "IsDeleted" = false;
