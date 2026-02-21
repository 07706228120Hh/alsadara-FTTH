#!/bin/bash

echo "=== Test credit-customers endpoint (check DLL has it) ==="
strings /var/www/sadara-api/Sadara.API.dll 2>/dev/null | grep -i "credit-customers"

echo ""
echo "=== Test operators-dashboard response ==="
# Login first to get token
TOKEN=$(curl -s -X POST http://localhost:5000/api/companies/login \
  -H "Content-Type: application/json" \
  -d '{"phone":"07711520410","password":"12345678"}' | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null)

if [ -z "$TOKEN" ]; then
  echo "Login failed, trying with jq..."
  TOKEN=$(curl -s -X POST http://localhost:5000/api/companies/login \
    -H "Content-Type: application/json" \
    -d '{"phone":"07711520410","password":"12345678"}' | jq -r '.token // empty')
fi

echo "Token length: ${#TOKEN}"

if [ -n "$TOKEN" ]; then
  echo ""
  echo "=== credit-customers response ==="
  curl -s http://localhost:5000/api/ftth-accounting/credit-customers/81ea550b-aaac-4e5a-a04a-82cd603aff44 \
    -H "Authorization: Bearer $TOKEN"
  
  echo ""
  echo ""
  echo "=== operators-dashboard response (first 1000 chars)==="
  curl -s http://localhost:5000/api/ftth-accounting/operators-dashboard \
    -H "Authorization: Bearer $TOKEN" | head -c 1000
fi
