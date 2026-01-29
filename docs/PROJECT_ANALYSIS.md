# 📊 تحليل شامل لمشروع منصة الصدارة (Sadara Platform)

## 📋 نظرة عامة على المشروع

### ما هو المشروع؟
منصة الصدارة هي **نظام متكامل لإدارة خدمات الإنترنت (FTTH - Fiber To The Home)** يتكون من:

| المكون | الوصف | التقنية | الحالة |
|--------|-------|---------|--------|
| 🌐 **Backend API** | الخادم الرئيسي | .NET 9 + Clean Architecture | ✅ مكتمل |
| 💻 **تطبيق الشركة** | للموظفين والفنيين | Flutter Desktop (Windows) | ✅ مكتمل |
| 📱 **تطبيق المواطن** | للعملاء | Flutter Web (PWA) | 🔄 قيد التطوير |
| 🗄️ **قاعدة البيانات** | PostgreSQL | على VPS Hostinger | ✅ مُعد |

---

## 🏗️ هيكل المشروع

```
C:\SadaraPlatform\
│
├── 📂 src\
│   ├── 📂 Backend\                      ← الخادم
│   │   ├── API\Sadara.API\              ← 28 Controller
│   │   └── Core\                        ← Clean Architecture
│   │       ├── Sadara.Domain\           ← الكيانات (15+ Entity)
│   │       ├── Sadara.Application\      ← منطق العمل
│   │       └── Sadara.Infrastructure\   ← قاعدة البيانات
│   │
│   └── 📂 Apps\
│       ├── CitizenWeb\                  ← تطبيق المواطن (Flutter Web)
│       └── CompanyDesktop\              ← تطبيق الشركة (Flutter Windows)
│           └── alsadara-ftth\           ← 11,545+ سطر كود
│
├── 📂 docs\                             ← التوثيق
├── 📂 deployment\                       ← ملفات النشر
│   ├── vps\                             ← إعدادات VPS
│   └── firebase\                        ← إعدادات Firebase
├── 📂 docker\                           ← Docker files
└── 📂 scripts\                          ← سكربتات الأتمتة
```

---

## 🔧 المكونات التقنية

### 1️⃣ Backend API (.NET 9)

#### Controllers (28 Controller):
| Controller | الوظيفة | الأهمية |
|------------|---------|---------|
| `AuthController` | مصادقة الموظفين | 🔴 حرج |
| `CitizenAuthController` | مصادقة المواطنين | 🔴 حرج |
| `SuperAdminController` | إدارة النظام | 🔴 حرج |
| `CompaniesController` | إدارة الشركات | 🟡 مهم |
| `UsersController` | إدارة المستخدمين | 🟡 مهم |
| `InternetPlansController` | باقات الإنترنت | 🟡 مهم |
| `CitizenSubscriptionsController` | اشتراكات المواطنين | 🟡 مهم |
| `ProductsController` | المنتجات | 🟢 عادي |
| `OrdersController` | الطلبات | 🟢 عادي |
| `PaymentsController` | المدفوعات | 🟡 مهم |
| `SupportTicketsController` | تذاكر الدعم | 🟢 عادي |
| `NotificationsController` | الإشعارات | 🟢 عادي |
| `DashboardController` | لوحة التحكم | 🟢 عادي |

#### الكيانات (Entities):
```
├── User.cs              ← المستخدمين/الموظفين
├── Citizen.cs           ← المواطنين/العملاء
├── Company.cs           ← الشركات
├── Subscription.cs      ← الاشتراكات
├── Product.cs           ← المنتجات
├── Order.cs             ← الطلبات
├── Payment.cs           ← المدفوعات
├── SupportTicket.cs     ← تذاكر الدعم
└── ...
```

### 2️⃣ تطبيق الشركة (Flutter Desktop)

#### الميزات الرئيسية:
- ✅ إدارة المشتركين والاشتراكات
- ✅ نظام التذاكر والدعم الفني
- ✅ المعاملات المالية والمحافظ
- ✅ تكامل WhatsApp Business API
- ✅ نظام إشعارات Firebase
- ✅ تقارير وتحليلات متقدمة
- ✅ نظام الحضور والانصراف
- ✅ تصدير Excel و PDF

#### الصفحات الكبيرة:
| الملف | عدد الأسطر | الملاحظة |
|-------|-----------|----------|
| `subscription_details_page.dart` | 11,545 | ⚠️ يحتاج تقسيم |
| `home_page.dart` (FTTH) | 4,729 | ⚠️ يحتاج تقسيم |

### 3️⃣ تطبيق المواطن (Flutter Web)

#### الميزات المخططة:
- 📱 تسجيل حساب جديد
- 🔐 تسجيل الدخول بالهاتف
- 📋 عرض الباقات المتاحة
- 💳 طلب اشتراك جديد
- 📊 متابعة الاشتراكات
- 🎫 فتح تذاكر دعم
- 🛒 متجر المنتجات

---

## 🔐 نظام المصادقة والصلاحيات

### أنواع المستخدمين:
```
👑 SuperAdmin (مدير النظام)
   └── يدير جميع الشركات والمستخدمين
   
🏢 CompanyAdmin (مدير الشركة)
   └── يدير موظفي شركته فقط
   
👷 Employee (موظف)
   └── صلاحيات محددة من المدير
   
🔧 Technician (فني)
   └── صلاحيات الصيانة والتركيب
   
💰 Accountant (محاسب)
   └── صلاحيات مالية
   
👤 Citizen (مواطن/عميل)
   └── طلب الخدمات ومتابعتها
```

### آلية المصادقة:
```
┌─────────────────────────────────────────────────────────────┐
│                    تدفق المصادقة                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   المستخدم يدخل:                                            │
│   ├── كود الشركة (أو "1" للـ SuperAdmin)                    │
│   ├── اسم المستخدم                                          │
│   └── كلمة المرور                                           │
│                                                             │
│              ▼                                              │
│   ┌─────────────────────────────────────┐                  │
│   │  POST /api/auth/login               │                  │
│   │  أو                                 │                  │
│   │  POST /api/superadmin/login         │                  │
│   └────────────────┬────────────────────┘                  │
│                    ▼                                        │
│   ┌─────────────────────────────────────┐                  │
│   │  Response:                          │                  │
│   │  {                                  │                  │
│   │    "token": "JWT...",               │                  │
│   │    "refreshToken": "...",           │                  │
│   │    "expiresAt": "...",              │                  │
│   │    "user": {...},                   │                  │
│   │    "company": {...},                │                  │
│   │    "permissions": {...}             │                  │
│   │  }                                  │                  │
│   └─────────────────────────────────────┘                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 🗄️ قاعدة البيانات

### الجداول الرئيسية:
| الجدول | الوصف | العلاقات |
|--------|-------|----------|
| `Companies` | الشركات | 1:N مع Users, Citizens |
| `Users` | الموظفين | N:1 مع Company |
| `Citizens` | المواطنين | N:1 مع Company |
| `InternetPlans` | باقات الإنترنت | N:1 مع Company |
| `CitizenSubscriptions` | اشتراكات المواطنين | N:1 مع Citizen, Plan |
| `Products` | المنتجات | N:1 مع Company |
| `Orders` | الطلبات | N:1 مع Citizen |
| `Payments` | المدفوعات | N:1 مع Order |
| `SupportTickets` | تذاكر الدعم | N:1 مع Citizen |

### الاتصال:
```
Host: 72.61.183.61 (VPS Hostinger)
Port: 5432
Database: SadaraDB
User: postgres
```

---

## ⚠️ المشاكل المتوقعة والحلول

### 🔴 مشاكل حرجة (Critical)

#### 1. أمان الملفات السرية
**المشكلة:** ملفات الـ credentials مكشوفة في الكود
```
❌ firebase-service-account.json في المشروع
❌ service_account.json لـ Google Sheets
❌ كلمات مرور في config.json
```

**الحل:**
```bash
# تم إضافتها إلى .gitignore
*.json (في مجلدات secrets)
.env
firebase-service-account.json
service_account.json
```

#### 2. اتصال قاعدة البيانات
**المشكلة:** PostgreSQL على VPS قد لا يكون مُعداً للاتصال الخارجي

**الحل:**
```bash
# على VPS، تعديل postgresql.conf
listen_addresses = '*'

# تعديل pg_hba.conf
host    all    all    0.0.0.0/0    md5
```

#### 3. HTTPS غير مفعل
**المشكلة:** API يعمل على HTTP فقط

**الحل:**
```bash
# تثبيت Certbot على VPS
sudo apt install certbot
sudo certbot certonly --standalone -d api.alsadara.com
```

### 🟡 مشاكل مهمة (Important)

#### 4. ملفات كود ضخمة
**المشكلة:** بعض الملفات تتجاوز 10,000 سطر
```
subscription_details_page.dart → 11,545 سطر
home_page.dart (FTTH) → 4,729 سطر
```

**الحل:**
- تقسيم الملفات إلى widgets منفصلة
- استخدام نمط BLoC أو Provider
- فصل منطق العمل عن الـ UI

#### 5. تعدد مصادر البيانات
**المشكلة:** التطبيق يستخدم مصادر متعددة:
```
- Firebase Firestore (قديم)
- admin.ftth.iq API (خارجي)
- Sadara API (جديد)
- Google Sheets
```

**الحل:**
- توحيد جميع البيانات في Sadara API
- ترحيل بيانات Firebase إلى PostgreSQL
- إزالة الاعتماد على admin.ftth.iq

#### 6. إدارة الجلسات
**المشكلة:** JWT tokens قد تنتهي أثناء الاستخدام

**الحل:**
```dart
// تم تنفيذه في vps_auth_service.dart
- Refresh Token تلقائي
- حفظ الجلسة في SharedPreferences
- التحقق من صلاحية التوكن قبل كل طلب
```

### 🟢 مشاكل ثانوية (Minor)

#### 7. عدم وجود اختبارات
**المشكلة:** لا توجد Unit Tests أو Integration Tests

**الحل:**
```bash
# إنشاء مجلد tests
tests/
├── unit/
├── integration/
└── e2e/
```

#### 8. التوثيق غير مكتمل
**المشكلة:** بعض الـ APIs غير موثقة

**الحل:**
- إضافة Swagger/OpenAPI
- توثيق كل endpoint
- إنشاء Postman Collection

#### 9. عدم وجود CI/CD
**المشكلة:** النشر يدوي

**الحل:**
```yaml
# GitHub Actions
- Build on push
- Run tests
- Deploy to VPS
```

---

## 📊 تقييم الجاهزية

| المكون | الجاهزية | الملاحظات |
|--------|----------|-----------|
| Backend API | 85% | يحتاج HTTPS وتحسينات أمنية |
| تطبيق الشركة | 90% | يعمل، يحتاج تحسينات |
| تطبيق المواطن | 40% | قيد التطوير |
| قاعدة البيانات | 80% | مُعدة، تحتاج تحسينات |
| الأمان | 60% | يحتاج تحسينات كبيرة |
| التوثيق | 70% | جيد، يحتاج تحديث |
| الاختبارات | 10% | شبه معدومة |

---

## 🚀 خطة العمل المقترحة

### المرحلة 1: الأمان (أسبوع 1)
- [x] تحديث .gitignore
- [x] إنشاء .env
- [ ] تفعيل HTTPS
- [ ] تأمين PostgreSQL

### المرحلة 2: الاستقرار (أسبوع 2)
- [ ] اختبار جميع الـ APIs
- [ ] إصلاح الأخطاء
- [ ] تحسين الأداء

### المرحلة 3: التوحيد (أسبوع 3-4)
- [ ] ترحيل Firebase إلى PostgreSQL
- [ ] توحيد مصادر البيانات
- [ ] تحديث تطبيق الشركة

### المرحلة 4: الإطلاق (أسبوع 5)
- [ ] إكمال تطبيق المواطن
- [ ] اختبارات شاملة
- [ ] النشر النهائي

---

## 📞 معلومات الاتصال

| المعلومة | القيمة |
|----------|--------|
| VPS IP | `72.61.183.61` |
| VPS Provider | Hostinger |
| VPS OS | Ubuntu 24.04 LTS |
| Firebase Project | `web-app-sadara` |
| API Port | 5000 (dev) / 443 (prod) |

---

## 📝 ملاحظات ختامية

1. **المشروع متقدم** ويحتاج تحسينات أمنية وتنظيمية
2. **الأولوية القصوى** هي تأمين الملفات السرية وتفعيل HTTPS
3. **التوحيد** ضروري لتقليل التعقيد والصيانة
4. **الاختبارات** مهمة لضمان الجودة قبل الإطلاق

---

*آخر تحديث: يناير 2026*
