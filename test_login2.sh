#!/bin/bash
echo "=== Testing SuperAdmin login ==="
RESP=$(curl -s -X POST http://localhost:5000/api/superadmin/login -H 'Content-Type: application/json' -d '{"username":"superadmin","password":"Admin@123"}')
echo "SuperAdmin response: $RESP"

echo ""
echo "=== Testing with different username ==="
RESP2=$(curl -s -X POST http://localhost:5000/api/superadmin/login -H 'Content-Type: application/json' -d '{"username":"admin","password":"Admin@123"}')
echo "Admin response: $RESP2"

echo ""
echo "=== Trying unified auth ==="
RESP3=$(curl -s -X POST http://localhost:5000/api/unified-auth/login -H 'Content-Type: application/json' -d '{"identifier":"superadmin","password":"Admin@123"}')
echo "Unified response: ${RESP3:0:200}"
