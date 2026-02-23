SELECT "Id", "FullName", LENGTH("FirstSystemPermissionsV2") as v2_len
FROM "Users"
WHERE "IsDeleted" = false AND "FirstSystemPermissionsV2" IS NOT NULL
  AND "FirstSystemPermissionsV2" != '' AND "FirstSystemPermissionsV2" != 'null'
LIMIT 5;
