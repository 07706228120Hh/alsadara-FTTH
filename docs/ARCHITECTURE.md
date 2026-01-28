# 🏗️ هيكل مشروع منصة الصدارة

## 📁 نظرة عامة على الهيكل

```
C:\SadaraPlatform\
│
├── 📂 src\                           ← كل الكود المصدري
│   │
│   ├── 📂 Backend\                   ← الخادم (API)
│   │   ├── API\                      ← نقطة الدخول (Controllers)
│   │   ├── Core\                     ← المنطق الأساسي
│   │   │   ├── Sadara.Domain\        ← الكيانات والقواعد
│   │   │   ├── Sadara.Application\   ← منطق العمل
│   │   │   └── Sadara.Infrastructure\← قاعدة البيانات والخدمات الخارجية
│   │   └── Services\                 ← خدمات مشتركة
│   │
│   ├── 📂 Apps\                      ← التطبيقات
│   │   ├── CitizenWeb\               ← تطبيق المواطن (PWA - Blazor)
│   │   └── CompanyDesktop\           ← تطبيق الشركة (Flutter)
│   │
│   └── 📂 Shared\                    ← كود مشترك
│
├── 📂 tests\                         ← الاختبارات
├── 📂 docs\                          ← التوثيق
├── 📂 scripts\                       ← سكربتات الأتمتة
├── 📂 secrets\                       ← الملفات السرية (⚠️ لا تُرفع على Git)
└── 📂 docker\                        ← ملفات Docker
```

---

## 📂 شرح تفصيلي لكل مجلد

### 🔙 Backend (الخادم)

| المجلد | الوظيفة | أمثلة |
|--------|---------|-------|
| `API/Sadara.API` | نقطة الدخول، Controllers | UsersController, ServicesController |
| `Core/Sadara.Domain` | الكيانات والقواعد الأساسية | User, Company, ServiceRequest |
| `Core/Sadara.Application` | منطق العمل والخدمات | UserService, RequestService |
| `Core/Sadara.Infrastructure` | البنية التحتية | DbContext, FirebaseService |

### 📱 Apps (التطبيقات)

| المجلد | التقنية | الاستخدام |
|--------|---------|-----------|
| `CitizenWeb` | Blazor WebAssembly (PWA) | للمواطنين - ويب قابل للتثبيت |
| `CompanyDesktop` | Flutter | للموظفين - Windows Desktop |

---

## 🔄 تدفق البيانات

```
📱 تطبيق المواطن ──┐
                    │
📱 تطبيق الشركة ────┼──→ 🌐 API ──→ 🗄️ PostgreSQL
                    │            │
🌐 أي تطبيق آخر ────┘            └──→ 🔥 Firebase (Real-time)
```

---

## 📋 معايير التسمية

| النوع | القاعدة | مثال |
|-------|--------|-------|
| المجلدات | PascalCase | `CompanyDesktop` |
| الملفات C# | PascalCase | `UserService.cs` |
| ملفات Dart | snake_case | `user_service.dart` |
| الكيانات | مفرد | `User` (ليس Users) |
| Controllers | جمع + Controller | `UsersController` |

---

## 🚀 أوامر التشغيل

### تشغيل API
```powershell
cd C:\SadaraPlatform\src\Backend\API\Sadara.API
dotnet run --urls "http://localhost:5000"
```

### تشغيل تطبيق الشركة (Flutter)
```powershell
cd C:\SadaraPlatform\src\Apps\CompanyDesktop\alsadara-ftth
flutter run -d windows
```

### تشغيل تطبيق المواطن (Blazor)
```powershell
cd C:\SadaraPlatform\src\Apps\CitizenWeb
dotnet run
```
