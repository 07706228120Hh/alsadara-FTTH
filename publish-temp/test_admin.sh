#!/bin/bash
# Test with admin auth

# Login as admin
echo "=== Admin Login ==="
RESULT=$(curl -s http://localhost:5000/api/auth/login -X POST -H 'Content-Type: application/json' \
  -d '{"phoneNumber":"07901234567","password":"Sadara@2024"}')
SUCCESS=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('success','?'))" 2>/dev/null)
echo "Admin login: $SUCCESS"

TOKEN=""
if [ "$SUCCESS" = "True" ]; then
  TOKEN=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('token',''))" 2>/dev/null)
fi

# Try SuperAdmin seed password
if [ -z "$TOKEN" ]; then
  RESULT=$(curl -s http://localhost:5000/api/auth/login -X POST -H 'Content-Type: application/json' \
    -d '{"phoneNumber":"07700000001","password":"Admin@123"}')
  TOKEN=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('token',''))" 2>/dev/null)
  echo "SuperAdmin login attempt"
fi

if [ -n "$TOKEN" ] && [ "$TOKEN" != "None" ] && [ "$TOKEN" != "" ]; then
  echo "Got token (${#TOKEN} chars)"
  
  echo ""
  echo "=== Service Requests ==="
  curl -s "http://localhost:5000/api/servicerequests?pageSize=3" \
    -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys,json
d=json.load(sys.stdin)
reqs = d.get('data',[])
print(f'Total: {d.get(\"total\",0)}')
for r in reqs[:3]:
    print(f'  #{r.get(\"requestNumber\",\"?\")} | agentId: {r.get(\"agentId\",\"null\")} | agentName: {r.get(\"agentName\",\"null\")} | agentCode: {r.get(\"agentCode\",\"null\")} | status: {r.get(\"status\",\"?\")}')
" 2>/dev/null || echo "Could not parse"

else
  echo "Could not authenticate as admin"
  
  # Check users table for any admin
  echo ""
  echo "=== Checking API structure ==="
  echo "me/payment endpoint:"
  curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:5000/api/agents/me/payment
  echo ""
  echo "me/accounting endpoint:"
  curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/api/agents/me/accounting
  echo ""
  echo "me/balance-request endpoint:"
  curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:5000/api/agents/me/balance-request
  echo ""
  echo "me/change-password endpoint:"
  curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:5000/api/agents/me/change-password
  echo ""
  echo "servicerequests endpoint:"
  curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/api/servicerequests
  echo ""
fi
