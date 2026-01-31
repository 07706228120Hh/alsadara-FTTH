# ═══════════════════════════════════════════════════════════════════════════════
#                          منصة الصدارة - SadaraPlatform
# ═══════════════════════════════════════════════════════════════════════════════
#         شرح ملف الحل (Solution File) - SadaraPlatform.sln
# ═══════════════════════════════════════════════════════════════════════════════

## 📋 معلومات عامة

| الحقل | القيمة |
|-------|--------|
| **الاسم** | SadaraPlatform.sln |
| **النوع** | Visual Studio Solution File |
| **الإصدار** | Format Version 12.00 |
| **Visual Studio** | Version 17 (VS 2022) |

---

## 📁 بنية المشروع

```
SadaraPlatform.sln
├── 📂 src/                           ← مجلد الحل الرئيسي
│   ├── 📂 API/                       ← مجلد الواجهة البرمجية
│   │   └── 📦 Sadara.API             → REST API Controllers
│   └── 📂 Core/                      ← مجلد الطبقات الأساسية
│       ├── 📦 Sadara.Domain          → الكيانات (Entities)
│       ├── 📦 Sadara.Application     → الخدمات (Services)
│       └── 📦 Sadara.Infrastructure  → قاعدة البيانات (DbContext)
```

---

## 🏗️ المشاريع (Projects)

### 1️⃣ Sadara.Domain - طبقة الكيانات
| الخاصية | القيمة |
|---------|--------|
| **المسار** | `src/Backend/Core/Sadara.Domain/` |
| **GUID** | `{55E86CED-16E9-439F-B75B-BBCEEE67DC23}` |
| **الغرض** | تعريف كيانات قاعدة البيانات (Entities) والـ Enums |
| **الاعتماديات** | لا شيء (طبقة مستقلة تماماً) |

**الملفات الرئيسية:**
- `Entities/` → User, Company, Order, Customer, Product, etc.
- `Enums/` → UserRole, OrderStatus, SubscriptionStatus, etc.

---

### 2️⃣ Sadara.Application - طبقة الخدمات
| الخاصية | القيمة |
|---------|--------|
| **المسار** | `src/Backend/Core/Sadara.Application/` |
| **GUID** | `{C07879CE-2D6E-4155-BBD4-397DD49208FF}` |
| **الغرض** | منطق الأعمال، الخدمات، Interfaces, DTOs |
| **الاعتماديات** | `Sadara.Domain` |

**الملفات الرئيسية:**
- `Services/Services.cs` → جميع الخدمات
- `DTOs/DTOs.cs` → نماذج نقل البيانات
- `Interfaces/` → الواجهات
- `Validators/` → FluentValidation

---

### 3️⃣ Sadara.Infrastructure - طبقة البنية التحتية
| الخاصية | القيمة |
|---------|--------|
| **المسار** | `src/Backend/Core/Sadara.Infrastructure/` |
| **GUID** | `{4FDCB063-C15C-4B05-BCC7-AB5C4447BBC4}` |
| **الغرض** | DbContext, Repositories, خدمات خارجية |
| **الاعتماديات** | `Sadara.Domain`, `Sadara.Application` |

**الملفات الرئيسية:**
- `Data/SadaraDbContext.cs` → Entity Framework DbContext
- `Repositories/` → Repository Pattern
- `UnitOfWork/` → Unit of Work Pattern
- `Services/Firebase/` → Firebase integration
- `Services/Server/` → VPS control

---

### 4️⃣ Sadara.API - الواجهة البرمجية
| الخاصية | القيمة |
|---------|--------|
| **المسار** | `src/Backend/API/Sadara.API/` |
| **GUID** | `{4CCF8BB4-9350-4BC3-8000-9B61E1CE5925}` |
| **الغرض** | Controllers, Endpoints, Middleware |
| **الاعتماديات** | `Sadara.Domain`, `Sadara.Application`, `Sadara.Infrastructure` |

**الملفات الرئيسية:**
- `Program.cs` → نقطة دخول التطبيق
- `Controllers/` → 30+ controller
- `appsettings.json` → الإعدادات

---

## 🔄 تدفق الاعتماديات (Dependency Flow)

```
┌─────────────┐     ┌─────────────────────┐     ┌────────────────────────┐     ┌──────────────────┐
│  Sadara.API │ ──► │ Sadara.Application  │ ──► │ Sadara.Infrastructure  │ ──► │  Sadara.Domain   │
│ Controllers │     │     Services        │     │      DbContext         │     │    Entities      │
└─────────────┘     └─────────────────────┘     └────────────────────────┘     └──────────────────┘
      ▲                                                                                │
      │                                                                                │
      └────────────────────────────────────────────────────────────────────────────────┘
                                    Direct Reference
```

---

## ⚙️ أوضاع البناء (Build Configurations)

| الوضع | الاستخدام | التحسينات |
|-------|-----------|-----------|
| **Debug** | التطوير المحلي | رموز التصحيح، logs مفصلة |
| **Release** | الإنتاج | محسّن للأداء، بدون debug symbols |

---

## 🚀 أوامر التشغيل

```powershell
# بناء كل المشاريع
dotnet build SadaraPlatform.sln

# تشغيل API
dotnet run --project src/Backend/API/Sadara.API

# بناء للإنتاج
dotnet build SadaraPlatform.sln -c Release

# نشر التطبيق
dotnet publish src/Backend/API/Sadara.API -c Release -o publish/
```

---

## 📂 مجلدات الحل (Solution Folders)

مجلدات الحل هي للتنظيم فقط في Visual Studio، لا تحتوي على كود فعلي:

| المجلد | GUID | المحتوى |
|--------|------|---------|
| `src` | `{827E0CD3-B72D-47B6-A68D-7590B98EB39B}` | المجلد الجذري |
| `Core` | `{8D626EA8-CB54-BC41-363A-217881BEBA6E}` | طبقات Clean Architecture |
| `API` | `{984BB9B3-3FA3-BE33-9484-CAC21695A33C}` | مشروع الواجهة البرمجية |

---

## 📋 آخر تحديث

- **التاريخ:** 2026-01-31
- **الإجراء:** تنظيف المشروع وإصلاح warnings
