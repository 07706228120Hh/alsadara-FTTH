#!/bin/bash
# Create JSON body
python3 -c 'import json; open("/tmp/req.json","w").write(json.dumps({"username":"superadmin","password":"Admin@123"}))'
echo "Request body:"
cat /tmp/req.json
echo

# Login
curl -s -X POST http://localhost:5000/api/v2/auth/login \
  -H "Content-Type: application/json" \
  -d @/tmp/req.json > /tmp/login_resp.json

# Extract token
python3 << 'EOF'
import json
d = json.load(open("/tmp/login_resp.json"))
token = d.get("data",{}).get("token","")
if token:
    print(f"TOKEN_OK:{token[:50]}...")
    open("/tmp/jwt_token.txt","w").write(token)
else:
    print("LOGIN_FAIL:")
    print(json.dumps(d,indent=2,ensure_ascii=False)[:500])
EOF

# Get operator summary with token
if [ -f /tmp/jwt_token.txt ]; then
  TOKEN=$(cat /tmp/jwt_token.txt)

  # Get dashboard
  curl -s "http://localhost:5000/api/ftth-accounting/operators-dashboard" \
    -H "Authorization: Bearer $TOKEN" > /tmp/dash3.json

  python3 << 'EOF2'
import json, subprocess
d = json.load(open("/tmp/dash3.json"))
ops = d.get("data",{}).get("operators",[])
if not ops:
    print("NO_OPS:", json.dumps(d,indent=2)[:300])
else:
    uid = ops[0]["userId"]
    cid = ops[0].get("companyId","")
    print(f"Operator: {uid} Company: {cid}")

    # Get operator summary
    TOKEN = open("/tmp/jwt_token.txt").read().strip()
    r = subprocess.run(
        ["curl","-s",f"http://localhost:5000/api/ftth-accounting/operator-summary/{uid}?companyId={cid}",
         "-H",f"Authorization: Bearer {TOKEN}"],
        capture_output=True, text=True
    )
    sd = json.loads(r.stdout)
    txns = sd.get("data",{}).get("transactions",[])
    print(f"Total transactions: {len(txns)}")
    if txns:
        print("FIRST_TX:")
        print(json.dumps(txns[0], indent=2, ensure_ascii=False)[:2000])
    else:
        print("NO_TXNS, response:")
        print(json.dumps(sd,indent=2,ensure_ascii=False)[:500])
EOF2
fi
