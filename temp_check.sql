SELECT "FullName", "TechTotalCharges", "TechTotalPayments", "TechNetBalance" FROM "Users" WHERE "Id" = 'b1e3a4f3-b808-44dc-8feb-c41e34beca66';
SELECT count(*) as tx_count FROM "TechnicianTransactions" WHERE "TechnicianId" = 'b1e3a4f3-b808-44dc-8feb-c41e34beca66' AND "IsDeleted" = false;
