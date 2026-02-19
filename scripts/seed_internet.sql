-- Check if Internet FTTH service exists
SELECT "Id", "Name" FROM "Services" ORDER BY "Id";

-- Add Internet FTTH service if not exists
INSERT INTO "Services" ("Id", "Name", "NameAr", "Description", "Icon", "Color", "IsActive", "DisplayOrder", "CreatedAt", "IsDeleted")
SELECT 9, 'Internet FTTH', 'إنترنت FTTH', 'خدمات الإنترنت عبر الألياف الضوئية FTTH', 'wifi', '#0EA5E9', true, 0, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "Services" WHERE "Id" = 9);

-- Add New Subscription operation type if not exists
INSERT INTO "OperationTypes" ("Id", "Name", "NameAr", "Description", "Icon", "RequiresApproval", "EstimatedDays", "BasePrice", "IsActive", "CreatedAt", "IsDeleted")
SELECT 8, 'New Subscription', 'تفعيل اشتراك جديد', 'تفعيل اشتراك إنترنت جديد للعميل', 'fiber_new', true, 2, 0, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "OperationTypes" WHERE "Id" = 8);

-- Add ServiceOperations for Internet FTTH  
INSERT INTO "ServiceOperations" ("ServiceId", "OperationTypeId", "Price", "IsActive", "CreatedAt", "IsDeleted")
SELECT 9, 1, 50000, true, NOW(), false  -- Installation
WHERE NOT EXISTS (SELECT 1 FROM "ServiceOperations" WHERE "ServiceId" = 9 AND "OperationTypeId" = 1);

INSERT INTO "ServiceOperations" ("ServiceId", "OperationTypeId", "Price", "IsActive", "CreatedAt", "IsDeleted")
SELECT 9, 8, 0, true, NOW(), false  -- New Subscription
WHERE NOT EXISTS (SELECT 1 FROM "ServiceOperations" WHERE "ServiceId" = 9 AND "OperationTypeId" = 8);

-- Seed Internet Plans
INSERT INTO "InternetPlans" ("Id", "Name", "NameAr", "Description", "SpeedMbps", "DataLimitGB", "IsUnlimited", "MonthlyPrice", "YearlyPrice", "InstallationFee", "DurationMonths", "Features", "IsFeatured", "IsActive", "Badge", "BadgeColor", "CreatedAt", "IsDeleted")
SELECT 'a1000000-0000-0000-0000-000000000001'::uuid, 'Fiber 25 Mbps', 'فايبر 25 ميغا', 'باقة أساسية للتصفح والاستخدام الخفيف', 25, NULL, true, 25000, 250000, 50000, 1, '["تصفح الإنترنت","شبكات التواصل","بث فيديو SD"]', false, true, NULL, NULL, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "InternetPlans" WHERE "Id" = 'a1000000-0000-0000-0000-000000000001'::uuid);

INSERT INTO "InternetPlans" ("Id", "Name", "NameAr", "Description", "SpeedMbps", "DataLimitGB", "IsUnlimited", "MonthlyPrice", "YearlyPrice", "InstallationFee", "DurationMonths", "Features", "IsFeatured", "IsActive", "Badge", "BadgeColor", "CreatedAt", "IsDeleted")
SELECT 'a1000000-0000-0000-0000-000000000002'::uuid, 'Fiber 50 Mbps', 'فايبر 50 ميغا', 'باقة متوسطة للعائلات والعمل من المنزل', 50, NULL, true, 40000, 400000, 50000, 1, '["تصفح الإنترنت","شبكات التواصل","بث فيديو HD","ألعاب أونلاين"]', false, true, NULL, NULL, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "InternetPlans" WHERE "Id" = 'a1000000-0000-0000-0000-000000000002'::uuid);

INSERT INTO "InternetPlans" ("Id", "Name", "NameAr", "Description", "SpeedMbps", "DataLimitGB", "IsUnlimited", "MonthlyPrice", "YearlyPrice", "InstallationFee", "DurationMonths", "Features", "IsFeatured", "IsActive", "Badge", "BadgeColor", "CreatedAt", "IsDeleted")
SELECT 'a1000000-0000-0000-0000-000000000003'::uuid, 'Fiber 100 Mbps', 'فايبر 100 ميغا', 'باقة احترافية للاستخدام الكثيف والبث العالي', 100, NULL, true, 60000, 600000, 50000, 1, '["تصفح الإنترنت","شبكات التواصل","بث فيديو 4K","ألعاب أونلاين","تحميل سريع","اجتماعات فيديو"]', true, true, 'الأكثر طلباً', '#10B981', NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "InternetPlans" WHERE "Id" = 'a1000000-0000-0000-0000-000000000003'::uuid);

INSERT INTO "InternetPlans" ("Id", "Name", "NameAr", "Description", "SpeedMbps", "DataLimitGB", "IsUnlimited", "MonthlyPrice", "YearlyPrice", "InstallationFee", "DurationMonths", "Features", "IsFeatured", "IsActive", "Badge", "BadgeColor", "CreatedAt", "IsDeleted")
SELECT 'a1000000-0000-0000-0000-000000000004'::uuid, 'Fiber 200 Mbps', 'فايبر 200 ميغا', 'أقصى سرعة للمستخدمين المحترفين والشركات الصغيرة', 200, NULL, true, 90000, 900000, 50000, 1, '["تصفح الإنترنت","شبكات التواصل","بث فيديو 4K","ألعاب أونلاين","تحميل فائق السرعة","اجتماعات فيديو HD","خوادم منزلية","أولوية في الدعم"]', false, true, 'VIP', '#8B5CF6', NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "InternetPlans" WHERE "Id" = 'a1000000-0000-0000-0000-000000000004'::uuid);

-- Verify
SELECT 'Services:' AS info, "Id", "Name" FROM "Services" WHERE "Id" = 9
UNION ALL
SELECT 'OperationTypes:', "Id"::text, "Name" FROM "OperationTypes" WHERE "Id" = 8;

SELECT COUNT(*) AS internet_plans_count FROM "InternetPlans";
