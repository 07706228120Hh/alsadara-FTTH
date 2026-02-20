#!/bin/bash
# Get admin users
PGPASSWORD=sadara_secure_password_2024 psql -h 127.0.0.1 -U sadara_user -d sadara_db -t -A -F '|' << 'SQLEOF'
SELECT "Id", "PhoneNumber", "Role", "FullName" FROM "Users" WHERE "IsDeleted"=false AND "Role" IN (0,1) LIMIT 5;
SQLEOF

echo "---"

# Try login
python3 << 'PYEOF'
import json, subprocess

# Try superadmin
r = subprocess.run(
    ['curl', '-s', '-X', 'POST', 'http://localhost:5000/api/v2/auth/login',
     '-H', 'Content-Type: application/json',
     '-d', json.dumps({"username":"9647700000001","password":"Admin@123!"})],
    capture_output=True, text=True
)
d = json.loads(r.stdout) if r.stdout else {}
token = d.get('data',{}).get('token','')
if token:
    print(f"LOGIN_OK: {token[:50]}...")

    # Get dashboard
    r2 = subprocess.run(
        ['curl', '-s', 'http://localhost:5000/api/ftth-accounting/operators-dashboard',
         '-H', f'Authorization: Bearer {token}'],
        capture_output=True, text=True
    )
    dash = json.loads(r2.stdout)
    ops = dash.get('data',{}).get('operators',[])
    print(f"Operators count: {len(ops)}")
    if ops:
        uid = ops[0]['userId']
        cid = ops[0].get('companyId','')
        print(f"First operator: {uid} company: {cid}")

        # Get summary
        r3 = subprocess.run(
            ['curl', '-s', f'http://localhost:5000/api/ftth-accounting/operator-summary/{uid}?companyId={cid}',
             '-H', f'Authorization: Bearer {token}'],
            capture_output=True, text=True
        )
        sd = json.loads(r3.stdout)
        txns = sd.get('data',{}).get('transactions',[])
        print(f"Transactions: {len(txns)}")
        if txns:
            tx = txns[0]
            print("FIRST_TRANSACTION:")
            print(json.dumps(tx, indent=2, ensure_ascii=False)[:2000])
else:
    print(f"LOGIN_FAIL: {json.dumps(d, ensure_ascii=False)[:300]}")
PYEOF
