#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# rotate_jwt_secret.sh
# تدوير سرّ توقيع JWT في الإنتاج — يُغلق نهائياً خطر تزوير توكن SuperAdmin
# (الذي يتجاوز الفلتر المركزي كله).
#
# آمن: لا يحوي أي سرّ. يولّد سرّاً جديداً عشوائياً على خادمك لحظة التشغيل،
#      يأخذ نسخة احتياطية من ملفات الإعداد، يحدّث Jwt:Secret، ثم يعيد التشغيل.
#      لا يطبع قيمة السرّ، ولا يمرّرها عبر argv (تُمرَّر عبر متغيّر بيئة فقط).
#
# الأثر الوحيد: كل التوكنات الحالية تبطل ⇒ الجميع يعيد الدخول مرة واحدة.
#
# fail-safe: يتحقّق أن الخدمة أقلعت (استطلاع حتى ~16ث)؛ وعند فشل الإقلاع
#            يسترجع النسخة الاحتياطية ويعيد التشغيل تلقائياً.
#
# التشغيل (على الخادم، بصلاحية root):  bash rotate_jwt_secret.sh
# التراجع اليدوي: cp <ملف>.bak_<الطابع> <ملف> && sudo systemctl restart sadara-api
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

APP_DIR="${APP_DIR:-/var/www/sadara-api}"
SERVICE="${SERVICE:-sadara-api}"
STAMP="$(date +%F_%H%M%S)"

command -v openssl >/dev/null || { echo "❌ openssl غير متوفّر"; exit 1; }
command -v python3 >/dev/null || { echo "❌ python3 غير متوفّر"; exit 1; }

# سرّ جديد قوي (64 بايت base64 ≈ 88 حرفاً) — يُولَّد الآن، لا يُطبع ولا يُمرَّر عبر argv
export NEW_SECRET="$(openssl rand -base64 64 | tr -d '\n')"

BACKUPS=()
UPDATED=0
for CFG in "$APP_DIR/appsettings.Production.json" "$APP_DIR/appsettings.json"; do
  [ -f "$CFG" ] || continue
  # حدِّث فقط الملفات التي تحوي Jwt.Secret فعلاً
  if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if isinstance(d.get('Jwt'),dict) and d['Jwt'].get('Secret') else 1)" "$CFG" 2>/dev/null; then
    cp -p "$CFG" "$CFG.bak_$STAMP"
    BACKUPS+=("$CFG.bak_$STAMP")
    echo "  📦 نسخة احتياطية: $CFG.bak_$STAMP"
    python3 - "$CFG" <<'PY'
import json, os, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    d = json.load(f)
d.setdefault("Jwt", {})["Secret"] = os.environ["NEW_SECRET"]
with open(path, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
print(f"  ✅ حُدِّث Jwt:Secret في {path} (القيمة غير مطبوعة)")
PY
    UPDATED=1
  fi
done
unset NEW_SECRET

[ "$UPDATED" = "1" ] || { echo "❌ لم أجد أي ملف إعداد به Jwt:Secret في $APP_DIR"; exit 1; }

echo "🔄 إعادة تشغيل الخدمة..."
sudo systemctl restart "$SERVICE"

# تحقّق: استطلاع حتى ~16 ثانية (.NET قد يحتاج بضع ثوانٍ للإقلاع)
active=0
for _ in $(seq 1 8); do
  sleep 2
  if sudo systemctl is-active --quiet "$SERVICE"; then active=1; break; fi
done

if [ "$active" = "1" ]; then
  echo "🟢 $SERVICE يعمل. تمّ تدوير سرّ JWT بنجاح."
  echo "   كل المستخدمين يعيدون الدخول مرة واحدة (طبيعي)."
  echo "   النسخ الاحتياطية: ${BACKUPS[*]}  (نظّفها بعد التأكّد من الاستقرار)"
else
  echo "🔴 الخدمة لم تُقلع بعد التدوير — استرجاع النسخ الاحتياطية تلقائياً..."
  for b in "${BACKUPS[@]}"; do cp -p "$b" "${b%.bak_$STAMP}"; done
  sudo systemctl restart "$SERVICE"; sleep 4
  if sudo systemctl is-active --quiet "$SERVICE"; then
    echo "↩️ استُرجع الإعداد السابق والخدمة تعمل. لم يتغيّر شيء فعلياً."
  else
    echo "⚠️ الخدمة ما زالت متوقّفة — تدخّل يدوي: journalctl -u $SERVICE -n 50"
  fi
  exit 1
fi
