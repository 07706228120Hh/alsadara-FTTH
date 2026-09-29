#!/usr/bin/env bash
# entrypoint الإنتاج: انتظار Postgres → ترقية المخطط (Alembic) → تشغيل uvicorn.
set -e

echo "[entrypoint] انتظار قاعدة البيانات..."
python - <<'PY'
import os, time, sys
from sqlalchemy import create_engine, text
url = os.environ.get("DATABASE_URL", "")
if url.startswith("sqlite"):
    sys.exit(0)  # لا انتظار في وضع sqlite
for i in range(60):
    try:
        create_engine(url).connect().execute(text("select 1"))
        print("[entrypoint] قاعدة البيانات جاهزة")
        break
    except Exception as e:
        print(f"[entrypoint] ({i+1}/60) بانتظار DB: {e}")
        time.sleep(2)
else:
    print("[entrypoint] تعذّر الاتصال بقاعدة البيانات"); sys.exit(1)
PY

echo "[entrypoint] تطبيق هجرات Alembic..."
# على قاعدة موجودة أُنشئت بـ create_all دون Alembic: stamp مرة واحدة عبر ALEMBIC_STAMP=head
if [ -n "${ALEMBIC_STAMP:-}" ]; then
  alembic stamp "${ALEMBIC_STAMP}" || true
fi
alembic upgrade head

echo "[entrypoint] تشغيل الخادم على 0.0.0.0:${PORT:-8000}"
exec uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-8000}" --workers "${WEB_CONCURRENCY:-2}"
