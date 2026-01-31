# 📚 الدرس #5: طبقة Application - الخدمات ومنطق العمل

## 🎯 ما هي طبقة Application؟

**طبقة Application** تحتوي على **منطق العمل (Business Logic)**:
- Services - الخدمات
- DTOs - نماذج البيانات
- Validators - التحقق من البيانات
- Interfaces - الواجهات

**💡 هذه الطبقة تعرف "كيف" يعمل التطبيق.**

---

## 📁 هيكل المجلد

```
src/Backend/Core/Sadara.Application/
├── DTOs/               ← نماذج البيانات
│   ├── UserDto.cs
│   ├── LoginRequest.cs
│   └── ...
│
├── Interfaces/         ← الواجهات
│   ├── IFirebaseAdminService.cs
│   └── IVpsControlService.cs
│
├── Services/           ← الخدمات
│   └── Services.cs     ← كل الخدمات
│
├── Validators/         ← التحقق من البيانات
│   └── ...
│
└── Mapping/            ← AutoMapper
    └── ...
```

---

## 🔧 Service - الخدمة

### ما هي Service؟

**Service** = موظف متخصص يقوم بمهمة محددة.

```
Controller = موظف الاستقبال (يستلم الطلب)
Service = الموظف المختص (يُنفذ العمل)
Repository = المخزن (يجلب/يحفظ البيانات)
```

### مثال: `AuthService`

```csharp
public interface IAuthService
{
    Task<ApiResponse<LoginResponse>> LoginAsync(LoginRequest request);
    Task<ApiResponse<LoginResponse>> RegisterAsync(RegisterRequest request);
    Task<ApiResponse<bool>> ForgotPasswordAsync(ForgotPasswordRequest request);
}

public class AuthService : IAuthService
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly IPasswordHasher _passwordHasher;
    private readonly IJwtService _jwtService;
    private readonly ISmsService _smsService;

    public AuthService(
        IUnitOfWork unitOfWork,
        IPasswordHasher passwordHasher,
        IJwtService jwtService,
        ISmsService smsService)
    {
        _unitOfWork = unitOfWork;
        _passwordHasher = passwordHasher;
        _jwtService = jwtService;
        _smsService = smsService;
    }

    public async Task<ApiResponse<LoginResponse>> LoginAsync(LoginRequest request)
    {
        // 1. البحث عن المستخدم
        var user = await _unitOfWork.Users
            .FirstOrDefaultAsync(u => u.PhoneNumber == request.PhoneNumber);
        
        if (user == null)
            return ApiResponse<LoginResponse>.FailResponse("بيانات خاطئة");

        // 2. التحقق من كلمة المرور
        if (!_passwordHasher.VerifyPassword(request.Password, user.PasswordHash))
            return ApiResponse<LoginResponse>.FailResponse("بيانات خاطئة");

        // 3. التحقق من الحساب
        if (!user.IsActive)
            return ApiResponse<LoginResponse>.FailResponse("الحساب معطل");

        // 4. إنشاء Token
        var accessToken = _jwtService.GenerateAccessToken(user);
        var refreshToken = _jwtService.GenerateRefreshToken();
        
        user.RefreshToken = refreshToken;
        user.LastLoginAt = DateTime.UtcNow;
        await _unitOfWork.SaveChangesAsync();

        // 5. إرجاع النتيجة
        return ApiResponse<LoginResponse>.SuccessResponse(
            new LoginResponse(accessToken, refreshToken, user),
            "تم تسجيل الدخول");
    }
}
```

---

## 🎭 Interface و Implementation

### لماذا نستخدم Interface؟

```csharp
// Interface = العقد
public interface IAuthService
{
    Task<ApiResponse<LoginResponse>> LoginAsync(LoginRequest request);
}

// Implementation = التنفيذ
public class AuthService : IAuthService
{
    public async Task<ApiResponse<LoginResponse>> LoginAsync(LoginRequest request)
    {
        // الكود الفعلي
    }
}
```

**الفوائد:**
1. **الاختبار:** يمكن إنشاء Mock للاختبارات
2. **المرونة:** يمكن تبديل التنفيذ بدون تغيير الكود
3. **الفصل:** Controller لا يعرف تفاصيل التنفيذ

### 💡 تشبيه

```
Interface = قائمة الطعام في المطعم
Implementation = المطبخ الذي يُحضر الطعام

أنت تطلب من القائمة، لا تهتم كيف يُحضر في المطبخ!
```

---

## 📦 DTOs - نماذج البيانات

### Request DTOs (ما يُرسله العميل)

```csharp
public class LoginRequest
{
    [Required]
    public string PhoneNumber { get; set; }
    
    [Required]
    [MinLength(6)]
    public string Password { get; set; }
    
    public string? DeviceId { get; set; }
    public string? DeviceInfo { get; set; }
}

public class RegisterRequest
{
    [Required]
    public string FullName { get; set; }
    
    [Required]
    [Phone]
    public string PhoneNumber { get; set; }
    
    [Required]
    [MinLength(6)]
    public string Password { get; set; }
    
    public string? Email { get; set; }
    public UserRole Role { get; set; } = UserRole.Citizen;
}
```

### Response DTOs (ما يُرجعه الخادم)

```csharp
public class UserDto
{
    public Guid Id { get; set; }
    public string FullName { get; set; }
    public string PhoneNumber { get; set; }
    public string? Email { get; set; }
    public string Role { get; set; }
    public bool IsActive { get; set; }
}

public class LoginResponse
{
    public string AccessToken { get; set; }
    public string RefreshToken { get; set; }
    public DateTime ExpiresAt { get; set; }
    public UserDto User { get; set; }
}
```

### ApiResponse - رد موحد

```csharp
public class ApiResponse<T>
{
    public bool Success { get; set; }
    public string Message { get; set; }
    public T? Data { get; set; }
    public IEnumerable<string>? Errors { get; set; }

    public static ApiResponse<T> SuccessResponse(T data, string message = "Success")
    {
        return new ApiResponse<T>
        {
            Success = true,
            Message = message,
            Data = data
        };
    }

    public static ApiResponse<T> FailResponse(string message, IEnumerable<string>? errors = null)
    {
        return new ApiResponse<T>
        {
            Success = false,
            Message = message,
            Errors = errors
        };
    }
}
```

**الاستخدام:**
```csharp
// نجاح
return ApiResponse<UserDto>.SuccessResponse(userDto, "تم بنجاح");
// Response: { "success": true, "message": "تم بنجاح", "data": {...} }

// فشل
return ApiResponse<UserDto>.FailResponse("خطأ", ["الحقل مطلوب"]);
// Response: { "success": false, "message": "خطأ", "errors": ["الحقل مطلوب"] }
```

---

## ✅ Validators - التحقق من البيانات

### باستخدام FluentValidation

```csharp
public class LoginRequestValidator : AbstractValidator<LoginRequest>
{
    public LoginRequestValidator()
    {
        RuleFor(x => x.PhoneNumber)
            .NotEmpty().WithMessage("رقم الهاتف مطلوب")
            .Length(11).WithMessage("رقم الهاتف يجب أن يكون 11 رقم")
            .Matches(@"^07\d{9}$").WithMessage("رقم الهاتف غير صحيح");

        RuleFor(x => x.Password)
            .NotEmpty().WithMessage("كلمة المرور مطلوبة")
            .MinimumLength(6).WithMessage("كلمة المرور قصيرة جداً");
    }
}
```

### الاستخدام في Service

```csharp
public class AuthService : IAuthService
{
    private readonly IValidator<LoginRequest> _loginValidator;

    public async Task<ApiResponse<LoginResponse>> LoginAsync(LoginRequest request)
    {
        // التحقق أولاً
        var validation = await _loginValidator.ValidateAsync(request);
        
        if (!validation.IsValid)
        {
            return ApiResponse<LoginResponse>.FailResponse(
                "خطأ في البيانات", 
                validation.Errors.Select(e => e.ErrorMessage));
        }

        // باقي المنطق...
    }
}
```

---

## 🗺️ AutoMapper - تحويل البيانات

### ما هو AutoMapper؟

يحول من Entity إلى DTO تلقائياً:

```csharp
// بدون AutoMapper (يدوي)
var userDto = new UserDto
{
    Id = user.Id,
    FullName = user.FullName,
    PhoneNumber = user.PhoneNumber,
    Email = user.Email,
    Role = user.Role.ToString(),
    IsActive = user.IsActive
};

// مع AutoMapper (سطر واحد)
var userDto = _mapper.Map<UserDto>(user);
```

### التكوين

```csharp
// Mapping/MappingProfile.cs
public class MappingProfile : Profile
{
    public MappingProfile()
    {
        CreateMap<User, UserDto>()
            .ForMember(d => d.Role, opt => opt.MapFrom(s => s.Role.ToString()));
        
        CreateMap<RegisterRequest, User>();
        
        CreateMap<Company, CompanyDto>();
    }
}
```

---

## 🔄 تدفق Service كامل

```
┌─────────────────────────────────────────────────────────┐
│                    Controller                           │
│  var result = await _authService.LoginAsync(request);  │
└───────────────────────────┬─────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                    AuthService                          │
│  1. Validation (FluentValidation)                      │
│  2. Find User (Repository)                             │
│  3. Verify Password (PasswordHasher)                   │
│  4. Generate Token (JwtService)                        │
│  5. Save Changes (UnitOfWork)                          │
│  6. Map to DTO (AutoMapper)                            │
│  7. Return ApiResponse                                 │
└───────────────────────────┬─────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                    ApiResponse                          │
│  { success: true, data: { token, user } }              │
└─────────────────────────────────────────────────────────┘
```

---

## 🔧 الخدمات المساعدة

### قائمة الخدمات في المشروع

| الخدمة | الوظيفة |
|--------|---------|
| `IAuthService` | المصادقة (تسجيل/دخول) |
| `IJwtService` | إنشاء وتحقق JWT |
| `IPasswordHasher` | تشفير كلمات المرور |
| `ISmsService` | إرسال SMS |
| `IFirebaseAdminService` | Firebase Admin |
| `IVpsControlService` | التحكم بالخادم |

### تسجيل الخدمات في Program.cs

```csharp
// Services
builder.Services.AddScoped<IAuthService, AuthService>();
builder.Services.AddScoped<IJwtService, JwtService>();
builder.Services.AddSingleton<IPasswordHasher, BCryptPasswordHasher>();
builder.Services.AddScoped<ISmsService, DummySmsService>();

// Validators
builder.Services.AddValidatorsFromAssemblyContaining<LoginRequestValidator>();

// AutoMapper
builder.Services.AddAutoMapper(typeof(MappingProfile));
```

---

## ➕ كيف تضيف Service جديدة؟

### الخطوة 1: أنشئ Interface

```csharp
// Interfaces/IInvoiceService.cs
public interface IInvoiceService
{
    Task<ApiResponse<InvoiceDto>> CreateAsync(CreateInvoiceRequest request);
    Task<ApiResponse<InvoiceDto>> GetByIdAsync(Guid id);
    Task<ApiResponse<IEnumerable<InvoiceDto>>> GetAllAsync();
}
```

### الخطوة 2: أنشئ Implementation

```csharp
// Services/InvoiceService.cs
public class InvoiceService : IInvoiceService
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly IMapper _mapper;

    public InvoiceService(IUnitOfWork unitOfWork, IMapper mapper)
    {
        _unitOfWork = unitOfWork;
        _mapper = mapper;
    }

    public async Task<ApiResponse<InvoiceDto>> CreateAsync(CreateInvoiceRequest request)
    {
        var invoice = _mapper.Map<Invoice>(request);
        await _unitOfWork.Invoices.AddAsync(invoice);
        await _unitOfWork.SaveChangesAsync();
        return ApiResponse<InvoiceDto>.SuccessResponse(_mapper.Map<InvoiceDto>(invoice));
    }
}
```

### الخطوة 3: سجّل في Program.cs

```csharp
builder.Services.AddScoped<IInvoiceService, InvoiceService>();
```

---

## 📝 تمارين

1. **افتح `Services.cs`** - كم خدمة موجودة؟
2. **ابحث عن `LoginAsync`** - ما خطوات التحقق؟
3. **فكر:** لماذا `PasswordHash` لا يُرسل في `UserDto`؟

---

## 🔗 الدرس التالي

[06_Flutter_App.md](./06_Flutter_App.md) - تطبيق Flutter Desktop
