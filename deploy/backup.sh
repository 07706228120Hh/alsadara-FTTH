#!/usr/bin/env bash
# نسخة احتياطية كاملة قبل أي تغيير إنتاجي — شغّلها على الخادم الذي يحوي القاعدة/الخدمات.
# الاستخدام:  PGHOST=127.0.0.1 PGPORT=5432 PGDB=SadaraDb PGUSER=... PGPASSWORD=... \
#            APP_DIR=/srv/sadara  DP_KEYS_PATH=/srv/sadara/keys  SAS_DIR=/srv/sas-service \
#            bash backup.sh
set -euo pipefail

TS="$(date +%Y%m%d_%H%M%S)"
OUT="${BACKUP_ROOT:-$HOME/sadara_backups}/backup_$TS"
mkdir -p "$OUT"
echo "📦 وجهة النسخة: $OUT"

# 1) قاعدة البيانات (صيغة مضغوطة قابلة للاستعادة الانتقائية)
: "${PGDB:?اضبط PGDB}" "${PGUSER:?اضبط PGUSER}"
PGHOST="${PGHOST:-127.0.0.1}"; PGPORT="${PGPORT:-5432}"
echo "🗄️  pg_dump $PGDB ..."
pg_dump -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -Fc "$PGDB" > "$OUT/db.dump"

# 2) الإعدادات/الأسرار/المفاتيح/SQLite الساس (إن وُجدت)
for p in "${APP_DIR:-}/.env" "${APP_DIR:-}/appsettings.Production.json" \
         "${DP_KEYS_PATH:-}" "${SAS_DIR:-}/data/sas.db" "${SAS_DIR:-}/.env"; do
  [ -n "$p" ] && [ -e "$p" ] && cp -r "$p" "$OUT/" 2>/dev/null && echo "  + $p"
done

# 3) تحقّق
SZ=$(du -h "$OUT/db.dump" | cut -f1)
echo "✅ db.dump = $SZ"
[ -s "$OUT/db.dump" ] || { echo "❌ db.dump فارغ — أوقف العملية!"; exit 1; }
echo "✅ النسخة جاهزة: $OUT"
echo "↩️  للاستعادة:  pg_restore -c -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDB \"$OUT/db.dump\""
