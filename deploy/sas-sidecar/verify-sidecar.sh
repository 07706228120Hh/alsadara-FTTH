#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# verify-sidecar.sh — فحص تشغيلي للقراءة فقط لخدمة الساز (SAS sidecar)
#
# يجيب على: هل الـsidecar مُشغَّل ومُفعَّل كـsystemd؟ هل المنفذ 8100 يستمع؟
# هل صحّته 200؟ هل السرّ الداخلي مضبوط؟ هل النسخ الاحتياطي يغطّي sas.db؟
#
# لا يغيّر شيئاً ولا يطبع أي سرّ. يُشغَّل على الخادم نفسه:
#   bash verify-sidecar.sh
# أو عن بُعد:
#   ssh root@72.61.183.61 'bash -s' < deploy/sas-sidecar/verify-sidecar.sh
# ══════════════════════════════════════════════════════════════════════════════
set -u

# القيم الافتراضية مطابقة لبنية الإنتاج الفعلية (مُتحقَّقة 2026-11-27).
SVC="${SAS_SERVICE_NAME:-sadara-sas-sidecar}"
PORT="${SAS_PORT:-8100}"
SAS_DIR="${SAS_DIR:-/opt/sadara/sas/service}"   # app.py + data/sas.db هنا
ENV_FILE="${SAS_ENV_FILE:-/etc/sadara/sas-sidecar.env}"
BACKUP_DIR="${BACKUP_DIR:-/root/backups}"

echo "════════ فحص خدمة الساز (قراءة فقط) ════════"

echo "── 1) خدمات systemd ذات صلة ──"
systemctl list-units --type=service --all 2>/dev/null | grep -iE "sas|sadara" || echo "  (لا شيء)"

echo "── 2) حالة الخدمة: $SVC ──"
echo "   active : $(systemctl is-active  "$SVC" 2>/dev/null || echo unknown)"
echo "   enabled: $(systemctl is-enabled "$SVC" 2>/dev/null || echo unknown)   # يجب أن يكون enabled ليقلع تلقائياً بعد reboot"

echo "── 3) هل المنفذ $PORT يستمع (على 127.0.0.1 فقط)؟ ──"
ss -ltnp 2>/dev/null | grep -E ":$PORT" || echo "  (غير مستمع — الخدمة متوقّفة؟)"

echo "── 4) صحّة الـsidecar (محلي) ──"
curl -s -m 8 -o /dev/null -w "   127.0.0.1:$PORT/health -> HTTP %{http_code}\n" "http://127.0.0.1:$PORT/health" \
  || echo "   (تعذّر الاتصال بـ$PORT)"

echo "── 5) صحّة الباكند ──"
curl -s -m 8 -o /dev/null -w "   127.0.0.1:5000/health -> HTTP %{http_code}\n" "http://127.0.0.1:5000/health" \
  || echo "   (تعذّر الاتصال بالباكند)"

echo "── 6) السرّ الداخلي مضبوط؟ (دون طباعة قيمته) ──"
if [ -f "$ENV_FILE" ]; then
  grep -q '^SADARA_SAS_INTERNAL_SECRET=.\+' "$ENV_FILE" \
    && echo "   $ENV_FILE: SADARA_SAS_INTERNAL_SECRET = set ✓" \
    || echo "   $ENV_FILE: SADARA_SAS_INTERNAL_SECRET = MISSING ✗ (fail-closed ⇒ كل الطلبات 503)"
else
  echo "   $ENV_FILE غير موجود"
fi

echo "── 7) تغطية النسخ الاحتياطي لـsas.db ──"
if [ -f "$SAS_DIR/data/sas.db" ]; then
  echo "   قاعدة الساز: $SAS_DIR/data/sas.db ($(du -h "$SAS_DIR/data/sas.db" 2>/dev/null | cut -f1))"
else
  echo "   لم أجد $SAS_DIR/data/sas.db — تحقّق من المسار الفعلي:"
  find /srv /opt /root /var/www -name sas.db 2>/dev/null | head
fi
echo "   آخر نسخ احتياطية:"
ls -lt "$BACKUP_DIR" 2>/dev/null | grep -iE "sas" | head -3 || echo "   (لا نسخ تحوي sas في $BACKUP_DIR — شغّل deploy/backup.sh مع SAS_DIR مضبوطاً)"

echo "════════ انتهى الفحص ════════"
