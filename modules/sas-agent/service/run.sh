#!/usr/bin/env bash
# run.sh -- تشغيل SAS Sidecar على 127.0.0.1:8100 (Linux/macOS)
#
# متطلّبات:
#   1. Python 3.11+ في PATH
#   2. pip install -r requirements.txt  (من مجلد service/)
#   3. تعيين متغيّر البيئة SADARA_SAS_INTERNAL_SECRET قبل التشغيل:
#         export SADARA_SAS_INTERNAL_SECRET="your-secret-here"
#
# fail-closed: الخدمة ترفض كل الطلبات إن لم يُضبط SADARA_SAS_INTERNAL_SECRET.

set -euo pipefail

cd "$(dirname "$0")"

if [[ -z "${SADARA_SAS_INTERNAL_SECRET:-}" ]]; then
    echo "[ERROR] SADARA_SAS_INTERNAL_SECRET is not set." >&2
    echo "        The sidecar will start but reject ALL requests (fail-closed)." >&2
    echo "        Set the variable before running in production." >&2
fi

exec python -m uvicorn app:app \
    --host 127.0.0.1 \
    --port 8100 \
    --log-level info
