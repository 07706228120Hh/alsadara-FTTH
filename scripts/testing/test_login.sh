#!/bin/bash
curl -s -X POST http://localhost:5000/api/superadmin/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin@sadara.iq","password":"Admin@123!"}'
