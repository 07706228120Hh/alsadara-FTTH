#!/bin/bash
STORED=$(PGPASSWORD=sadara_secure_password_2024 psql -h localhost -U sadara_user -d sadara_db -t -A -c 'SELECT "PasswordHash" FROM "Agents" LIMIT 1;')
echo "Stored hash: $STORED"

for PW in "123" "12345" "123456" "Agent@123!" "password"; do
  H=$(python3 -c "
import hashlib, base64
h = hashlib.sha256(('${PW}SadaraSalt2024').encode()).digest()
print(base64.b64encode(h).decode())
")
  MATCH=""
  if [ "$H" = "$STORED" ]; then MATCH=" <<<< MATCH!"; fi
  echo "  '$PW' -> $H$MATCH"
done

echo ""
echo "=== Reset password to 123 ==="
NEWHASH=$(python3 -c "
import hashlib, base64
h = hashlib.sha256(('123SadaraSalt2024').encode()).digest()
print(base64.b64encode(h).decode())
")
echo "New hash for '123': $NEWHASH"
PGPASSWORD=sadara_secure_password_2024 psql -h localhost -U sadara_user -d sadara_db -c "UPDATE \"Agents\" SET \"PasswordHash\" = '$NEWHASH' WHERE \"AgentCode\" = 'AGT-0001';"

echo ""
echo "=== Test login after reset ==="
curl -s -X POST http://localhost:5000/api/agents/login \
  -H 'Content-Type: application/json' \
  -d '{"agentCode":"احمد","password":"123"}' | python3 -m json.tool 2>/dev/null
