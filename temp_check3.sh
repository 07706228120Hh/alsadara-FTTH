#!/bin/bash

echo "=== Check DLL has credit-customers ==="
grep -c "credit-customers" /var/www/sadara-api/Sadara.API.dll || echo "NOT IN DLL"

echo ""
echo "=== Binary search in DLL ==="
xxd /var/www/sadara-api/Sadara.API.dll | grep -i "credit" | head -5

echo ""
echo "=== Check DLL file size and timestamp ==="
ls -la /var/www/sadara-api/Sadara.API.dll

echo ""
echo "=== Check API logs for recent requests ==="
journalctl -u sadara-api --no-pager -n 10 --since "1 min ago"

echo ""
echo "=== Try curl without auth ==="
curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/api/ftth-accounting/credit-customers/81ea550b-aaac-4e5a-a04a-82cd603aff44
echo " (expected 401 if endpoint exists)"

echo ""
echo "=== Check all available endpoints ==="
curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/api/ftth-accounting/operators-dashboard
echo " (operators-dashboard)"
