# VPS Deployment Guide for Sadara Platform

## معلومات السيرفر
- **IP:** 72.61.183.61
- **Provider:** Hostinger
- **OS:** Ubuntu 24.04

## المكونات المثبتة
- ✅ .NET 9 Runtime
- ✅ PostgreSQL 16
- ✅ Nginx (Reverse Proxy)
- ✅ SSL (Self-signed)

## بيانات الوصول

### SSH
```bash
ssh root@72.61.183.61
```

### PostgreSQL
```
Host: localhost
Port: 5432
Database: sadara_db
User: sadara_user
Password: sadara_secure_password_2024
```

### API
- **HTTP:** http://72.61.183.61/
- **HTTPS:** https://72.61.183.61/
- **Swagger:** https://72.61.183.61/

### Super Admin
```
Phone: 9647700000001
Password: Admin@123!
```

## مسارات الملفات على السيرفر

```
/var/www/sadara-api/          # ملفات API
/var/log/sadara-api/          # سجلات API
/etc/nginx/sites-available/   # تكوين Nginx
/etc/systemd/system/          # خدمات systemd
```

## أوامر مفيدة

### إعادة تشغيل API
```bash
sudo systemctl restart sadara-api
```

### فحص حالة API
```bash
sudo systemctl status sadara-api
```

### عرض السجلات
```bash
sudo journalctl -u sadara-api -f
```

### إعادة تشغيل Nginx
```bash
sudo systemctl reload nginx
```

### الاتصال بقاعدة البيانات
```bash
sudo -u postgres psql -d sadara_db
```

## النشر

### من Windows (PowerShell)
```powershell
.\deploy-windows.ps1
```

### أو يدوياً
```powershell
# 1. Build
dotnet publish -c Release -o publish

# 2. Upload
scp -r publish/* root@72.61.183.61:/var/www/sadara-api/

# 3. Restart
ssh root@72.61.183.61 "systemctl restart sadara-api"
```

## النسخ الاحتياطي

### قاعدة البيانات
```bash
pg_dump -U sadara_user -d sadara_db > backup_$(date +%Y%m%d).sql
```

### استعادة
```bash
psql -U sadara_user -d sadara_db < backup.sql
```

## إضافة Domain

### 1. تحديث DNS
أضف A Record يشير لـ 72.61.183.61

### 2. تحديث Nginx
```bash
sudo nano /etc/nginx/sites-available/sadara-api
# غيّر server_name إلى اسم الدومين
```

### 3. الحصول على SSL
```bash
sudo certbot --nginx -d yourdomain.com
```

## استكشاف الأخطاء

### API لا يعمل
```bash
# فحص السجلات
journalctl -u sadara-api --no-pager -n 50

# فحص المنفذ
ss -tlnp | grep 5000
```

### مشاكل قاعدة البيانات
```bash
# فحص اتصال PostgreSQL
sudo -u postgres psql -c "SELECT 1"

# فحص صلاحيات المستخدم
sudo -u postgres psql -c "\du sadara_user"
```

### مشاكل Nginx
```bash
# اختبار التكوين
sudo nginx -t

# فحص السجلات
sudo tail -f /var/log/nginx/error.log
```
