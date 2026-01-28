# 🏢 منصة الصدارة - Sadara Platform

<div align="center">

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![.NET](https://img.shields.io/badge/.NET-9.0-purple.svg)
![Flutter](https://img.shields.io/badge/Flutter-3.x-blue.svg)
![License](https://img.shields.io/badge/license-Private-red.svg)

**منصة متكاملة لإدارة خدمات الإنترنت والمنتجات للمواطنين والشركات**

</div>

---

## 📋 نظرة عامة

منصة الصدارة هي نظام متكامل يتكون من:

| المكون | الوصف | التقنية |
|--------|-------|---------|
| 🌐 **Backend API** | الخادم الرئيسي | .NET 9, Clean Architecture |
| 📱 **تطبيق المواطن** | للمواطنين لطلب الخدمات | Blazor WebAssembly (PWA) |
| 💻 **تطبيق الشركة** | للموظفين لإدارة الطلبات | Flutter Desktop |

---

## 📁 هيكل المشروع

```
C:\SadaraPlatform\
│
├── 📂 src\                           ← الكود المصدري
│   ├── 📂 Backend\                   ← API والمنطق الخلفي
│   │   ├── API\Sadara.API\           ← Controllers ونقطة الدخول
│   │   └── Core\                     ← Domain, Application, Infrastructure
│   │
│   ├── 📂 Apps\                      ← التطبيقات
│   │   ├── CitizenWeb\               ← تطبيق المواطن (PWA)
│   │   └── CompanyDesktop\           ← تطبيق الشركة (Flutter)
│   │
│   └── 📂 Shared\                    ← كود مشترك
│
├── 📂 docs\                          ← التوثيق
├── 📂 scripts\                       ← سكربتات الأتمتة
├── 📂 secrets\                       ← الملفات السرية ⚠️
├── 📂 tests\                         ← الاختبارات
└── 📂 docker\                        ← ملفات Docker
```

---

## 🚀 البدء السريع

### المتطلبات
- [.NET 9 SDK](https://dot.net)
- [Flutter 3.x](https://flutter.dev)
- [Visual Studio Code](https://code.visualstudio.com)

### 1️⃣ إعداد بيئة التطوير
```powershell
cd C:\SadaraPlatform\scripts
.\setup-dev.ps1
```

### 2️⃣ تشغيل API
```powershell
cd C:\SadaraPlatform\src\Backend\API\Sadara.API
dotnet run --urls "http://localhost:5000"
```

### 3️⃣ تشغيل تطبيق الشركة
```powershell
cd C:\SadaraPlatform\src\Apps\CompanyDesktop\alsadara-ftth
flutter run -d windows
```

---

## 🔐 نظام الصلاحيات

```
👑 مدير النظام (Super Admin)
   └── يدير الشركات ومديريها
   
🏢 مدير الشركة (Company Admin)
   └── يدير موظفي شركته وصلاحياتهم
   
👷 الموظف (Employee)
   └── صلاحيات محددة من مدير الشركة
   
👤 المواطن (Citizen)
   └── طلب الخدمات ومتابعتها
```

---

## 🛠️ الخدمات المدعومة

| الخدمة | العمليات المتاحة |
|--------|-----------------|
| 🌐 الإنترنت | شراء، تجديد، صيانة، تغيير، شكوى، إلغاء |
| 🛍️ المنتجات | شراء، استبدال، شكوى، إرجاع |
| ➕ خدمات مستقبلية | قابل للتوسع |

---

## 📚 التوثيق

| الملف | الوصف |
|-------|-------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | هيكل المشروع التفصيلي |
| [DATABASE.md](docs/DATABASE.md) | توثيق قاعدة البيانات |
| [DEPLOYMENT.md](docs/DEPLOYMENT.md) | دليل النشر |

---

## 🔧 السكربتات

| السكربت | الوظيفة |
|---------|---------|
| `scripts/setup-dev.ps1` | إعداد بيئة التطوير |
| `scripts/deploy.ps1` | نشر API على الخادم |
| `scripts/backup.ps1` | نسخ احتياطي للمشروع |

---

## 🌐 الخادم (VPS)

| المعلومة | القيمة |
|----------|--------|
| IP | `72.61.183.61` |
| OS | Ubuntu 24.04 LTS |
| RAM | 8GB |
| Provider | Hostinger |

---

## ⚠️ ملاحظات أمنية

- **لا ترفع** مجلد `secrets/` على Git
- **لا تشارك** ملفات `.env`
- **غيّر** كلمات المرور الافتراضية

---

## 📞 الدعم

للدعم الفني أو الاستفسارات، تواصل مع فريق التطوير.

---

<div align="center">

**صُنع بـ ❤️ في العراق**

</div>
