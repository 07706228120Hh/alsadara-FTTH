-- إضافة الخدمة والعمليات الجديدة للوكلاء
-- Service Id=10: عمليات الوكلاء
-- OperationType Id=9: شحن ماستر
-- OperationType Id=10: طلب رصيد
-- OperationType Id=11: دفع مديونية

-- الخدمة الجديدة: عمليات الوكلاء
INSERT INTO "Services" ("Id", "Name", "NameAr", "Description", "Icon", "Color", "IsActive", "DisplayOrder", "CreatedAt", "IsDeleted")
SELECT 10, 'Agent Operations', 'عمليات الوكلاء', 'طلبات الوكلاء المالية (رصيد، مديونية، ماستر)', 'storefront', '#E91E63', true, 10, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "Services" WHERE "Id" = 10);

-- شحن ماستر
INSERT INTO "OperationTypes" ("Id", "Name", "NameAr", "Icon", "IsActive", "RequiresApproval", "RequiresTechnician", "EstimatedDays", "DisplayOrder", "CreatedAt", "IsDeleted")
SELECT 9, 'Master Recharge', 'شحن ماستر', 'credit-card', true, true, false, 0, 9, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "OperationTypes" WHERE "Id" = 9);

-- طلب رصيد
INSERT INTO "OperationTypes" ("Id", "Name", "NameAr", "Icon", "IsActive", "RequiresApproval", "RequiresTechnician", "EstimatedDays", "DisplayOrder", "CreatedAt", "IsDeleted")
SELECT 10, 'Balance Request', 'طلب رصيد', 'account-balance-wallet', true, true, false, 0, 10, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "OperationTypes" WHERE "Id" = 10);

-- دفع مديونية
INSERT INTO "OperationTypes" ("Id", "Name", "NameAr", "Icon", "IsActive", "RequiresApproval", "RequiresTechnician", "EstimatedDays", "DisplayOrder", "CreatedAt", "IsDeleted")
SELECT 11, 'Debt Payment', 'دفع مديونية', 'payments', true, false, false, 0, 11, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "OperationTypes" WHERE "Id" = 11);

-- ربط عمليات الوكلاء بالخدمة
INSERT INTO "ServiceOperations" ("ServiceId", "OperationTypeId", "IsActive", "CreatedAt", "IsDeleted")
SELECT 10, 9, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "ServiceOperations" WHERE "ServiceId" = 10 AND "OperationTypeId" = 9);

INSERT INTO "ServiceOperations" ("ServiceId", "OperationTypeId", "IsActive", "CreatedAt", "IsDeleted")
SELECT 10, 10, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "ServiceOperations" WHERE "ServiceId" = 10 AND "OperationTypeId" = 10);

INSERT INTO "ServiceOperations" ("ServiceId", "OperationTypeId", "IsActive", "CreatedAt", "IsDeleted")
SELECT 10, 11, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "ServiceOperations" WHERE "ServiceId" = 10 AND "OperationTypeId" = 11);
