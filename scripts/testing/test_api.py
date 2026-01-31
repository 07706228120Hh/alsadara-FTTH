import urllib.request
import json

# اختبار إضافة مواطن
data = json.dumps({
    'fullName': 'مواطن اختبار',
    'phoneNumber': '0512345678',
    'password': 'Test123456',
    'email': 'citizen@test.com',
    'city': 'الرياض',
    'district': 'النخيل'
}).encode('utf-8')

req = urllib.request.Request('http://localhost:5000/api/internal/citizens', data=data, method='POST')
req.add_header('Content-Type', 'application/json')
req.add_header('X-Api-Key', 'sadara-internal-2024-secure-key')

try:
    with urllib.request.urlopen(req) as response:
        print(response.read().decode())
except urllib.error.HTTPError as e:
    print(f'Error {e.code}: {e.read().decode()}')

