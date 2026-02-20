#!/bin/bash
curl -s -X POST http://localhost:5000/api/unified-auth/login -H 'Content-Type: application/json' -d '{"username":"superadmin","password":"Admin@123"}' > /tmp/login2.json
TOKEN=$(python3 -c "import json; d=json.load(open('/tmp/login2.json')); print(d.get('data',{}).get('token','NO'))")
echo "TOKEN: ${TOKEN:0:50}"
curl -s "http://localhost:5000/api/ftth-accounting/operators-dashboard" -H "Authorization: Bearer $TOKEN" > /tmp/dash2.json
python3 << 'PYEOF'
import json
d=json.load(open('/tmp/dash2.json'))
ops=d.get('data',{}).get('operators',[])
if ops:
    uid=ops[0]['userId']
    cid=ops[0].get('companyId','N/A')
    print(f'UID:{uid} CID:{cid}')
    # Now get operator summary
    import subprocess
    import os
    token = open('/tmp/token.txt').read().strip()
    r = subprocess.run(['curl','-s',f'http://localhost:5000/api/ftth-accounting/operator-summary/{uid}?companyId={cid}','-H',f'Authorization: Bearer {token}'], capture_output=True, text=True)
    sd = json.loads(r.stdout)
    txns = sd.get('data',{}).get('transactions',[])
    if txns:
        print('FIRST_TX:')
        print(json.dumps(txns[0], indent=2, ensure_ascii=False)[:1500])
    else:
        print('NO_TXNS')
        print(json.dumps(sd, indent=2)[:500])
else:
    print('NO_OPS')
    print(json.dumps(d, indent=2)[:500])
PYEOF
echo "$TOKEN" > /tmp/token.txt
