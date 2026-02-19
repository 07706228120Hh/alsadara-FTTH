#!/bin/bash
TOKEN=$(curl -s -X POST http://localhost:5000/api/superadmin/login -H 'Content-Type: application/json' -d '{"username":"superadmin","password":"Admin@123"}' | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('data',{}).get('token','') if isinstance(r.get('data'),dict) else r.get('token',''))")
echo "Token: ${TOKEN:0:20}..."
curl -s http://localhost:5000/api/accounting/dashboard -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys,json
try:
    r=json.load(sys.stdin)
    d=r.get('data',r)
    print('PendingDetails:', d.get('PendingDetails',{}))
    print('Collections:', d.get('Collections',{}))
except Exception as e:
    print('Error:', e)
"
