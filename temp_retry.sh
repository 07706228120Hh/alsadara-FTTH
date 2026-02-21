#!/bin/bash
# Login and get token
TOKEN=$(curl -s -X POST http://localhost:5000/api/superadmin/login \
  -H "Content-Type: application/json" \
  -d '{"username":"superadmin","password":"Admin@123"}' | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('token',''))" 2>/dev/null)

if [ -z "$TOKEN" ]; then
  echo "FAIL: Could not login"
  # Try to see raw response
  curl -s -X POST http://localhost:5000/api/superadmin/login \
    -H "Content-Type: application/json" \
    -d '{"username":"superadmin","password":"Admin@123"}'
  exit 1
fi

echo "TOKEN_LENGTH: ${#TOKEN}"

# Call retry-missing-entries
echo ""
echo "=== Retry missing entries ==="
curl -s -X POST http://localhost:5000/api/ftth-accounting/retry-missing-entries \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN"

echo ""
echo ""
echo "=== Recalculate balances ==="
curl -s -X POST http://localhost:5000/api/ftth-accounting/recalculate-balances \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN"

echo ""
echo ""
echo "=== Final account check ==="
sudo -u postgres psql -d sadara_db -c 'SELECT "Code", "Name", "CurrentBalance" FROM "Accounts" WHERE "IsActive" = true AND "IsDeleted" = false AND "CurrentBalance" != 0 ORDER BY "Code";'
