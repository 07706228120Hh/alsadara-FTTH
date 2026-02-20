#!/bin/bash
PGPASSWORD=sadara_secure_password_2024 psql -h 127.0.0.1 -U sadara_user -d sadara_db -t -c "
SELECT \"PhoneNumber\", \"Role\"::int, \"FullName\"
FROM \"Users\"
WHERE \"IsDeleted\" = false AND \"Role\" IN (0,1)
LIMIT 3;
"
