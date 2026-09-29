# باكند منصة العراق الرقمية — صورة إنتاجية
# البناء من جذر المشروع:  docker build -f backend/Dockerfile -t idp-backend ./backend
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# اعتمادات النظام (cryptography/psycopg تحتاج أدوات بناء بسيطة + عميل postgres)
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential libpq5 curl \
    && rm -rf /var/lib/apt/lists/*

# طبقة الاعتمادات أولاً (كاش أفضل)
COPY requirements.txt .
RUN pip install -r requirements.txt

# كود التطبيق + الهجرات + المعرفة
COPY . .

# صلاحية تنفيذ للـ entrypoint (تُفقد عند النسخ من ويندوز)
RUN chmod +x docker-entrypoint.sh

# مستخدم غير جذر
RUN useradd -m appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

# entrypoint: ينتظر قاعدة البيانات، يطبّق الهجرات، ثم يشغّل الخادم
ENTRYPOINT ["./docker-entrypoint.sh"]
