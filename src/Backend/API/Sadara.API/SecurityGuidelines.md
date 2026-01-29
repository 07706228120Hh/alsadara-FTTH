# 🔐 إرشادات أمان API - Sadara Platform

## التحذيرات الأمنية ⚠️

### 1. لا ترفع هذه الملفات أبداً للـ Git
```
appsettings.Development.json   # يحتوي على Connection Strings
appsettings.Production.json    # يحتوي على Production secrets
secrets/                        # مجلد المفاتيح السرية
*.pem                          # شهادات SSL
*.key                          # مفاتيح التشفير
```

### 2. كلمات المرور الافتراضية (تغييرها فوراً)
| المستخدم | اسم المستخدم | كلمة المرور |
|----------|-------------|-------------|
| Super Admin | admin | admin123 ❌ |
| VPS SSH | root | CHANGE_THIS ❌ |
| PostgreSQL | postgres | CHANGE_THIS ❌ |

---

## تحسينات الأمان المطلوبة

### 1. تغيير كلمات المرور الافتراضية
```bash
# تغيير كلمة مرور PostgreSQL
sudo -u postgres psql
ALTER USER postgres WITH PASSWORD 'YourStrongPassword123!';

# تغيير كلمة مرور VPS SSH
sudo passwd root
```

### 2. تفعيل HTTPS
```bash
# تثبيت Let's Encrypt
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d your-domain.com
```

### 3. إعداد Environment Variables
```csharp
// في Program.cs
builder.Configuration.AddEnvironmentVariables();

// في appsettings.json
{
  "ConnectionStrings": {
    "DefaultConnection": "${POSTGRES_CONNECTION_STRING}"
  },
  "Jwt": {
    "SecretKey": "${JWT_SECRET_KEY}"
  },
  "Firebase": {
    "ProjectId": "${FIREBASE_PROJECT_ID}"
  }
}
```

### 4. تفعيل Rate Limiting
```csharp
// Program.cs
builder.Services.AddRateLimiter(options =>
{
    options.AddFixedWindowLimiter("fixed", opt =>
    {
        opt.PermitLimit = 100;
        opt.Window = TimeSpan.FromMinutes(1);
    });
});
```

### 5._headers الأمني
```csharp
// Program.cs
app.UseMiddleware<SecurityHeadersMiddleware>();
```

---

## قائمة التحقق للأمان ✅

- [ ] تغيير جميع كلمات المرور الافتراضية
- [ ] تفعيل HTTPS على VPS
- [ ] إعداد Environment Variables
- [ ] تفعيل Rate Limiting
- [ ] إضافة CORS محدد
- [ ] تفعيل logging للـ security events
- [ ] إعداد firewall (ufw)
- [ ] تغيير منفذ SSH الافتراضي (22)
- [ ] تفعيل fail2ban
- [ ] إنشاء مستخدم جديد لـ SSH (عدم استخدام root)

---

## الاستجابة للحوادث 🚨

### عند اكتشاف اختراق:
1. **عزل النظام**: إيقاف API فوراً
2. **تغيير كلمات المرور**: جميع كلمات المرور
3. **فحص السجلات**: البحث عن نشاط مشبوه
4. **إبلاغ السلطات**: إذا تطلب الأمر
5. **تحديث الأمان**: تطبيق الإصلاحات
6. **نسخ احتياطية**: التأكد من سلامة النسخ
