#!/bin/bash
TOKEN=$(curl -s -X POST http://localhost:5000/api/superadmin/login -H "Content-Type: application/json" -d '{"username":"superadmin","password":"Admin@123"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['token'])")
curl -s http://localhost:5000/api/accounting/dashboard -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json; d=json.load(sys.stdin)['data']; print('PendingDetails:', d.get('PendingDetails',{})); print('Collections:', d.get('Collections',{}))"
