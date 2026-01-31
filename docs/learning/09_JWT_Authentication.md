# 📚 الدرس #9: JWT والمصادقة (Authentication)

## 🎯 ما هي المصادقة؟

**المصادقة (Authentication)** = التحقق من هوية المستخدم.
**التفويض (Authorization)** = التحقق من صلاحياته.

```
Authentication: "من أنت؟"
Authorization: "ماذا يُسمح لك؟"
```

---

## 🔐 ما هو JWT؟

**JWT = JSON Web Token**

```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.
eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4ifQ.
SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
```

**ثلاثة أجزاء مفصولة بنقاط:**

1. **Header** (الرأس): نوع الخوارزمية
2. **Payload** (الحمولة): بيانات المستخدم
3. **Signature** (التوقيع): للتحقق من صحة التوكن

---

## 🏗️ كيف يعمل JWT؟

```
┌─────────────────────────────────────────────────────────────┐
│  1. تسجيل الدخول                                            │
│  POST /api/auth/login                                       │
│  { "phoneNumber": "07700000000", "password": "123456" }     │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  2. الخادم يتحقق من البيانات                                │
│  - البحث عن المستخدم                                        │
│  - التحقق من كلمة المرور                                    │
└────────────────────────┬────────────────────────────────────┘
                         │ ✅ صحيح
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  3. الخادم يُنشئ JWT                                        │
│  {                                                          │
│    "accessToken": "eyJ...",                                │
│    "refreshToken": "abc123...",                            │
│    "expiresAt": "2024-01-15T12:00:00"                       │
│  }                                                          │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  4. العميل يحفظ التوكن                                      │
│  ويُرسله مع كل طلب                                          │
│  Authorization: Bearer eyJ...                               │
└─────────────────────────────────────────────────────────────┘
```

---

## 📦 محتوى JWT (Payload)

```json
{
  "sub": "user-guid-here",           // معرف المستخدم
  "name": "أحمد محمد",                // الاسم
  "phone": "07700000000",            // الهاتف
  "role": "CompanyAdmin",            // الدور
  "companyId": "company-guid",       // معرف الشركة
  "iat": 1705312800,                 // وقت الإصدار
  "exp": 1705316400                  // وقت الانتهاء
}
```

---

## 🔧 إعداد JWT في .NET

### appsettings.json

```json
{
  "Jwt": {
    "Secret": "your-secret-key-at-least-32-characters-long!",
    "Issuer": "SadaraPlatform",
    "Audience": "SadaraClients",
    "AccessTokenExpirationMinutes": 60,
    "RefreshTokenExpirationDays": 7
  }
}
```

### Program.cs

```csharp
// إعداد JWT
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = builder.Configuration["Jwt:Issuer"],
            ValidAudience = builder.Configuration["Jwt:Audience"],
            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(builder.Configuration["Jwt:Secret"]!))
        };
    });

builder.Services.AddAuthorization();

// في Middleware
app.UseAuthentication();
app.UseAuthorization();
```

---

## 🛠️ JwtService - إنشاء التوكن

```csharp
public interface IJwtService
{
    string GenerateAccessToken(User user);
    string GenerateRefreshToken();
    ClaimsPrincipal? ValidateToken(string token);
}

public class JwtService : IJwtService
{
    private readonly IConfiguration _config;

    public JwtService(IConfiguration config)
    {
        _config = config;
    }

    public string GenerateAccessToken(User user)
    {
        var securityKey = new SymmetricSecurityKey(
            Encoding.UTF8.GetBytes(_config["Jwt:Secret"]!));
        
        var credentials = new SigningCredentials(
            securityKey, SecurityAlgorithms.HmacSha256);

        var claims = new[]
        {
            new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new Claim(ClaimTypes.Name, user.FullName),
            new Claim(ClaimTypes.MobilePhone, user.PhoneNumber),
            new Claim(ClaimTypes.Role, user.Role.ToString()),
            new Claim("companyId", user.CompanyId?.ToString() ?? "")
        };

        var token = new JwtSecurityToken(
            issuer: _config["Jwt:Issuer"],
            audience: _config["Jwt:Audience"],
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(
                int.Parse(_config["Jwt:AccessTokenExpirationMinutes"]!)),
            signingCredentials: credentials
        );

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    public string GenerateRefreshToken()
    {
        var randomBytes = new byte[64];
        using var rng = RandomNumberGenerator.Create();
        rng.GetBytes(randomBytes);
        return Convert.ToBase64String(randomBytes);
    }
}
```

---

## 🔄 Access Token vs Refresh Token

### Access Token
- **مدة صلاحية:** قصيرة (1 ساعة)
- **الاستخدام:** إرسال مع كل طلب
- **المحتوى:** بيانات المستخدم

### Refresh Token
- **مدة صلاحية:** طويلة (7 أيام)
- **الاستخدام:** للحصول على Access Token جديد
- **المحتوى:** نص عشوائي فقط

```
┌──────────────────────────────────────────────────────────┐
│  تدفق التوكنات                                           │
│                                                          │
│  تسجيل دخول                                              │
│       │                                                  │
│       ▼                                                  │
│  Access Token (1 ساعة) + Refresh Token (7 أيام)         │
│       │                                                  │
│       ▼                                                  │
│  استخدام Access Token مع كل طلب                         │
│       │                                                  │
│       ▼                                                  │
│  انتهى Access Token؟                                     │
│       │                                                  │
│  نعم  ▼                                                  │
│  إرسال Refresh Token للحصول على Access جديد             │
│       │                                                  │
│  انتهى Refresh Token؟                                    │
│       │                                                  │
│  نعم  ▼                                                  │
│  إعادة تسجيل الدخول                                      │
└──────────────────────────────────────────────────────────┘
```

---

## 📱 استخدام JWT في Flutter

### AuthService

```dart
class AuthService {
  static AuthService? _instance;
  static AuthService get instance => _instance ??= AuthService._internal();

  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;

  Future<bool> login(String phoneNumber, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'phoneNumber': phoneNumber,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      _accessToken = data['accessToken'];
      _refreshToken = data['refreshToken'];
      _expiresAt = DateTime.parse(data['expiresAt']);
      
      // حفظ في التخزين المحلي
      await _saveTokens();
      return true;
    }
    return false;
  }

  Future<http.Response> authenticatedRequest(
    String method,
    String url, {
    Object? body,
  }) async {
    // التحقق من صلاحية التوكن
    if (_isTokenExpired()) {
      await _refreshAccessToken();
    }

    return http.Request(method, Uri.parse(url))
      ..headers['Authorization'] = 'Bearer $_accessToken'
      ..headers['Content-Type'] = 'application/json'
      ..body = body?.toString() ?? '';
  }

  bool _isTokenExpired() {
    if (_expiresAt == null) return true;
    return DateTime.now().isAfter(_expiresAt!.subtract(Duration(minutes: 5)));
  }

  Future<void> _refreshAccessToken() async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/refresh-token'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'refreshToken': _refreshToken}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      _accessToken = data['accessToken'];
      _expiresAt = DateTime.parse(data['expiresAt']);
    } else {
      // Refresh Token منتهي - أعد تسجيل الدخول
      throw AuthException('Session expired');
    }
  }
}
```

---

## 🔒 حماية الـ Endpoints

### في Controller

```csharp
[ApiController]
[Route("api/[controller]")]
public class UsersController : ControllerBase
{
    // 🔓 عام - بدون حماية
    [HttpGet("public")]
    [AllowAnonymous]
    public IActionResult PublicEndpoint() => Ok("Public");

    // 🔐 يتطلب تسجيل دخول
    [HttpGet("protected")]
    [Authorize]
    public IActionResult ProtectedEndpoint() => Ok("Protected");

    // 🔐 يتطلب Role محدد
    [HttpGet("admin-only")]
    [Authorize(Roles = "SuperAdmin,CompanyAdmin")]
    public IActionResult AdminOnly() => Ok("Admin Only");

    // 🔐 يتطلب Policy
    [HttpDelete("{id}")]
    [Authorize(Policy = "CanDeleteUsers")]
    public IActionResult Delete(Guid id) => Ok("Deleted");
}
```

### تعريف Policies

```csharp
// Program.cs
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("CanDeleteUsers", policy =>
        policy.RequireRole("SuperAdmin", "CompanyAdmin"));
    
    options.AddPolicy("IsManager", policy =>
        policy.RequireClaim("role", "Manager", "CompanyAdmin", "SuperAdmin"));
});
```

---

## 🔍 استخراج معلومات المستخدم الحالي

### في Controller

```csharp
[Authorize]
public class BaseController : ControllerBase
{
    protected Guid GetCurrentUserId()
    {
        var claim = User.FindFirst(ClaimTypes.NameIdentifier);
        return Guid.Parse(claim?.Value ?? throw new UnauthorizedAccessException());
    }

    protected string GetCurrentUserRole()
    {
        return User.FindFirst(ClaimTypes.Role)?.Value ?? "";
    }

    protected Guid? GetCurrentCompanyId()
    {
        var claim = User.FindFirst("companyId");
        if (string.IsNullOrEmpty(claim?.Value)) return null;
        return Guid.Parse(claim.Value);
    }
}
```

### الاستخدام

```csharp
[HttpGet("my-orders")]
[Authorize]
public async Task<IActionResult> GetMyOrders()
{
    var userId = GetCurrentUserId();
    var orders = await _unitOfWork.Orders
        .FindAsync(o => o.UserId == userId);
    return Ok(orders);
}
```

---

## 🛡️ أمان إضافي

### 1. تشفير كلمة المرور

```csharp
public class BCryptPasswordHasher : IPasswordHasher
{
    public string HashPassword(string password)
    {
        return BCrypt.Net.BCrypt.HashPassword(password, workFactor: 12);
    }

    public bool VerifyPassword(string password, string hash)
    {
        return BCrypt.Net.BCrypt.Verify(password, hash);
    }
}
```

### 2. قفل الحساب بعد محاولات فاشلة

```csharp
if (!_passwordHasher.VerifyPassword(request.Password, user.PasswordHash))
{
    user.FailedLoginAttempts++;
    
    if (user.FailedLoginAttempts >= 5)
    {
        user.LockoutEnd = DateTime.UtcNow.AddMinutes(30);
        user.FailedLoginAttempts = 0;
    }
    
    await _unitOfWork.SaveChangesAsync();
    return FailResponse("Invalid credentials");
}

// إعادة تعيين عداد المحاولات الفاشلة
user.FailedLoginAttempts = 0;
```

### 3. HTTPS فقط

```csharp
// Program.cs (Production)
if (!app.Environment.IsDevelopment())
{
    app.UseHsts();
    app.UseHttpsRedirection();
}
```

---

## 📝 تمارين

1. **أضف Claim** لـ `department` في JWT
2. **أنشئ Policy** تتطلب أن يكون المستخدم من قسم "IT"
3. **فكر:** لماذا Secret Key يجب أن يكون طويلاً؟

---

## 🔗 الدرس التالي

[10_Citizen_Portal.md](./10_Citizen_Portal.md) - بوابة المواطن (Blazor PWA)
