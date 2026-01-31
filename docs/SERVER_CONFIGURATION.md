# 📋 توثيق إعدادات السيرفر - منصة صدارة

## 🖥️ معلومات السيرفر

| البند | القيمة |
|-------|--------|
| **عنوان IP** | `72.61.183.61` |
| **الاتصال SSH** | `ssh root@72.61.183.61` |
| **نظام التشغيل** | Ubuntu 24.04 LTS |
| **المنفذ API** | `5000` |

---

## 🔗 روابط API

### رابط الإنتاج (Production)
```
http://72.61.183.61:5000/api
```

### رابط التطوير المحلي (Development)
```
http://localhost:5000/api
```

---

## 📁 ملفات الإعدادات المهمة

### 1. Flutter App - api_config.dart
**المسار:** `C:\SadaraPlatform\src\Apps\CompanyDesktop\alsadara-ftth\lib\services\api\api_config.dart`

```dart
/// رابط API للإنتاج (VPS)
static const String prodBaseUrl = 'http://72.61.183.61:5000/api';

/// استخدام بيئة التطوير أو الإنتاج
static const bool isProduction = true;
```

### 2. MAUI App - Constans.cs
**المسار:** `C:\Sadara.APP\Sadara.APP\Constans.cs`

```csharp
// للاختبار على المحاكي Android (10.0.2.2 = localhost)
public static string BaseApiAddress => "http://10.0.2.2:5000";

// للإنتاج - يجب تغييره إلى:
// public static string BaseApiAddress => "http://72.61.183.61:5000";
```

---

## 🔌 الخدمات على السيرفر

| الخدمة | المنفذ | الحالة |
|--------|--------|--------|
| Nginx | 80, 443 | ✅ يعمل |
| .NET API (Sadara.API) | 5000 | ✅ يعمل |
| PostgreSQL | 5432 | ✅ يعمل |

---

## 📡 Endpoints المتاحة

### الشركات (Companies)
| Endpoint | Method | الوصف |
|----------|--------|-------|
| `/api/companies/list` | GET | جلب قائمة الشركات (بدون مصادقة) |
| `/api/companies/login` | POST | تسجيل دخول موظف شركة |

### المصادقة (Auth)
| Endpoint | Method | الوصف |
|----------|--------|-------|
| `/api/auth/login` | POST | تسجيل دخول عام |
| `/api/auth/register` | POST | تسجيل حساب جديد |
| `/api/auth/reset-password` | POST | إعادة تعيين كلمة المرور |

### المدن والمناطق (Cities & Areas)
| Endpoint | Method | الوصف |
|----------|--------|-------|
| `/api/cities` | GET | جلب جميع المدن |
| `/api/cities/{id}/areas` | GET | جلب مناطق مدينة معينة |
| `/api/areas` | GET | جلب جميع المناطق |

### الإعلانات (Advertisings)
| Endpoint | Method | الوصف |
|----------|--------|-------|
| `/api/advertisings` | GET | جلب جميع الإعلانات |
| `/api/advertisings/active` | GET | جلب الإعلانات النشطة |

---

## ⚠️ مشاكل شائعة وحلولها

### المشكلة 1: "غير موجود" عند تسجيل الدخول
**السبب:** التطبيق يشير إلى رابط API خاطئ
**الحل:** تأكد من أن `BaseApiAddress` أو `prodBaseUrl` يشير إلى `http://72.61.183.61:5000/api`

### المشكلة 2: قائمة الشركات فارغة
**السبب:** رابط API غير صحيح
**الحل:** 
1. تحقق من `api_config.dart` في مشروع Flutter
2. تأكد أن `isProduction = true`
3. تأكد أن `prodBaseUrl = 'http://72.61.183.61:5000/api'`

### المشكلة 3: خطأ 404 على endpoints
**السبب:** الـ API القديم (Sadara.API) مختلف عن الجديد (SadaraPlatform)
**الحل:** راجع جدول Endpoints أعلاه واستخدم المسارات الصحيحة

---

## 🔄 كيفية اختبار الاتصال

### من PowerShell:
```powershell
# اختبار جلب الشركات
Invoke-RestMethod -Uri "http://72.61.183.61:5000/api/companies/list" -Method Get

# اختبار جلب المدن
Invoke-RestMethod -Uri "http://72.61.183.61:5000/api/cities" -Method Get
```

### من المتصفح:
```
http://72.61.183.61:5000/api/companies/list
http://72.61.183.61:5000/swagger
```

---

## 📂 مسارات المشاريع

| المشروع | المسار |
|---------|--------|
| SadaraPlatform (API الجديد) | `C:\SadaraPlatform\` |
| Flutter Desktop App | `C:\SadaraPlatform\src\Apps\CompanyDesktop\alsadara-ftth\` |
| MAUI Mobile App | `C:\Sadara.APP\` |
| API القديم (غير مستخدم) | `C:\Sadara.API\` |

---

## 📝 ملاحظات مهمة

1. **لا تستخدم** `https://admin.ftth.iq` - هذا ليس سيرفرنا
2. **السيرفر الخاص:** `72.61.183.61` فقط
3. **عند شراء Domain:** حدّث `prodBaseUrl` في جميع التطبيقات
4. **للمحاكي Android:** استخدم `10.0.2.2` بدلاً من `localhost`

---

*آخر تحديث: 31 يناير 2026*
