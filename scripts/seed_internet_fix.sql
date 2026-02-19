-- Add New Subscription operation type if not exists (correct columns)
INSERT INTO "OperationTypes" ("Id", "Name", "NameAr", "Icon", "RequiresApproval", "RequiresTechnician", "EstimatedDays", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 8, 'New Subscription', 'تفعيل اشتراك جديد', 'fiber_new', true, false, 2, 8, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "OperationTypes" WHERE "Id" = 8);

-- Add ServiceOperations for Internet FTTH (correct column: BasePrice)
INSERT INTO "ServiceOperations" ("ServiceId", "OperationTypeId", "BasePrice", "IsActive", "CreatedAt", "IsDeleted")
SELECT 9, 1, 50000, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "ServiceOperations" WHERE "ServiceId" = 9 AND "OperationTypeId" = 1);

INSERT INTO "ServiceOperations" ("ServiceId", "OperationTypeId", "BasePrice", "IsActive", "CreatedAt", "IsDeleted")
SELECT 9, 8, 0, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "ServiceOperations" WHERE "ServiceId" = 9 AND "OperationTypeId" = 8);

-- Verify all data
SELECT 'Service 9:' AS info, "Id"::text, "Name" FROM "Services" WHERE "Id" = 9;
SELECT 'OpType 8:' AS info, "Id"::text, "Name" FROM "OperationTypes" WHERE "Id" = 8;
SELECT 'ServiceOps:' AS info, "ServiceId"::text, "OperationTypeId"::text FROM "ServiceOperations" WHERE "ServiceId" = 9;
SELECT 'Plans:' AS info, "Id"::text, "Name" FROM "InternetPlans" LIMIT 5;
