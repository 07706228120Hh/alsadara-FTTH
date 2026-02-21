#!/bin/bash
echo "=== Deployed DLL timestamp ==="
ls -la /var/www/sadara-api/Sadara.API.dll

echo ""
echo "=== Check if credit-customers route exists in deployed DLL ==="
strings /var/www/sadara-api/Sadara.API.dll 2>/dev/null | grep -i "credit-customers" || echo "NOT FOUND in DLL!"

echo ""
echo "=== Check ToUpper in DLL ==="
strings /var/www/sadara-api/Sadara.API.dll 2>/dev/null | grep -i "ToUpper" | head -5 || echo "NOT FOUND"

echo ""
echo "=== Check publish-temp on server ==="
ls -la /tmp/sadara-deploy/publish-temp/Sadara.API.dll 2>/dev/null || echo "No publish-temp found"
ls -la /var/www/sadara-api/Sadara.API.dll
