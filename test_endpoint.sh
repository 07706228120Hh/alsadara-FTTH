#!/bin/bash
TOKEN=$(curl -s -X POST http://localhost:5000/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"phoneNumber":"07700000000","password":"Admin@123"}' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin).get("token",""))')
echo "TOKEN=$TOKEN"
RESP=$(curl -s -H "Authorization: Bearer $TOKEN" http://localhost:5000/api/taskaudits/bulk)
echo "RESPONSE=$RESP"
