#!/bin/bash
PGPASSWORD=sadara_secure_password_2024 psql -h 127.0.0.1 -U sadara_user -d sadara_db << 'SQLEOF'
\pset format unaligned
\pset fieldsep '|'
\pset tuples_only on
SELECT "Id", "PhoneNumber", "Role", "FullName" FROM "Users" WHERE "IsDeleted"=false LIMIT 10;
SQLEOF
