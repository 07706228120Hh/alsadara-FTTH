# 📚 الدرس #4: طبقة API - Controllers و Endpoints

## 🎯 ما هي طبقة API؟

**طبقة API** هي **نقطة الدخول** للتطبيق:
- تستقبل طلبات HTTP من Flutter/Blazor
- تُعالج الطلبات وتُرسل الردود
- تتحقق من الصلاحيات (Authorization)

---

## 📁 هيكل المجلد

```
src/Backend/API/Sadara.API/
├── Program.cs              ← نقطة البداية
├── appsettings.json        ← الإعدادات
│
├── Controllers/            ← Controllers
│   ├── AuthController.cs   ← المصادقة
│   ├── UsersController.cs  ← المستخدمون
│   ├── CompaniesController.cs
│   └── ...
│
├── DTOs/                   ← Data Transfer Objects
│   ├── UserDto.cs
│   ├── LoginRequest.cs
│   └── ...
│
└── citizen_portal/         ← ملفات Blazor PWA
```

---

## 🎮 Controller - المتحكم

### ما هو Controller؟

**Controller** = موظف استقبال في فندق:
- يستقبل الطلبات
- يوجهها للخدمة المناسبة
- يُرجع الرد للعميل

### مثال بسيط: `AuthController.cs`

```csharp
[ApiController]
[Route("api/[controller]")]  // المسار: /api/auth
public class AuthController : ControllerBase
{
    private readonly IAuthService _authService;

    // Dependency Injection
    public AuthController(IAuthService authService)
    {
        _authService = authService;
    }

    // POST /api/auth/login
    [HttpPost("login")]
    public async Task<IActionResult> Login([FromBody] LoginRequest request)
    {
        var result = await _authService.LoginAsync(request);
        
        if (result.Success)
            return Ok(result);      // 200 OK
        else
            return BadRequest(result);  // 400 Bad Request
    }

    // POST /api/auth/register
    [HttpPost("register")]
    public async Task<IActionResult> Register([FromBody] RegisterRequest request)
    {
        var result = await _authService.RegisterAsync(request);
        return result.Success ? Ok(result) : BadRequest(result);
    }
}
```

### 💡 شرح الـ Attributes

| Attribute | الوظيفة |
|-----------|---------|
| `[ApiController]` | يُخبر .NET أن هذا Controller لـ API |
| `[Route("api/[controller]")]` | المسار = `/api/auth` |
| `[HttpGet]` | يستجيب لـ GET requests |
| `[HttpPost]` | يستجيب لـ POST requests |
| `[HttpPut]` | يستجيب لـ PUT requests |
| `[HttpDelete]` | يستجيب لـ DELETE requests |
| `[FromBody]` | يقرأ البيانات من body الطلب |
| `[FromQuery]` | يقرأ من query string |
| `[Authorize]` | يتطلب تسجيل دخول |

---

## 🔗 HTTP Methods و CRUD

```
┌──────────────────────────────────────────────────────────┐
│   HTTP Method  │   العملية   │        المثال             │
├──────────────────────────────────────────────────────────┤
│   GET          │   Read      │  GET /api/users          │
│   POST         │   Create    │  POST /api/users         │
│   PUT          │   Update    │  PUT /api/users/123      │
│   DELETE       │   Delete    │  DELETE /api/users/123   │
└──────────────────────────────────────────────────────────┘
```

### مثال عملي: `UsersController.cs`

```csharp
[ApiController]
[Route("api/[controller]")]
public class UsersController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;

    public UsersController(IUnitOfWork unitOfWork)
    {
        _unitOfWork = unitOfWork;
    }

    // GET /api/users - جلب الكل
    [HttpGet]
    [Authorize(Policy = "Admin")]  // فقط Admin
    public async Task<IActionResult> GetAll(
        [FromQuery] int page = 1, 
        [FromQuery] int pageSize = 20)
    {
        var users = await _unitOfWork.Users
            .AsQueryable()
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        return Ok(new { success = true, data = users });
    }

    // GET /api/users/{id} - جلب واحد
    [HttpGet("{id:guid}")]
    [Authorize]
    public async Task<IActionResult> GetById(Guid id)
    {
        var user = await _unitOfWork.Users.GetByIdAsync(id);
        
        if (user == null)
            return NotFound(new { success = false, message = "المستخدم غير موجود" });

        return Ok(new { success = true, data = user });
    }

    // PUT /api/users/{id} - تحديث
    [HttpPut("{id:guid}")]
    [Authorize]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateUserRequest request)
    {
        var user = await _unitOfWork.Users.GetByIdAsync(id);
        if (user == null)
            return NotFound(new { success = false, message = "المستخدم غير موجود" });

        user.FullName = request.FullName ?? user.FullName;
        user.Email = request.Email ?? user.Email;
        user.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Users.Update(user);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم التحديث" });
    }
}
```

---

## 📦 DTOs - Data Transfer Objects

### ما هو DTO؟

**DTO** = صندوق يحتوي البيانات المُرسلة/المستلمة.

```csharp
// ❌ سيء - إرسال Entity مباشرة (يكشف كل البيانات!)
return Ok(user);  // يرسل PasswordHash أيضاً!

// ✅ جيد - استخدام DTO (يرسل المطلوب فقط)
return Ok(new UserDto
{
    Id = user.Id,
    FullName = user.FullName,
    Email = user.Email
    // PasswordHash لا يُرسل!
});
```

### أنواع DTOs

```csharp
// Request DTO - ما يُرسله العميل
public class LoginRequest
{
    public string PhoneNumber { get; set; }
    public string Password { get; set; }
}

// Response DTO - ما يُرجعه الخادم
public class UserDto
{
    public Guid Id { get; set; }
    public string FullName { get; set; }
    public string Email { get; set; }
    public string Role { get; set; }
    public bool IsActive { get; set; }
}
```

---

## 🔒 Authorization - الصلاحيات

### أنواع الحماية

```csharp
// 1. يتطلب تسجيل دخول فقط
[Authorize]
public async Task<IActionResult> GetProfile() { }

// 2. يتطلب Role معين
[Authorize(Roles = "SuperAdmin")]
public async Task<IActionResult> DeleteCompany() { }

// 3. يتطلب Policy معينة
[Authorize(Policy = "Admin")]
public async Task<IActionResult> GetAllUsers() { }

// 4. بدون حماية (عام)
[AllowAnonymous]
public async Task<IActionResult> Login() { }
```

### تعريف Policy في Program.cs

```csharp
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("Admin", policy =>
        policy.RequireRole("SuperAdmin", "CompanyAdmin"));
    
    options.AddPolicy("Employee", policy =>
        policy.RequireRole("SuperAdmin", "CompanyAdmin", "Employee"));
});
```

---

## 📡 HTTP Status Codes

### الردود الشائعة

| الكود | المعنى | الاستخدام |
|-------|--------|-----------|
| 200 | OK | نجاح العملية |
| 201 | Created | تم الإنشاء |
| 204 | No Content | نجاح بدون محتوى |
| 400 | Bad Request | خطأ في البيانات |
| 401 | Unauthorized | غير مسجل دخول |
| 403 | Forbidden | لا يملك صلاحية |
| 404 | Not Found | غير موجود |
| 500 | Server Error | خطأ في الخادم |

### في الكود

```csharp
return Ok(result);           // 200
return Created(uri, obj);    // 201
return NoContent();          // 204
return BadRequest(error);    // 400
return Unauthorized();       // 401
return Forbid();             // 403
return NotFound();           // 404
```

---

## 🗂️ قائمة Controllers في المشروع

| Controller | الملف | الوظيفة |
|------------|-------|---------|
| `AuthController` | AuthController.cs | المصادقة (تسجيل/دخول) |
| `UsersController` | UsersController.cs | إدارة المستخدمين |
| `CompaniesController` | CompaniesController.cs | إدارة الشركات |
| `OrdersController` | OrdersController.cs | إدارة الطلبات |
| `PaymentsController` | PaymentsController.cs | المدفوعات |
| `CustomersController` | CustomersController.cs | العملاء |
| `ProductsController` | ProductsController.cs | المنتجات |
| `DashboardController` | DashboardController.cs | الإحصائيات |
| `SuperAdminController` | SuperAdminController.cs | مدير النظام |
| `CitizenPortalController` | CitizenPortalController.cs | بوابة المواطن |
| `InternalDataController` | InternalDataController.cs | بيانات داخلية |
| `DatabaseAdminController` | DatabaseAdminController.cs | إدارة قاعدة البيانات |

---

## 🔄 تدفق الطلب الكامل

```
┌──────────────────────────────────────────────────────────────┐
│  Flutter App                                                  │
│  POST /api/auth/login                                        │
│  Body: { "phoneNumber": "07700000000", "password": "123" }   │
└───────────────────────────┬──────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────┐
│  ASP.NET Core Middleware                                      │
│  - CORS Check                                                │
│  - Authentication (JWT)                                       │
│  - Authorization                                              │
└───────────────────────────┬──────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────┐
│  AuthController.Login()                                       │
│  - يستلم LoginRequest                                        │
│  - يُمرر لـ AuthService                                       │
└───────────────────────────┬──────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────┐
│  AuthService.LoginAsync()                                     │
│  - يبحث عن المستخدم                                          │
│  - يتحقق من كلمة المرور                                      │
│  - يُنشئ JWT Token                                            │
└───────────────────────────┬──────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────┐
│  Response                                                     │
│  { "success": true, "token": "eyJ...", "user": {...} }       │
└──────────────────────────────────────────────────────────────┘
```

---

## ➕ كيف تضيف Controller جديد؟

### الخطوة 1: أنشئ الملف

```csharp
// Controllers/InvoicesController.cs
[ApiController]
[Route("api/[controller]")]
public class InvoicesController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;

    public InvoicesController(IUnitOfWork unitOfWork)
    {
        _unitOfWork = unitOfWork;
    }

    [HttpGet]
    [Authorize]
    public async Task<IActionResult> GetAll()
    {
        var invoices = await _unitOfWork.Invoices.GetAllAsync();
        return Ok(new { success = true, data = invoices });
    }
}
```

### الخطوة 2: اختبر

```bash
# من المتصفح أو Postman
GET http://localhost:5000/api/invoices
```

---

## 📝 تمارين

1. **افتح `AuthController.cs`** - ما الـ endpoints المتاحة؟
2. **افتح `UsersController.cs`** - كيف يتم Pagination؟
3. **فكر:** لماذا `GetByPhone` ليس لديه `[Authorize]`؟

---

## 🔗 الدرس التالي

[05_Application_Layer.md](./05_Application_Layer.md) - طبقة Application (Services)
