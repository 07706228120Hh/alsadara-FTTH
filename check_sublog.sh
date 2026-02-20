#!/bin/bash
PGPASSWORD=sadara_secure_password_2024 psql -h 127.0.0.1 -U sadara_user -d sadara_db << 'SQLEOF'
\pset format wrapped
SELECT * FROM "SubscriptionLogs" WHERE "IsDeleted"=false ORDER BY "CreatedAt" DESC LIMIT 1;
SQLEOF
