#!/bin/bash
curl -s -X POST 'https://api.ramzalsadara.tech/api/agents/login' \
  -H 'Content-Type: application/json; charset=utf-8' \
  -d '{"agentCode":"AGT-0001","password":"123"}' | python3 -m json.tool 2>/dev/null || echo "JSON parse failed"
