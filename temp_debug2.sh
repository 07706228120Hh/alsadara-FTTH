#!/bin/bash
export PGPASSWORD=sadara_secure_password_2024

echo "=== SubscriptionLogs - ALL COLUMNS ==="
psql -h localhost -U sadara_user -d sadara_db -c "SELECT \"Id\", \"CollectionType\", \"PaymentStatus\", \"OperationType\", \"CustomerName\", \"UserId\", \"IsDeleted\" FROM \"SubscriptionLogs\" WHERE \"IsDeleted\" = false ORDER BY \"Id\" LIMIT 10;"

echo ""
echo "=== Check credit-specific logs ==="
psql -h localhost -U sadara_user -d sadara_db -c "SELECT \"Id\", \"CollectionType\", \"PaymentStatus\", \"CustomerName\", \"Amount\" FROM \"SubscriptionLogs\" WHERE \"IsDeleted\" = false AND \"CollectionType\" = 'credit';"

echo ""
echo "=== Check CollectionType values ==="
psql -h localhost -U sadara_user -d sadara_db -c "SELECT DISTINCT \"CollectionType\" FROM \"SubscriptionLogs\" WHERE \"IsDeleted\" = false;"

echo ""
echo "=== Check OperationType values ==="  
psql -h localhost -U sadara_user -d sadara_db -c "SELECT DISTINCT \"OperationType\" FROM \"SubscriptionLogs\" WHERE \"IsDeleted\" = false;"

echo ""
echo "=== Check PaymentStatus values ==="
psql -h localhost -U sadara_user -d sadara_db -c "SELECT DISTINCT \"PaymentStatus\" FROM \"SubscriptionLogs\" WHERE \"IsDeleted\" = false;"

echo ""
echo "=== API logs (last 30 lines) ==="
journalctl -u sadara-api --no-pager -n 30
