#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# فحص دخان وظيفي لعزل الشركات على نسخة staging معزولة — لا يمسّ الإنتاج.
#
# يُنشئ قاعدة scratch (sadara_staging) من نسخة احتياطية حقيقية، يطبّق الهجرات
# والـ backfill، يشغّل الـ API المُصلَح على منفذ 5001، ثم يختبر:
#   (أ) POST /api/employee-location بمفتاح API على UserId موجود ⇒ يجب 200 (لا 500).
#   (ب) GET صحّة الخدمة.
# اختبار الدخول عبر HTTP يجريه المشغّل يدوياً بحسابه (انظر نهاية المخرجات).
#
# الأمان:
#   • لا يلمس sadara_db (الإنتاج) ولا الخدمة على المنفذ 5000 إطلاقاً.
#   • يرفض العمل إن كان اسم قاعدة staging = قاعدة الإنتاج.
#   • لا يطبع أي سرّ؛ يقرأ المفتاح الداخلي من متغيّر البيئة SADARA_INTERNAL_API_KEY.
#   • للتنظيف بعد الفحص: STAGING_TEARDOWN=1 (يوقف العملية ويُسقط sadara_staging فقط).
#
# التشغيل (على الخادم، مثال):
#   export SADARA_INTERNAL_API_KEY='<المفتاح-الداخلي-الإنتاجي>'
#   bash staging_smoke_test.sh \
#       --dump   /root/backups/sadara_db_<الأحدث>.dump \
#       --dll    /root/staging/Sadara.API.dll \
#       --migrations ./migrations.sql \
#       --backfill   ./backfill_company_id.sql
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── إعدادات افتراضية (قابلة للتجاوز عبر البيئة) ──────────────────────────────
PROD_DB="${PROD_DB:-sadara_db}"                 # حارس: لن نلمسها أبداً
STAGING_DB="${STAGING_DB:-sadara_staging}"
STAGING_PORT="${STAGING_PORT:-5001}"
DB_USER="${DB_USER:-sadara_user}"
PG_SUPER="${PG_SUPER:-postgres}"                 # مستخدم postgres الإداري
HOST="127.0.0.1"

DUMP=""; DLL=""; MIGRATIONS=""; BACKFILL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dump)       DUMP="$2"; shift 2;;
    --dll)        DLL="$2"; shift 2;;
    --migrations) MIGRATIONS="$2"; shift 2;;
    --backfill)   BACKFILL="$2"; shift 2;;
    *) echo "وسيط غير معروف: $1" >&2; exit 2;;
  esac
done

# ── فحوصات سلامة قبل أي عمل ──────────────────────────────────────────────────
if [[ "$STAGING_DB" == "$PROD_DB" ]]; then
  echo "🔴 رفض: STAGING_DB يساوي قاعدة الإنتاج ($PROD_DB). أوقفت التنفيذ." >&2; exit 1
fi
if [[ "$STAGING_PORT" == "5000" ]]; then
  echo "🔴 رفض: منفذ staging = 5000 (الإنتاج الحيّ). أوقفت التنفيذ." >&2; exit 1
fi
[[ -z "$DUMP" || ! -f "$DUMP" ]] && { echo "🔴 --dump مطلوب وملف موجود." >&2; exit 1; }
[[ -z "$DLL"  || ! -f "$DLL"  ]] && { echo "🔴 --dll مطلوب (Sadara.API.dll المُصلَح)." >&2; exit 1; }
[[ -z "${SADARA_INTERNAL_API_KEY:-}" ]] && { echo "🔴 صدّر SADARA_INTERNAL_API_KEY أولاً." >&2; exit 1; }

echo "═══ staging: DB=$STAGING_DB  PORT=$STAGING_PORT  (الإنتاج $PROD_DB/5000 لن يُمسّ) ═══"

psql_super() { sudo -u "$PG_SUPER" psql -v ON_ERROR_STOP=1 "$@"; }

# ── 1) استعادة قاعدة scratch من النسخة الاحتياطية ────────────────────────────
echo "── 1/5 استعادة $STAGING_DB من: $DUMP"
psql_super -d postgres -c "DROP DATABASE IF EXISTS ${STAGING_DB};"
psql_super -d postgres -c "CREATE DATABASE ${STAGING_DB} OWNER ${DB_USER};"
sudo -u "$PG_SUPER" pg_restore --no-owner --role="${DB_USER}" -d "${STAGING_DB}" "$DUMP" || true
ROWS_BEFORE=$(psql_super -tA -d "$STAGING_DB" -c "SELECT count(*) FROM \"EmployeeLocations\";")
echo "   صفوف EmployeeLocations قبل: $ROWS_BEFORE"

# ── 2) الهجرات + backfill (كما سيجري على الإنتاج) ────────────────────────────
if [[ -n "$MIGRATIONS" && -f "$MIGRATIONS" ]]; then
  echo "── 2a تطبيق الهجرات على $STAGING_DB"
  psql_super -d "$STAGING_DB" -f "$MIGRATIONS"
fi
if [[ -n "$BACKFILL" && -f "$BACKFILL" ]]; then
  echo "── 2b تطبيق backfill على $STAGING_DB"
  psql_super -d "$STAGING_DB" -f "$BACKFILL"
fi

# ── 3) تشغيل الـ API المُصلَح على 5001 مقابل قاعدة staging ────────────────────
echo "── 3/5 تشغيل الـ API على :$STAGING_PORT"
STAGING_CONN="Host=localhost;Port=5432;Database=${STAGING_DB};Username=${DB_USER};Password=${DB_PASSWORD:-sadara_secure_password_2024}"
DLL_DIR="$(dirname "$DLL")"
LOG="$(mktemp /tmp/sadara_staging_XXXX.log)"
# طريقة الإطلاق: نشر مُعتمِد على الرنتايم (dotnet X.dll) أو ذاتي-الاحتواء (./X).
# تجاوزها عند اللزوم: export LAUNCH_CMD='./Sadara.API'
SELF_CONTAINED="${DLL%.dll}"
if [[ -z "${LAUNCH_CMD:-}" ]]; then
  if [[ -x "$SELF_CONTAINED" && ! "$SELF_CONTAINED" == "$DLL" ]]; then
    LAUNCH_CMD="$SELF_CONTAINED"
  else
    LAUNCH_CMD="dotnet $DLL"
  fi
fi
echo "   أمر الإطلاق: $LAUNCH_CMD"
(
  cd "$DLL_DIR"
  ASPNETCORE_ENVIRONMENT=Staging \
  ASPNETCORE_URLS="http://${HOST}:${STAGING_PORT}" \
  ConnectionStrings__DefaultConnection="$STAGING_CONN" \
  Security__InternalApiKey="$SADARA_INTERNAL_API_KEY" \
  $LAUNCH_CMD >"$LOG" 2>&1
) &
API_PID=$!
cleanup() {
  echo "── إيقاف API staging (PID $API_PID)"; kill "$API_PID" 2>/dev/null || true; wait "$API_PID" 2>/dev/null || true
  if [[ "${STAGING_TEARDOWN:-0}" == "1" ]]; then
    echo "── إسقاط $STAGING_DB (STAGING_TEARDOWN=1)"
    psql_super -d postgres -c "DROP DATABASE IF EXISTS ${STAGING_DB};" || true
  else
    echo "── تُركت $STAGING_DB قائمة للفحص اليدوي (صدّر STAGING_TEARDOWN=1 للحذف)."
  fi
}
trap cleanup EXIT

echo "   انتظار بدء الخدمة…"
for i in $(seq 1 30); do
  if curl -fsS "http://${HOST}:${STAGING_PORT}/" >/dev/null 2>&1 \
     || curl -fsS "http://${HOST}:${STAGING_PORT}/health" >/dev/null 2>&1; then break; fi
  sleep 1
done
if ! kill -0 "$API_PID" 2>/dev/null; then
  echo "🔴 فشل بدء الـ API. آخر السجل:"; tail -30 "$LOG"; exit 1
fi

# ── 4) اختبار upsert بمفتاح API على UserId موجود ─────────────────────────────
echo "── 4/5 اختبار POST /api/employee-location (مفتاح API) على صفٍّ موجود"
EXISTING_UID=$(psql_super -tA -d "$STAGING_DB" -c "SELECT \"UserId\" FROM \"EmployeeLocations\" ORDER BY \"UpdatedAt\" DESC NULLS LAST LIMIT 1;" | tr -d '[:space:]')
if [[ -z "$EXISTING_UID" ]]; then
  echo "🟡 لا يوجد صفّ EmployeeLocations في النسخة — سأختبر بإدراج جديد ثم إعادة إرسال."
  EXISTING_UID="smoke-$(date +%s)"
fi
echo "   UserId قيد الاختبار: $EXISTING_UID"

BODY=$(printf '{"userId":"%s","latitude":33.3152,"longitude":44.3661,"department":"smoke","center":"smoke"}' "$EXISTING_UID")
do_post() {
  curl -s -o /tmp/sadara_resp.json -w '%{http_code}' \
    -X POST "http://${HOST}:${STAGING_PORT}/api/employee-location" \
    -H "Content-Type: application/json" \
    -H "X-Api-Key: ${SADARA_INTERNAL_API_KEY}" \
    --data "$BODY"
}
CODE1=$(do_post); echo "   محاولة 1 (تحديث/إدراج): HTTP $CODE1"
CODE2=$(do_post); echo "   محاولة 2 (يجب أن تكون upsert على نفس الصف): HTTP $CODE2"

ROWS_AFTER=$(psql_super -tA -d "$STAGING_DB" -c "SELECT count(*) FROM \"EmployeeLocations\" WHERE \"UserId\"='${EXISTING_UID}';")
echo "   عدد صفوف هذا الـ UserId بعد محاولتين: $ROWS_AFTER (يجب = 1، لا تكرار ولا 500)"

# ── 5) الحكم ─────────────────────────────────────────────────────────────────
echo "── 5/5 النتيجة"
PASS=1
[[ "$CODE1" == "200" || "$CODE1" == "201" ]] || { echo "   🔴 المحاولة 1 ليست 200/201"; PASS=0; }
[[ "$CODE2" == "200" || "$CODE2" == "201" ]] || { echo "   🔴 المحاولة 2 ليست 200/201 (هي حالة العطل السابقة)"; PASS=0; }
[[ "$ROWS_AFTER" == "1" ]] || { echo "   🔴 عدد الصفوف ليس 1 (تكرار = عودة العطل)"; PASS=0; }

echo
if [[ "$PASS" == "1" ]]; then
  echo "🟢 نجح فحص الدخان الوظيفي لـ employee-location تحت الفلتر النشط."
else
  echo "🔴 فشل الفحص — لا تنشر. آخر سجل الخدمة:"; tail -40 "$LOG"
fi

cat <<EOF

──────────────────────────────────────────────────────────────────────────────
اختبار الدخول الحقيقي (تُجريه أنت — لا يمرّ عبر السكربت ولا يُخزَّن أي سرّ):
  curl -s -X POST "http://${HOST}:${STAGING_PORT}/api/companies/login" \\
    -H "Content-Type: application/json" \\
    -d '{"companyCode":"<كود-شركتك>","username":"<اسم-المستخدم>","password":"<كلمة-المرور>"}'
  # المتوقّع: success=true وتوكن — إثبات أن الدخول يعمل والفلتر نشط.

سجلّ خدمة staging الكامل: $LOG
للتنظيف الكامل بعد رضاك: STAGING_TEARDOWN=1 أعد تشغيل السكربت، أو يدوياً:
  sudo -u ${PG_SUPER} psql -c "DROP DATABASE IF EXISTS ${STAGING_DB};"
──────────────────────────────────────────────────────────────────────────────
EOF

[[ "$PASS" == "1" ]] || exit 1
