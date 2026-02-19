# منصة الصدارة - تعليمات وكيل الذكاء الاصطناعي

## نظرة عامة على البنية

منصة لإدارة خدمات الإنترنت (ISP) تتكون من 3 مكونات:
- **خادم API**: .NET 9 مع Clean Architecture ← `src/Backend/`
- **بوابة المواطن**: Blazor WebAssembly PWA ← `src/Apps/CitizenWeb/`
- **تطبيق الشركة**: Flutter Windows ← `src/Apps/CompanyDesktop/alsadara-ftth/`

### هيكل طبقات الخادم
```
src/Backend/
├── API/Sadara.API/           # Controllers, DTOs, Program.cs (نقطة الدخول)
├── Core/Sadara.Domain/       # Entities, Enums, Interfaces (بدون اعتماديات)
├── Core/Sadara.Application/  # Services, Validators, DTOs
└── Core/Sadara.Infrastructure/ # DbContext, Repositories, خدمات خارجية
```

**تدفق البيانات**: `Controller → Service → IUnitOfWork → Repository<T,TId> → PostgreSQL`

---

## الأنماط الحرجة

### 1. نمط Unit of Work (الخادم)
دائماً استخدم `IUnitOfWork` للوصول للبيانات - لا تُنشئ Repository مباشرة:
```csharp
// ✅ صحيح - في Controller أو Service
public UsersController(IUnitOfWork unitOfWork) => _unitOfWork = unitOfWork;
var user = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.PhoneNumber == phone);

// ❌ خطأ - إنشاء Repository مباشرة
var repo = new Repository<User, Guid>(context);
```

**الواجهات المهمة**:
- `IUnitOfWork` - في `Domain/Interfaces/Interfaces.cs`
- `IRepository<T, TId>` - generic repository pattern
- جميع الـ Repositories متاحة كخصائص في UnitOfWork (مثل `.Users`, `.Companies`, `.ServiceRequests`)

### 2. الحذف الناعم - جميع الكيانات ترث BaseEntity
```csharp
public abstract class BaseEntity {
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? UpdatedAt { get; set; }
    public bool IsDeleted { get; set; } = false;  // Query Filters تستبعد المحذوفات تلقائياً
    public DateTime? DeletedAt { get; set; }
}

public abstract class BaseEntity<TId> : BaseEntity {
    public TId Id { get; set; } = default!;
}
```

**Global Query Filters** في `SadaraDbContext.cs`:
```csharp
modelBuilder.Entity<User>().HasQueryFilter(x => !x.IsDeleted);
```
جميع الاستعلامات تستبعد السجلات المحذوفة تلقائياً - استخدم `IgnoreQueryFilters()` للوصول إليها.

### 3. نظام الصلاحيات المزدوج (V1 + V2)
الصلاحيات مخزنة كـ JSON في كيان `User`:
```csharp
// V1 - أعلام بسيطة (قديم)
User.FirstSystemPermissions = '{"attendance":true,"agent":false}'
User.SecondSystemPermissions = '{"users":true,"subscriptions":false}'

// V2 - مبني على الإجراءات (المعيار الحالي - استخدمه)
User.FirstSystemPermissionsV2 = '{"attendance":{"view":true,"add":false,...}}'
User.SecondSystemPermissionsV2 = '{"users":{"view":true,"add":true,"edit":false,"delete":false}}'
```

**Authorization Policies**:
- `SuperAdmin` - مدير النظام (أعلى صلاحية)
- `Admin` - مدير شركة أو مشرف
- `Merchant` - تاجر
- استخدم `[Authorize(Policy = "Admin")]` على Controllers/Actions

### 4. خدمات Flutter بنمط Singleton
جميع الخدمات تستخدم نمط Singleton:
```dart
class ApiService {
  static ApiService? _instance;
  static ApiService get instance => _instance ??= ApiService._internal();
  ApiService._internal();
}
```
لا تُنشئ instances جديدة - استخدم `.instance` دائماً.

### 5. تبديل مصدر البيانات في Flutter
راجع `lib/config/data_source_config.dart` - حالياً يستخدم VPS API:
```dart
static const DataSource currentSource = DataSource.vpsApi;  // ليس firebase
```
**base URL**: `https://api.ftth.iq/api` في `api_service.dart`

### ⚠️ بنية السيرفرات (مهم جداً)

| السيرفر | IP | الاستخدام |
|---------|----|-----------|
| **سيرفرنا الرئيسي** | `72.61.183.61` | تخزين وقراءة **جميع** بيانات المنصة (API + PostgreSQL + Nginx) |
| **سيرفر FTTH الخارجي** | `185.239.19.3` (`api.ftth.iq`) | جلب بيانات FTTH فقط (مشتركين، فلاتر، ألياف) - **ليس خاص بنا** |

**قواعد صارمة:**
- ✅ **النشر دائماً على** `72.61.183.61` فقط: `scp → root@72.61.183.61:/var/www/sadara-api/`
- ⛔ **لا تحاول SSH أو النشر على** `185.239.19.3` — لا نملك صلاحية عليه
- `api.ftth.iq` يعمل كـ reverse proxy يمرر الطلبات لسيرفرنا
- `admin.ftth.iq` / `dashboard.ftth.iq` = أنظمة FTTH خارجية نجلب منها بيانات فقط

### 6. Dependency Injection في .NET
`Program.cs` يُعد جميع الخدمات:
- `AddDbContext<SadaraDbContext>` - مع PostgreSQL أو InMemory
- `AddScoped<IUnitOfWork, UnitOfWork>` - لكل request
- `AddScoped<IPasswordHasher, PasswordHasher>` - تشفير كلمات المرور
- JWT Authentication مع Bearer tokens

---

## سير عمل المطور

### الإعداد الأولي
```powershell
cd C:\SadaraPlatform\scripts; .\setup-dev.ps1
```

### تشغيل API (Terminal 1)
```powershell
cd C:\SadaraPlatform\src\Backend\API\Sadara.API
dotnet run --urls "http://localhost:5000"
```

### تشغيل Flutter Desktop (Terminal 2)
```powershell
cd C:\SadaraPlatform\src\Apps\CompanyDesktop\alsadara-ftth
flutter run -d windows
```

### قاعدة البيانات مع Docker
```powershell
cd C:\SadaraPlatform\docker
docker-compose up -d postgres pgadmin  # pgAdmin على localhost:8080 (admin@sadara.com / admin123)
```

### ترحيلات EF Core
```powershell
cd src/Backend/Core/Sadara.Infrastructure
dotnet ef migrations add MigrationName --startup-project ../../API/Sadara.API
dotnet ef database update --startup-project ../../API/Sadara.API
```

**ملاحظة**: جميع migrations يجب أن تُشغل من `Sadara.Infrastructure` مع `--startup-project` يشير لـ API.

---

## إضافة ميزات جديدة

### إضافة Entity جديد
1. أنشئه في `Domain/Entities/` وارث من `BaseEntity<TId>`
2. أضف `DbSet<NewEntity>` في `Infrastructure/Data/SadaraDbContext.cs`
3. أضف query filter في `OnModelCreating`: `modelBuilder.Entity<NewEntity>().HasQueryFilter(x => !x.IsDeleted);`
4. أضف repository property في `Infrastructure/Repositories/UnitOfWork.cs`:
   ```csharp
   private IRepository<NewEntity, Guid>? _newEntities;
   public IRepository<NewEntity, Guid> NewEntities =>
       _newEntities ??= new Repository<NewEntity, Guid>(_context);
   ```
5. أضف property للواجهة في `Domain/Interfaces/Interfaces.cs` (`IUnitOfWork`)
6. شغّل migration: `dotnet ef migrations add AddNewEntity`

### إضافة Endpoint جديد
استخدم هذا النمط للـ Controller (Primary Constructor):
```csharp
[ApiController]
[Route("api/[controller]")]
public class NewController(IUnitOfWork unitOfWork) : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork = unitOfWork;

    [HttpGet]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetAll()
    {
        var items = await _unitOfWork.NewEntities.GetAllAsync();
        return Ok(items);
    }
}
```

### إضافة صلاحية جديدة
1. **الخادم**: أضفها في `Infrastructure/Data/SeedData.cs` ← `SeedPermissionsAsync()`
2. **Flutter**: أضفها في `services/permissions_service.dart`:
   ```dart
   static const List<String> secondSystemPermissions = [
     'users', 'subscriptions', ..., 'new_permission'
   ];
   ```
3. **واجهة Flutter**: غلّف العنصر بـ `PermissionsGate` widget:
   ```dart
   PermissionsGate(
     permission: 'new_permission',
     action: PermissionAction.view,
     child: YourWidget(),
   )
   ```

---

## مرجع الملفات الرئيسية

| المهمة | الموقع |
|--------|--------|
| نقطة دخول API وإعداد DI | `src/Backend/API/Sadara.API/Program.cs` |
| جميع الكيانات | `src/Backend/Core/Sadara.Domain/Entities/` |
| جميع الواجهات | `src/Backend/Core/Sadara.Domain/Interfaces/Interfaces.cs` |
| نمط Repository و UnitOfWork | `src/Backend/Core/Sadara.Infrastructure/Repositories/` |
| DbContext و Query Filters | `src/Backend/Core/Sadara.Infrastructure/Data/SadaraDbContext.cs` |
| Seed Data | `src/Backend/Core/Sadara.Infrastructure/Data/SeedData.cs` |
| مصادقة Flutter | `src/Apps/CompanyDesktop/alsadara-ftth/lib/services/unified_auth_manager.dart` |
| API calls Flutter | `src/Apps/CompanyDesktop/alsadara-ftth/lib/services/api_service.dart` |
| صلاحيات Flutter | `src/Apps/CompanyDesktop/alsadara-ftth/lib/services/permissions_service.dart` |
| إعدادات API | `src/Backend/API/Sadara.API/appsettings.json` |

---

## الإعدادات والأسرار

- **مفتاح JWT**: `appsettings.json` ← `Jwt:Secret` (32 حرف على الأقل)
- **PostgreSQL**: `ConnectionStrings:DefaultConnection` (Host=localhost;Port=5432;Database=SadaraDB;...)
- **Firebase**: `secrets/firebase-service-account.json` (للإشعارات والتخزين)
- **مفتاح API الداخلي**: `SADARA_INTERNAL_API_KEY` environment variable (fallback ثابت موجود - مشكلة معروفة)
- **Serilog**: logs تُحفظ في `logs/sadara-YYYYMMDD.log`

---

## معايير التسمية

| النوع | القاعدة | مثال |
|-------|---------|-------|
| Entities | مفرد PascalCase | `User`, `Company`, `ServiceRequest` |
| Controllers | جمع + Controller | `UsersController`, `CompaniesController` |
| ملفات Dart | snake_case | `api_service.dart`, `permissions_service.dart` |
| ملفات C# | PascalCase | `UserService.cs`, `UnitOfWork.cs` |

---

## مشاكل معروفة ومهام للإصلاح

1. **مفتاح API ثابت** في `app_secrets.dart` - يجب استخدام متغيرات البيئة فقط
2. **CORS مفتوح** (`AllowAnyOrigin` في Program.cs) - يجب تقييده في Production
3. **مجلدات الاختبار فارغة** - `tests/Sadara.API.Tests/` تحتاج تنفيذ
4. **ملفات Class1.cs غير مستخدمة** في Domain/Application/Infrastructure - آمنة للحذف
5. **InMemory Database fallback** - يُستخدم إذا لم يكن connection string موجود (للتطوير السريع)

---

## سيرفر النشر

```powershell
# النشر على السيرفر الرئيسي (الوحيد)
cd src/Backend/API/Sadara.API
dotnet publish -c Release -o ../../../../publish-temp
scp -r ../../../../publish-temp/* root@72.61.183.61:/var/www/sadara-api/
ssh root@72.61.183.61 "systemctl restart sadara-api"
```

**⚠️ السيرفر الوحيد للنشر هو `72.61.183.61` — لا تنشر على أي IP آخر**
