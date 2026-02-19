SELECT "Id", "Type", "Amount", "ReferenceNumber", "Description", "CreatedAt" FROM "TechnicianTransactions" WHERE "IsDeleted" = false ORDER BY "CreatedAt" DESC;
