#!/bin/bash
PGPASSWORD=sadara_secure_password_2024 psql -h localhost -U sadara_user -d sadara_db -c "
SELECT \"Id\", \"CustomerName\", \"CollectionType\", \"PaymentStatus\", \"OperationType\", \"UserId\"
FROM \"SubscriptionLogs\"
WHERE \"IsDeleted\" = false
ORDER BY \"Id\" DESC
LIMIT 10;
"
