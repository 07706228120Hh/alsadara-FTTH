# منصة الصدارة - تعليمات الذكاء الاصطناعي

## 📋 نظرة عامة على المشروع

منصة لإدارة خدمات الإنترنت (ISP) تتكون من ثلاثة مكونات:

| المكون | التقنية | المسار |
|--------|---------|--------|
| الخادم (API) | .NET 9, Clean Architecture | `src/Backend/` |
| بوابة المواطن | Blazor WebAssembly PWA | `src/Apps/CitizenWeb/` |
| تطبيق الشركة | Flutter Windows | `src/Apps/CompanyDesktop/alsadara-ftth/` |

---

## 🏗️ البنية الأساسية (Clean Architecture)

### طبقات الخادم
```
src/Backend/
├── API/Sadara.API/              → Controllers, DTOs (نقطة الدخول)
├── Core/Sadara.Application/     → Services, Interfaces, Validators
├── Core/Sadara.Domain/          → Entities, Enums (بدون اعتماديات)
└── Core/Sadara.Infrastructure/  → DbContext, Repositories, خدمات خارجية
```

### تدفق البيانات
```
Controller → Service → UnitOfWork/Repository → DbContext → PostgreSQL
```

---

## 🗄️ نظام قاعدة البيانات وتخزين البيانات

### الكيانات الرئيسية (Entities)
```
Sadara.Domain/Entities/
├── BaseEntity.cs          → الكيان الأساسي (CreatedAt, UpdatedAt, IsDeleted)
├── User.cs                → المستخدمون (صلاحيات JSON مدمجة)
├── Company.cs             → الشركات (Multi-Tenant)
├── Customer.cs            → العملاء
├── Order.cs               → الطلبات
├── Payment.cs             → المدفوعات
├── ServiceAndPermission.cs → الصلاحيات والخدمات (Permission, PermissionGroup, etc.)
├── Citizen.cs             → بيانات المواطنين
└── Subscription.cs        → الاشتراكات
```

### طريقة الخزن والجلب
- **Unit of Work Pattern**: `IUnitOfWork` يدير كل الـ Repositories
- **Generic Repository**: `Repository<T, TId>` يوفر CRUD operations
- **Soft Delete**: الكيانات لديها `IsDeleted` مع Query Filters تلقائية
- **مثال الجلب**:
  ```csharp
  // جلب مستخدم
  var user = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.PhoneNumber == phone);
  
  // جلب مع Includes
  var orders = await _unitOfWork.Orders.GetWithIncludesAsync(
      o => o.CustomerId == customerId,
      ct,
      o => o.OrderItems);
  ```

### الصلاحيات (نظام مزدوج)
```csharp
// V1 - بسيط (Boolean)
User.FirstSystemPermissions = '{"attendance":true,"agent":false}'

// V2 - مفصل (Actions)
User.SecondSystemPermissionsV2 = '{"users":{"view":true,"add":true,"edit":false,"delete":false}}'
```

---

## 📱 تطبيق Flutter Desktop

### البنية
```
lib/
├── config/                 → إعدادات (data_source_config.dart)
├── models/                 → نماذج البيانات
├── pages/                  → الصفحات
│   ├── admin/             → صفحات الإدارة
│   ├── super_admin/       → صفحات مدير النظام
│   └── citizen_portal/    → بوابة المواطن
├── services/              → الخدمات (API, Auth, Permissions)
├── widgets/               → المكونات المشتركة
└── ftth/                  → نظام FTTH الخاص
```

### مصادر البيانات
```dart
// في data_source_config.dart
enum DataSource { firebase, vpsApi }
static const DataSource currentSource = DataSource.vpsApi; // الافتراضي
```

### Singleton Pattern للخدمات
```dart
class ApiService {
  static ApiService? _instance;
  static ApiService get instance => _instance ??= ApiService._internal();
  ApiService._internal();
}
```

---

## ⚠️ ملفات غير مستخدمة (يمكن حذفها)

### ملفات Class1.cs الفارغة
```
src/Backend/Core/Sadara.Domain/Class1.cs        ← حذف
src/Backend/Core/Sadara.Application/Class1.cs   ← حذف
src/Backend/Core/Sadara.Infrastructure/Class1.cs ← حذف
```

### ملفات SQL مؤقتة في الجذر
```
/add_citizen_permissions.sql    ← نقل إلى scripts/ أو حذف
/add_company.sql                ← نقل إلى scripts/ أو حذف
/check_columns.sql              ← نقل إلى scripts/ أو حذف
/check_db.sql                   ← نقل إلى scripts/ أو حذف
/apply_migration.sql            ← نقل إلى scripts/ أو حذف
```

### ملفات توثيق قديمة
```
/ANALYSIS_REPORT.md             ← تم دمجه في التعليمات
/PERMISSIONS_SYSTEM_ANALYSIS.md ← تم دمجه
/MANAGER_DASHBOARD_ISSUES_ANALYSIS.md ← مراجعة للحذف
```

---

## 🔄 التغييرات والتحديثات الأخيرة

### سجل Git الأخير
```
276913d Fix API auth and database admin updates
0f4aefb تحديث: إصلاح حفظ الصلاحيات وتحسين تصميم نافذة الصلاحيات
f64177e Add comprehensive implementation plan
9b0f98e Initial commit - Project reorganization and structure setup
```

### التغييرات الرئيسية
1. **نظام الصلاحيات V2**: إضافة صلاحيات مفصلة (view, add, edit, delete)
2. **ربط نظام المواطن**: ربط Company بـ Citizen Portal
3. **إصلاح المصادقة**: تحسين JWT و API Key security

---

## ➕ كيفية إضافة تحسينات جديدة

### إضافة Entity جديد
1. أنشئ الملف في `Domain/Entities/`
2. سجّله في `SadaraDbContext.cs`:
   ```csharp
   public DbSet<NewEntity> NewEntities => Set<NewEntity>();
   ```
3. أضف Repository في `UnitOfWork.cs`
4. أنشئ Migration:
   ```powershell
   cd src/Backend/Core/Sadara.Infrastructure
   dotnet ef migrations add AddNewEntity
   ```

### إضافة Controller جديد
1. أنشئ الملف في `API/Controllers/`
2. استخدم النمط:
   ```csharp
   [ApiController]
   [Route("api/[controller]")]
   public class NewController : ControllerBase
   {
       private readonly IUnitOfWork _unitOfWork;
       // ...
   }
   ```

### إضافة صفحة Flutter جديدة
1. أنشئ الملف في `lib/pages/`
2. سجّلها في Navigation
3. أضف الصلاحيات إذا لزم في `permissions_service.dart`

### إضافة صلاحية جديدة
1. **الخادم**: في `SeedData.cs` → `SeedPermissionsAsync()`
2. **Flutter**: في `permissions_service.dart`:
   ```dart
   static const List<String> secondSystemPermissions = [
     // ... موجود
     'new_permission', // جديد
   ];
   ```
3. أضف `PermissionsGate` في الواجهة

---

## 🚀 أوامر التشغيل

```powershell
# إعداد البيئة
cd C:\SadaraPlatform\scripts; .\setup-dev.ps1

# تشغيل API
cd C:\SadaraPlatform\src\Backend\API\Sadara.API
dotnet run --urls "http://localhost:5000"

# تشغيل Flutter
cd C:\SadaraPlatform\src\Apps\CompanyDesktop\alsadara-ftth
flutter run -d windows

# Docker (PostgreSQL + pgAdmin)
cd C:\SadaraPlatform\docker
docker-compose up -d postgres pgadmin
```

---

## 🔧 نقاط التكامل

| الخدمة | الإعدادات |
|--------|-----------|
| Firebase Auth | `secrets/firebase-service-account.json` |
| Google Sheets | `assets/service_account.json` (Flutter) |
| JWT | `appsettings.json` → `Jwt:Secret` (32+ حرف) |
| PostgreSQL | `ConnectionStrings:DefaultConnection` |

---

## 📁 مواقع الملفات للمهام الشائعة

| المهمة | المسار |
|--------|--------|
| إضافة endpoint جديد | `src/Backend/API/Sadara.API/Controllers/` |
| إضافة entity جديد | `src/Backend/Core/Sadara.Domain/Entities/` |
| إضافة صفحة Flutter | `src/Apps/CompanyDesktop/alsadara-ftth/lib/pages/` |
| إضافة خدمة Flutter | `src/Apps/CompanyDesktop/alsadara-ftth/lib/services/` |
| تعديل المصادقة | `Services.cs` (خادم) أو `unified_auth_manager.dart` (Flutter) |
| إضافة صلاحية | `permissions_service.dart` + `SeedData.cs` |

---

## ⚡ مشاكل معروفة للإصلاح

1. **API Key ثابت**: مخزن hardcoded في الكود (يجب نقله إلى Environment Variables)
2. **CORS مفتوح**: `AllowAnyOrigin()` يجب تقييده في Production
3. **EmployeeCount = 0**: في `InternalDataController` لا يحسب العدد الفعلي
4. **TODO comments**: موجودة في بعض الملفات (badge_service.dart, notification_service.dart)
