#!/bin/bash
# Test my-assigned endpoint
python3 -c "import json; json.dump({'PhoneNumber':'0772','Password':'123456','CompanyCode':'001'}, open('/tmp/login.json','w'))"
curl -s -X POST http://localhost:5000/api/companies/login -H 'Content-Type: application/json' -d @/tmp/login.json > /tmp/resp.json
TOKEN=$(python3 -c "import json; d=json.load(open('/tmp/resp.json')); print(d['data']['Token'])")
echo "TOKEN_LEN=${#TOKEN}"
echo "--- my-assigned ---"
curl -s -w '\nHTTP:%{http_code}\n' -H "Authorization: Bearer $TOKEN" 'http://localhost:5000/api/servicerequests/my-assigned?page=1&pageSize=2&includeCompleted=true' | tail -3
echo "--- regular ---"
curl -s -w '\nHTTP:%{http_code}\n' -H "Authorization: Bearer $TOKEN" 'http://localhost:5000/api/servicerequests?page=1&pageSize=1' | tail -2
