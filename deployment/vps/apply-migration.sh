#!/bin/bash
# سكربت تطبيق Migration على VPS
# يجب تشغيله على السيرفر مباشرة

echo "🔄 تطبيق Migration - AddSubscriptionLogs"
echo "========================================"

# الانتقال لمجلد المشروع
cd /var/www/sadara-api || exit 1

# تطبيق الـ Migration
echo "📦 تحديث قاعدة البيانات..."
dotnet ef database update --connection "Host=localhost;Port=5432;Database=sadara_db;Username=sadara_user;Password=sadara_secure_password_2024"

if [ $? -eq 0 ]; then
    echo "✅ تم تطبيق Migration بنجاح!"
    echo ""
    echo "📋 الجدول الجديد: SubscriptionLogs"
    echo "🔗 API Endpoint: POST /api/subscriptionlogs"
else
    echo "❌ فشل تطبيق Migration"
    exit 1
fi

# إعادة تشغيل الخدمة
echo ""
echo "🔄 إعادة تشغيل الـ API..."
sudo systemctl restart sadara-api

echo "✅ تم بنجاح!"
