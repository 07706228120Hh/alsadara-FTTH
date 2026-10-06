#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
#  نشر باكند الصدارة بأمان — يمنع عدم تطابق DLL ويتحقّق بصرامة بعد النشر.
#  الاستخدام (من جذر المستودع، Git Bash):  bash deploy/deploy-backend.sh
#
#  يطبّق الدروس المكتسبة تلقائياً كي لا تتكرّر أعطال النشر:
#   1) يُغلق الباكند المحلي (يحرّر قفل البناء).
#   2) يبني Release كاملاً.
#   3) يولّد سكربت هجرات idempotent (يطبّق الناقص فقط).
#   4) نسخة احتياطية (قاعدة + كل DLLs الحالية) قبل أي تغيير.
#   5) يطبّق الهجرات **قبل** الـDLL (وإلا أعمدة جديدة = 500).
#   6) ينشر **كل *.dll** (لا أربعة فقط ولا واحد) ⇒ يستحيل عدم التطابق.
#   7) إعادة تشغيل + تحقّق صارم: active + /health=200 + **صفر** أخطاء في السجل
#      (MissingMethod / Unhandled exception / responded 500). يفشل بصوت عالٍ وإلا.
#
#  التراجع عند الفشل: الـDLLs الحالية محفوظة في /root/backups/dll_<TS> على الخادم.
# ════════════════════════════════════════════════════════════════════════════
set -euo pipefail

SERVER="${SADARA_SERVER:-root@72.61.183.61}"
APP_DIR="/var/www/sadara-api"
API_PROJ="src/Backend/API/Sadara.API/Sadara.API.csproj"
INFRA_PROJ="src/Backend/Core/Sadara.Infrastructure/Sadara.Infrastructure.csproj"
PUB="src/Backend/API/Sadara.API/publish_temp"
TS="$(date +%Y%m%d_%H%M%S)"

echo "════════ نشر باكند الصدارة — $TS ════════"

echo "==> 0) إغلاق الباكند المحلي (تحرير قفل البناء)"
taskkill //F //IM Sadara.API.exe >/dev/null 2>&1 || true

echo "==> 1) بناء Release"
rm -rf "$PUB"
dotnet publish "$API_PROJ" -c Release -o "$PUB" --nologo 2>&1 | tail -2
test -f "$PUB/Sadara.API.dll" || { echo "❌ البناء فشل"; exit 1; }

echo "==> 2) توليد سكربت الهجرات (idempotent)"
dotnet ef migrations script --idempotent \
  --project "$INFRA_PROJ" --startup-project "$API_PROJ" \
  -o /tmp/sadara_migrations_$TS.sql 2>&1 | tail -2
test -s "/tmp/sadara_migrations_$TS.sql" || { echo "❌ تعذّر توليد سكربت الهجرات"; exit 1; }
# فحص أمان: لا عمليات هدّامة غير متوقّعة (DROP TABLE)
if grep -qiE "DROP TABLE" "/tmp/sadara_migrations_$TS.sql"; then
  echo "⚠️  السكربت يحوي DROP TABLE — توقّف وراجع يدوياً"; exit 1
fi

echo "==> 3) نسخة احتياطية على الخادم (قاعدة + كل DLLs)"
ssh "$SERVER" "mkdir -p /root/backups/dll_$TS && cp $APP_DIR/*.dll /root/backups/dll_$TS/ && sudo -u postgres pg_dump sadara_db | gzip > /root/backups/db_$TS.sql.gz && echo '   backup: /root/backups/{dll_$TS, db_$TS.sql.gz}'"

echo "==> 4) تطبيق الهجرات (قبل الـDLL)"
scp "/tmp/sadara_migrations_$TS.sql" "$SERVER:/root/backups/" >/dev/null
ssh "$SERVER" "cat /root/backups/sadara_migrations_$TS.sql | sudo -u postgres psql -d sadara_db -v ON_ERROR_STOP=1 -q && echo '   migrations ✓'"

echo "==> 5) نشر كل DLLs (يمنع عدم التطابق)"
scp "$PUB"/*.dll "$SERVER:$APP_DIR/" >/dev/null
echo "   نُشر $(ls "$PUB"/*.dll | wc -l) ملف DLL"

echo "==> 6) إعادة التشغيل + تحقّق صارم (انتظار إقلاع EF ~30s)"
ssh "$SERVER" '
systemctl restart sadara-api
sleep 32
act=$(systemctl is-active sadara-api)
nr=$(systemctl show sadara-api -p NRestarts --value)
hc=$(curl -s -o /dev/null -w "%{http_code}" -m 10 http://localhost:5000/health)
errs=$(journalctl -u sadara-api --no-pager --since "45 seconds ago" | grep -ciE "MissingMethodException|Unhandled exception|responded 500|BadImageFormat")
echo "   active=$act  NRestarts=$nr  health=$hc  logErrors=$errs"
if [ "$act" = "active" ] && [ "$hc" = "200" ] && [ "$errs" = "0" ]; then
  echo "   ✅ النشر ناجح وسليم — صفر أخطاء في السجل"
else
  echo "   ❌ فشل التحقّق — تراجع: cp /root/backups/dll_'"$TS"'/*.dll '"$APP_DIR"'/ && systemctl restart sadara-api"
  exit 1
fi
'
echo "════════ انتهى النشر بنجاح — $TS ════════"
