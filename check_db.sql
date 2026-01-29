SELECT 'Permissions count: ' || COUNT(*)::text as info FROM "Permissions";
SELECT 'PermissionGroups count: ' || COUNT(*)::text as info FROM "PermissionGroups";
SELECT 'PermissionTemplates count: ' || COUNT(*)::text as info FROM "PermissionTemplates";
SELECT 'TemplatePermissions count: ' || COUNT(*)::text as info FROM "TemplatePermissions";
SELECT "Id", "Code", "NameAr" FROM "PermissionGroups" ORDER BY "Id";
