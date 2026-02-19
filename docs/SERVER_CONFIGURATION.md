# 📋 توثيق إعدادات السيرفر - منصة صدارة

## ⚠️ تحذير مهم: بنية السيرفرات

### سيرفر صدارة الرئيسي (الخاص بنا)
| البند | القيمة |
|-------|--------|
| **عنوان IP** | `72.61.183.61` |
| **الاتصال SSH** | `ssh root@72.61.183.61` |
| **نظام التشغيل** | Ubuntu 24.04 LTS |
| **المنفذ API** | `5000` |
| **الاستخدام** | **تخزين وقراءة جميع بيانات المنصة** (مستخدمين، شركات، مهام، طلبات...) |
| **الخدمات** | .NET API (Sadara.API) + PostgreSQL + Nginx |
| **النشر** | `scp -r ./publish/* root@72.61.183.61:/var/www/sadara-api/` |

### سيرفر FTTH الخارجي (ليس خاص بنا)
| البند | القيمة |
|-------|--------|
| **الدومين** | `api.ftth.iq` / `admin.ftth.iq` |
| **عنوان IP** | `185.239.19.3` |
| **الاستخدام** | **جلب بيانات نظام FTTH فقط** (بيانات المشتركين، الفلاتر، شبكة الألياف البصرية) |
| **ملاحظة** | ⛔ لا نملك صلاحية SSH عليه، لا ننشر كود عليه، لا نعدل قاعدة بياناته |

### كيف تعمل البنية:
```
┌─────────────────────────────┐
│  تطبيق Flutter Desktop     │
│  (CompanyDesktop)           │
│                             │
│  baseUrl: api.ftth.iq/api   │──► سيرفر FTTH الخارجي (185.239.19.3)
│                             │    يعمل كـ reverse proxy ويمرر الطلبات
│                             │    إلى سيرفرنا الرئيسي
│                             │
│  customGet: admin.ftth.iq   │──► بيانات FTTH الخارجية فقط
└─────────────────────────────┘    (فلاتر، مشتركين، الألياف)
         │
         ▼
┌─────────────────────────────┐
│  سيرفرنا الرئيسي           │
│  72.61.183.61:5000          │
│                             │
│  ✅ هنا يتم:               │
│  - تخزين جميع البيانات     │
│  - قراءة جميع البيانات     │
│  - تشغيل Sadara.API        │
│  - PostgreSQL               │
│  - النشر والتحديث          │
└─────────────────────────────┘

⚠️ عند النشر: انشر دائماً على 72.61.183.61 فقط!
⚠️ لا تحاول النشر أو SSH على 185.239.19.3!
```

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

1. **سيرفرنا الرئيسي:** `72.61.183.61` — هنا يتم تخزين وقراءة **جميع** بيانات المنصة
2. **`api.ftth.iq` (185.239.19.3):** سيرفر خارجي ليس خاص بنا — نستخدمه فقط لجلب بيانات FTTH
3. **⛔ لا تحاول SSH أو النشر على 185.239.19.3** — لا نملك صلاحية عليه
4. **النشر دائماً:** `scp → root@72.61.183.61:/var/www/sadara-api/` ثم `systemctl restart sadara-api`
5. **عند شراء Domain:** حدّث `baseUrl` في `api_service.dart` ليشير للدومين الجديد
6. **للمحاكي Android:** استخدم `10.0.2.2` بدلاً من `localhost`

---

*آخر تحديث: 17 فبراير 2026*
