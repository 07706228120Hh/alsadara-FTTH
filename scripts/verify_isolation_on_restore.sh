#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# verify_isolation_on_restore.sh
# البوابة الحاسمة قبل الإنتاج: يختبر (migration + backfill) على نسخة مستعادة
# من إنتاج رمز الصدارة، على قاعدة scratch منفصلة — لا يمسّ قاعدة الإنتاج sadara_db.
#
# يؤكّد:
#   ✅ لا فقدان بيانات: عدد صفوف كل جدول (قبل) = (بعد).
#   ✅ لا يبقى CompanyId فارغ/صفري بعد backfill (عدا PermissionTemplates).
#
# الاستخدام (على الخادم، بصلاحية root):
#   1) ولّد سكربت الهجرات على جهازك:
#        dotnet ef migrations script --idempotent -o migrations.sql \
#          --project src\Backend\Core\Sadara.Infrastructure --startup-project src\Backend\API\Sadara.API
#   2) انسخ migrations.sql إلى الخادم بجانب هذا السكربت و backfill_company_id.sql.
#   3) شغّل:
#        bash verify_isolation_on_restore.sh /root/backups/sadara_db_XXXX.dump ./migrations.sql
#
# لا حذف لأي شيء في الإنتاج. القاعدة scratch تُحذف تلقائياً في النهاية.
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

DUMP="${1:?الاستخدام: verify_isolation_on_restore.sh <path-to.dump> <path-to-migrations.sql>}"
MIGRATION_SQL="${2:?يلزم مسار migrations.sql (dotnet ef migrations script --idempotent)}"
HERE="$(cd "$(dirname "$0")" && pwd)"
BACKFILL="$HERE/backfill_company_id.sql"
SCRATCH="sadara_db_verify"
PSQL="sudo -u postgres psql -v ON_ERROR_STOP=1"

[ -f "$DUMP" ]         || { echo "❌ ملف النسخة غير موجود: $DUMP"; exit 1; }
[ -f "$MIGRATION_SQL" ]|| { echo "❌ ملف الهجرات غير موجود: $MIGRATION_SQL"; exit 1; }
[ -f "$BACKFILL" ]     || { echo "❌ backfill_company_id.sql غير موجود بجانب السكربت"; exit 1; }

count_all_tables () {
  sudo -u postgres psql -tAq -d "$SCRATCH" -c \
    "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename;" |
  while read -r t; do
    [ -z "$t" ] && continue
    c=$(sudo -u postgres psql -tAq -d "$SCRATCH" -c "SELECT COUNT(*) FROM \"$t\";")
    printf '%s=%s\n' "$t" "$c"
  done
}

echo "═══ [1/6] إنشاء قاعدة scratch: $SCRATCH ═══"
sudo -u postgres psql -c "DROP DATABASE IF EXISTS $SCRATCH;"
sudo -u postgres psql -c "CREATE DATABASE $SCRATCH OWNER sadara_user;"

echo "═══ [2/6] استعادة نسخة الإنتاج (تحذيرات pg_restore غير القاتلة طبيعية) ═══"
sudo -u postgres pg_restore --no-owner --role=sadara_user -d "$SCRATCH" "$DUMP" || true

echo "═══ [3/6] عدّ صفوف كل الجداول (قبل) ═══"
count_all_tables > /tmp/verify_before.txt
wc -l < /tmp/verify_before.txt | xargs echo "  عدد الجداول:"

echo "═══ [4/6] تطبيق migration ثم backfill ═══"
$PSQL -d "$SCRATCH" -f "$MIGRATION_SQL"
$PSQL -d "$SCRATCH" -f "$BACKFILL"

echo "═══ [5/6] عدّ صفوف كل الجداول (بعد) + مقارنة ═══"
count_all_tables > /tmp/verify_after.txt
if diff -u /tmp/verify_before.txt /tmp/verify_after.txt > /tmp/verify_diff.txt; then
  echo "  ✅ أعداد الصفوف متطابقة قبل=بعد — لا فقدان بيانات."
  ROWS_OK=1
else
  echo "  ❌ اختلاف في أعداد الصفوف:"; cat /tmp/verify_diff.txt
  ROWS_OK=0
fi

echo "═══ [6/6] فحص بقاء CompanyId فارغ/صفري بعد backfill (يجب 0) ═══"
NULLS=0
for t in $(sudo -u postgres psql -tAq -d "$SCRATCH" -c \
    "SELECT table_name FROM information_schema.columns
     WHERE table_schema='public' AND column_name='CompanyId' AND data_type='uuid'
       AND table_name <> 'PermissionTemplates' ORDER BY table_name;"); do
  n=$(sudo -u postgres psql -tAq -d "$SCRATCH" -c \
    "SELECT COUNT(*) FROM \"$t\" WHERE \"CompanyId\" IS NULL OR \"CompanyId\"='00000000-0000-0000-0000-000000000000';")
  if [ "$n" != "0" ]; then echo "  ⚠️ $t لا يزال به $n صف بشركة فارغة"; NULLS=$((NULLS+n)); fi
done
[ "$NULLS" = "0" ] && echo "  ✅ لا صفوف بشركة فارغة بعد backfill."

echo "═══ تنظيف: حذف قاعدة scratch ═══"
sudo -u postgres psql -c "DROP DATABASE IF EXISTS $SCRATCH;"

echo ""
if [ "$ROWS_OK" = "1" ] && [ "$NULLS" = "0" ]; then
  echo "🟢 النتيجة: التحقّق ناجح — آمن للانتقال لمرحلة النشر المتحكَّم (بموافقة + نسخة احتياطية)."
  exit 0
else
  echo "🔴 النتيجة: التحقّق فشل — لا تنشر. راجع المخرجات أعلاه."
  exit 1
fi
