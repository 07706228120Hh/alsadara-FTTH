#!/bin/bash
# Test agent login, payment endpoint, and service requests

# 1. Login
echo "=== Agent Login ==="
RESULT=$(curl -s http://localhost:5000/api/agents/login -X POST -H 'Content-Type: application/json' -d @/tmp/agent_login.json)
SUCCESS=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('success','?'))")
echo "Login success: $SUCCESS"

if [ "$SUCCESS" = "True" ]; then
  TOKEN=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('token',''))")
  echo "Token length: ${#TOKEN}"
  
  # 2. Test me/payment endpoint
  echo ""
  echo "=== Test me/payment ==="
  PAY_RESULT=$(curl -s -w "\n%{http_code}" http://localhost:5000/api/agents/me/payment -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{"amount":5000,"description":"test payment","category":6}')
  PAY_CODE=$(echo "$PAY_RESULT" | tail -1)
  PAY_BODY=$(echo "$PAY_RESULT" | head -1)
  echo "Payment HTTP code: $PAY_CODE"
  echo "Payment response: $(echo "$PAY_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('success','?'), d.get('message',''))" 2>/dev/null || echo "$PAY_BODY")"
  
  # 3. Test service requests (with auth from admin - use agent token to check if requests have agentName)
  echo ""
  echo "=== Service Requests (agent info check) ==="
  SR_RESULT=$(curl -s "http://localhost:5000/api/agents/me/service-requests?pageSize=2" \
    -H "Authorization: Bearer $TOKEN")
  echo "$SR_RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
reqs = d.get('data',[])
print(f'Total requests: {d.get(\"total\",0)}')
for r in reqs[:2]:
    print(f'  #{r.get(\"requestNumber\",\"?\")} | agent: {r.get(\"agentName\",\"N/A\")} | status: {r.get(\"status\",\"?\")}')
" 2>/dev/null || echo "Parse error"

else
  echo "Login failed: $RESULT"
  
  # Try with agentCode
  echo ""
  echo "=== Try login with agentCode ==="
  RESULT2=$(curl -s http://localhost:5000/api/agents/login -X POST -H 'Content-Type: application/json' \
    -d '{"agentCode":"AGT-0001","password":"Sadara@2024"}')
  echo "$RESULT2" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('success','?'), d.get('message',''))" 2>/dev/null
  
  RESULT3=$(curl -s http://localhost:5000/api/agents/login -X POST -H 'Content-Type: application/json' \
    -d '{"agentCode":"AGT-0001","password":"123456"}')
  echo "$RESULT3" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('success','?'), d.get('message',''))" 2>/dev/null
fi
