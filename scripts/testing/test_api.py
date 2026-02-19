import json, subprocess, sys
# Ensure correct login JSON
json.dump({'CompanyCode':'SADARA','Username':'0772','Password':'123456'}, open('/tmp/login.json','w'))
resp = subprocess.run(['curl', '-s', '-X', 'POST', 'http://localhost:5000/api/companies/login', '-H', 'Content-Type: application/json', '-d', '@/tmp/login.json'], capture_output=True, text=True)
print("LOGIN:", resp.stdout[:300])
d = json.loads(resp.stdout)
token = d.get('data', {}).get('Token', '')
print("TOKEN_LEN:", len(token))
if not token:
    sys.exit(1)
r2 = subprocess.run(['curl', '-s', '-w', '\nHTTP:%{http_code}', '-H', 'Authorization: Bearer ' + token, 'http://localhost:5000/api/servicerequests/my-assigned?page=1&pageSize=2&includeCompleted=true'], capture_output=True, text=True)
print("MY-ASSIGNED:", r2.stdout[:500])
r3 = subprocess.run(['curl', '-s', '-w', '\nHTTP:%{http_code}', '-H', 'Authorization: Bearer ' + token, 'http://localhost:5000/api/servicerequests?page=1&pageSize=1'], capture_output=True, text=True)
print("REGULAR:", r3.stdout[:300])
