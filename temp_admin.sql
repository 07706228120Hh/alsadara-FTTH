SELECT "Id", "Username", "FullName", "Role" 
FROM "Users" 
WHERE ("Role" = 0 OR "Username" = 'superadmin') AND "IsDeleted" = false
LIMIT 5;
