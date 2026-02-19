#!/bin/bash
systemctl stop sadara-api
cd /var/www/sadara-api
# حفظ الملفات المهمة
cp appsettings.json /tmp/appsettings_bak.json
cp appsettings.Production.json /tmp/appsettings_prod_bak.json 2>/dev/null
# فك الضغط مع استبعاد الإعدادات
unzip -o /tmp/publish.zip -x 'appsettings*' 'secrets/*' 'web.config' > /dev/null 2>&1
systemctl start sadara-api
sleep 4
STATUS=$(systemctl is-active sadara-api)
echo "API Status: $STATUS"
if [ "$STATUS" = "active" ]; then
    CODE=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:5000/api/agents)
    echo "GET /api/agents: $CODE"
    CODE2=$(curl -s -o /dev/null -w '%{http_code}' -X PUT http://localhost:5000/api/agents/transactions/1)
    echo "PUT /api/agents/transactions/1: $CODE2"
    CODE3=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE http://localhost:5000/api/agents/transactions/1)
    echo "DELETE /api/agents/transactions/1: $CODE3"
fi
