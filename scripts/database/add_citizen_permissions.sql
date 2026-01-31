-- إضافة مجموعات الصلاحيات الجديدة
INSERT INTO "PermissionGroups" ("Id", "Code", "NameAr", "Name", "Description", "SystemType", "Icon", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 8, 'citizen', 'إدارة المواطنين', 'Citizens Management', 'صلاحيات إدارة المواطنين في نظام المواطن', 3, 'people', 8, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "PermissionGroups" WHERE "Id" = 8);

INSERT INTO "PermissionGroups" ("Id", "Code", "NameAr", "Name", "Description", "SystemType", "Icon", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 9, 'subscriptions', 'إدارة الاشتراكات', 'Subscriptions Management', 'صلاحيات إدارة الاشتراكات', 3, 'card_membership', 9, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "PermissionGroups" WHERE "Id" = 9);

INSERT INTO "PermissionGroups" ("Id", "Code", "NameAr", "Name", "Description", "SystemType", "Icon", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 10, 'payments', 'إدارة المدفوعات', 'Payments Management', 'صلاحيات إدارة المدفوعات', 0, 'payment', 10, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "PermissionGroups" WHERE "Id" = 10);

INSERT INTO "PermissionGroups" ("Id", "Code", "NameAr", "Name", "Description", "SystemType", "Icon", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 11, 'support', 'الدعم الفني', 'Support Management', 'صلاحيات إدارة تذاكر الدعم الفني', 3, 'support_agent', 11, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "PermissionGroups" WHERE "Id" = 11);

INSERT INTO "PermissionGroups" ("Id", "Code", "NameAr", "Name", "Description", "SystemType", "Icon", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 12, 'admin', 'إدارة النظام', 'System Administration', 'صلاحيات إدارة النظام العليا', 0, 'admin_panel_settings', 12, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "PermissionGroups" WHERE "Id" = 12);

-- إضافة صلاحية ربط الشركة بنظام المواطن (إذا لم تكن موجودة)
INSERT INTO "Permissions" ("Id", "PermissionGroupId", "Module", "Action", "Code", "NameAr", "Name", "Description", "SystemType", "RequiresLinkedCompany", "IsFirstSystem", "IsSecondSystem", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 15, 2, 'companies', 'link_citizen', 'companies.link_citizen', 'ربط نظام المواطن', 'Link Citizen Portal', 'Link company to citizen portal', 1, false, false, true, 15, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Id" = 15);

-- إدارة المواطنين (Group 8)
INSERT INTO "Permissions" ("Id", "PermissionGroupId", "Module", "Action", "Code", "NameAr", "Name", "Description", "SystemType", "RequiresLinkedCompany", "IsFirstSystem", "IsSecondSystem", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 70, 8, 'citizen', 'view', 'citizen.view', 'عرض المواطنين', 'View Citizens', 'View citizens list', 3, true, false, true, 70, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Id" = 70);

INSERT INTO "Permissions" ("Id", "PermissionGroupId", "Module", "Action", "Code", "NameAr", "Name", "Description", "SystemType", "RequiresLinkedCompany", "IsFirstSystem", "IsSecondSystem", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 71, 8, 'citizen', 'create', 'citizen.create', 'إضافة مواطن', 'Create Citizen', 'Create new citizen', 3, true, false, true, 71, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Id" = 71);

INSERT INTO "Permissions" ("Id", "PermissionGroupId", "Module", "Action", "Code", "NameAr", "Name", "Description", "SystemType", "RequiresLinkedCompany", "IsFirstSystem", "IsSecondSystem", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 72, 8, 'citizen', 'edit', 'citizen.edit', 'تعديل مواطن', 'Edit Citizen', 'Edit citizen info', 3, true, false, true, 72, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Id" = 72);

INSERT INTO "Permissions" ("Id", "PermissionGroupId", "Module", "Action", "Code", "NameAr", "Name", "Description", "SystemType", "RequiresLinkedCompany", "IsFirstSystem", "IsSecondSystem", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 73, 8, 'citizen', 'delete', 'citizen.delete', 'حذف مواطن', 'Delete Citizen', 'Delete citizen', 3, true, false, true, 73, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Id" = 73);

INSERT INTO "Permissions" ("Id", "PermissionGroupId", "Module", "Action", "Code", "NameAr", "Name", "Description", "SystemType", "RequiresLinkedCompany", "IsFirstSystem", "IsSecondSystem", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 74, 8, 'citizen', 'portal_dashboard', 'citizen.portal_dashboard', 'لوحة نظام المواطن', 'Portal Dashboard', 'Access citizen portal dashboard', 3, true, false, true, 74, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Id" = 74);

-- إدارة الاشتراكات (Group 9)
INSERT INTO "Permissions" ("Id", "PermissionGroupId", "Module", "Action", "Code", "NameAr", "Name", "Description", "SystemType", "RequiresLinkedCompany", "IsFirstSystem", "IsSecondSystem", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 80, 9, 'subscriptions', 'view', 'subscriptions.view', 'عرض الاشتراكات', 'View Subscriptions', 'View subscriptions', 3, true, false, true, 80, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Id" = 80);

INSERT INTO "Permissions" ("Id", "PermissionGroupId", "Module", "Action", "Code", "NameAr", "Name", "Description", "SystemType", "RequiresLinkedCompany", "IsFirstSystem", "IsSecondSystem", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 81, 9, 'subscriptions', 'create', 'subscriptions.create', 'إنشاء اشتراك', 'Create Subscription', 'Create new subscription', 3, true, false, true, 81, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Id" = 81);

INSERT INTO "Permissions" ("Id", "PermissionGroupId", "Module", "Action", "Code", "NameAr", "Name", "Description", "SystemType", "RequiresLinkedCompany", "IsFirstSystem", "IsSecondSystem", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 82, 9, 'subscriptions', 'edit', 'subscriptions.edit', 'تعديل اشتراك', 'Edit Subscription', 'Edit subscription', 3, true, false, true, 82, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Id" = 82);

INSERT INTO "Permissions" ("Id", "PermissionGroupId", "Module", "Action", "Code", "NameAr", "Name", "Description", "SystemType", "RequiresLinkedCompany", "IsFirstSystem", "IsSecondSystem", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 83, 9, 'subscriptions', 'cancel', 'subscriptions.cancel', 'إلغاء اشتراك', 'Cancel Subscription', 'Cancel subscription', 3, true, false, true, 83, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Id" = 83);

INSERT INTO "Permissions" ("Id", "PermissionGroupId", "Module", "Action", "Code", "NameAr", "Name", "Description", "SystemType", "RequiresLinkedCompany", "IsFirstSystem", "IsSecondSystem", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 84, 9, 'subscriptions', 'manage_plans', 'subscriptions.manage_plans', 'إدارة الباقات', 'Manage Plans', 'Manage subscription plans', 3, true, false, true, 84, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Id" = 84);

-- إدارة المدفوعات (Group 10)
INSERT INTO "Permissions" ("Id", "PermissionGroupId", "Module", "Action", "Code", "NameAr", "Name", "Description", "SystemType", "RequiresLinkedCompany", "IsFirstSystem", "IsSecondSystem", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 85, 10, 'payments', 'view', 'payments.view', 'عرض المدفوعات', 'View Payments', 'View payments', 0, false, true, true, 85, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Id" = 85);

INSERT INTO "Permissions" ("Id", "PermissionGroupId", "Module", "Action", "Code", "NameAr", "Name", "Description", "SystemType", "RequiresLinkedCompany", "IsFirstSystem", "IsSecondSystem", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 86, 10, 'payments', 'record', 'payments.record', 'تسجيل دفعة', 'Record Payment', 'Record payment', 0, false, true, true, 86, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Id" = 86);

INSERT INTO "Permissions" ("Id", "PermissionGroupId", "Module", "Action", "Code", "NameAr", "Name", "Description", "SystemType", "RequiresLinkedCompany", "IsFirstSystem", "IsSecondSystem", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 87, 10, 'payments', 'refund', 'payments.refund', 'معالجة استرداد', 'Process Refund', 'Process refund', 0, false, true, true, 87, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Id" = 87);

-- الدعم الفني (Group 11)
INSERT INTO "Permissions" ("Id", "PermissionGroupId", "Module", "Action", "Code", "NameAr", "Name", "Description", "SystemType", "RequiresLinkedCompany", "IsFirstSystem", "IsSecondSystem", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 88, 11, 'support', 'view', 'support.view', 'عرض التذاكر', 'View Tickets', 'View support tickets', 3, true, false, true, 88, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Id" = 88);

INSERT INTO "Permissions" ("Id", "PermissionGroupId", "Module", "Action", "Code", "NameAr", "Name", "Description", "SystemType", "RequiresLinkedCompany", "IsFirstSystem", "IsSecondSystem", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 89, 11, 'support', 'respond', 'support.respond', 'الرد على التذاكر', 'Respond to Tickets', 'Respond to tickets', 3, true, false, true, 89, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Id" = 89);

-- صلاحية إدارة نظام المواطن (Group 12)
INSERT INTO "Permissions" ("Id", "PermissionGroupId", "Module", "Action", "Code", "NameAr", "Name", "Description", "SystemType", "RequiresLinkedCompany", "IsFirstSystem", "IsSecondSystem", "DisplayOrder", "IsActive", "CreatedAt", "IsDeleted")
SELECT 95, 12, 'admin', 'citizen_portal', 'admin.citizen_portal', 'إدارة نظام المواطن', 'Citizen Portal Admin', 'Full citizen portal management', 3, false, false, true, 95, true, NOW(), false
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Id" = 95);

-- تحديث تسلسل الـ Id
SELECT setval(pg_get_serial_sequence('"PermissionGroups"', 'Id'), COALESCE((SELECT MAX("Id") FROM "PermissionGroups"), 1) + 1, false);
SELECT setval(pg_get_serial_sequence('"Permissions"', 'Id'), COALESCE((SELECT MAX("Id") FROM "Permissions"), 1) + 1, false);

-- عرض الصلاحيات بعد الإضافة
SELECT COUNT(*) as total_permissions FROM "Permissions";
SELECT "Id", "Code", "NameAr" FROM "Permissions" WHERE "Id" >= 70 ORDER BY "Id";
