# 📖 الملف #1: Program.cs - نقطة بداية التطبيق

## 📍 الموقع
```
src/Backend/API/Sadara.API/Program.cs
```

## 🎯 ما هذا الملف؟

هذا هو **أول ملف يُنفذ** عند تشغيل التطبيق. يمكن تشبيهه بـ "مدير المبنى" الذي:
- يفتح الأبواب (يشغّل الخدمات)
- يوصّل الكهرباء والماء (يربط قاعدة البيانات)
- يضع حراس الأمن (يُعِد المصادقة)
- يستقبل الزوار (يستقبل طلبات HTTP)

---

## 🔍 شرح الكود سطراً سطراً

### 1️⃣ الاستيرادات (using statements)

```csharp
using FluentValidation;                           // للتحقق من صحة البيانات
using Microsoft.AspNetCore.Authentication.JwtBearer;  // للمصادقة بـ JWT
using Microsoft.EntityFrameworkCore;              // للتعامل مع قاعدة البيانات
using Microsoft.IdentityModel.Tokens;             // للتعامل مع التوكنات
using Microsoft.OpenApi.Models;                   // لتوليد وثائق API (Swagger)
using Sadara.Application.DTOs;                    // نماذج نقل البيانات
using Sadara.Application.Services;                // خدمات التطبيق
using Sadara.Domain.Interfaces;                   // الواجهات
using Sadara.Infrastructure.Data;                 // قاعدة البيانات
using Serilog;                                    // لتسجيل الأحداث (Logging)
```

**💡 تشبيه:** هذا مثل قائمة المواد التي تحتاجها لبناء منزل - كل سطر يستورد "مادة" تحتاجها.

---

### 2️⃣ إنشاء التطبيق (Builder Pattern)

```csharp
var builder = WebApplication.CreateBuilder(args);
```

**ماذا يفعل؟** ينشئ "مخطط" التطبيق قبل بنائه.

**💡 تشبيه:** مثل رسم مخطط المنزل قبل البناء الفعلي.

---

### 3️⃣ إعداد Serilog (تسجيل الأحداث)

```csharp
Log.Logger = new LoggerConfiguration()
    .ReadFrom.Configuration(builder.Configuration)  // قراءة الإعدادات
    .Enrich.FromLogContext()                        // إضافة معلومات السياق
    .WriteTo.Console()                              // طباعة في الـ Console
    .WriteTo.File("logs/sadara-.log",               // حفظ في ملف
        rollingInterval: RollingInterval.Day)       // ملف جديد كل يوم
    .CreateLogger();

builder.Host.UseSerilog();
```

**ماذا يفعل؟** يُعِد نظام تسجيل الأحداث لتتبع ما يحدث في التطبيق.

**💡 تشبيه:** مثل كاميرات المراقبة في المبنى - تسجل كل شيء يحدث.

**مثال على ما يُسجَّل:**
```
[14:30:22 INF] User admin@sadara.com logged in
[14:30:25 WRN] Invalid password attempt for user test@test.com
[14:30:30 ERR] Database connection failed
```

---

### 4️⃣ إعداد قاعدة البيانات

```csharp
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection");

if (string.IsNullOrEmpty(connectionString))
{
    // إذا لم يوجد اتصال → استخدم قاعدة بيانات في الذاكرة (للتطوير)
    builder.Services.AddDbContext<SadaraDbContext>(options =>
        options.UseInMemoryDatabase("SadaraDb"));
}
else
{
    // إذا وُجد اتصال → استخدم PostgreSQL (للإنتاج)
    builder.Services.AddDbContext<SadaraDbContext>(options =>
        options.UseNpgsql(connectionString));
}
```

**ماذا يفعل؟** يربط التطبيق بقاعدة البيانات.

**💡 تشبيه:** 
- **InMemoryDatabase** = دفتر ملاحظات مؤقت (يُمسح عند إيقاف التطبيق)
- **PostgreSQL** = خزنة دائمة (البيانات تبقى محفوظة)

---

### 5️⃣ تسجيل الخدمات (Dependency Injection)

```csharp
// نمط Repository و Unit of Work
builder.Services.AddScoped<IUnitOfWork, UnitOfWork>();

// خدمات الهوية
builder.Services.AddScoped<IPasswordHasher, PasswordHasher>();
builder.Services.AddScoped<IJwtService>(sp => new JwtService(...));

// خدمات التطبيق
builder.Services.AddScoped<IAuthService, AuthService>();
builder.Services.AddScoped<ICustomerService, CustomerService>();
```

**ماذا يفعل؟** يُخبر التطبيق "عندما يطلب أحد IAuthService، أعطه AuthService".

**💡 تشبيه:** مثل دليل الهاتف:
- تبحث عن "طبيب" (Interface) → يعطيك "د. أحمد" (Implementation)
- تبحث عن "مهندس" (Interface) → يعطيك "م. سارة" (Implementation)

**أنواع التسجيل:**
| النوع | المعنى | مثال |
|-------|--------|------|
| `AddScoped` | نسخة جديدة لكل طلب HTTP | معظم الخدمات |
| `AddSingleton` | نسخة واحدة للتطبيق كله | إعدادات، Cache |
| `AddTransient` | نسخة جديدة كل مرة | عمليات خفيفة |

---

### 6️⃣ إعداد JWT (المصادقة)

```csharp
var jwtSecret = builder.Configuration["Jwt:Secret"];
var key = Encoding.ASCII.GetBytes(jwtSecret);

builder.Services.AddAuthentication(options =>
{
    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
})
.AddJwtBearer(options =>
{
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuerSigningKey = true,   // تحقق من التوقيع
        IssuerSigningKey = new SymmetricSecurityKey(key),
        ValidateIssuer = true,              // تحقق من المُصدِر
        ValidIssuer = "SadaraPlatform",
        ValidateAudience = true,            // تحقق من الجمهور
        ValidAudience = "SadaraClients",
        ValidateLifetime = true,            // تحقق من انتهاء الصلاحية
        ClockSkew = TimeSpan.Zero           // بدون تسامح في الوقت
    };
});
```

**ماذا يفعل؟** يُعِد نظام التحقق من هوية المستخدمين.

**💡 تشبيه:** مثل بطاقة الدخول للمبنى:
- **Secret** = الختم السري للشركة
- **Issuer** = من أصدر البطاقة
- **Audience** = لمن البطاقة
- **Lifetime** = تاريخ انتهاء البطاقة

**كيف يعمل JWT؟**
```
1. المستخدم يسجل دخول (username + password)
2. الخادم يُنشئ توكن JWT ويُرسله
3. المستخدم يُرسل التوكن مع كل طلب
4. الخادم يتحقق من التوكن ويسمح بالوصول
```

---

### 7️⃣ سياسات الصلاحيات (Authorization Policies)

```csharp
builder.Services.AddAuthorization(options =>
{
    // المدير الأعلى فقط
    options.AddPolicy("SuperAdmin", policy => 
        policy.RequireRole("SuperAdmin"));
    
    // مدير الشركة أو أعلى
    options.AddPolicy("CompanyAdminOrAbove", policy => 
        policy.RequireRole("SuperAdmin", "CompanyAdmin"));
    
    // مدير أو أعلى
    options.AddPolicy("ManagerOrAbove", policy => 
        policy.RequireRole("SuperAdmin", "CompanyAdmin", "Manager"));
    
    // موظف شركة
    options.AddPolicy("CompanyEmployee", policy => 
        policy.RequireRole("SuperAdmin", "CompanyAdmin", "Manager", 
                          "TechnicalLeader", "Technician", "Employee", "Viewer"));
});
```

**ماذا يفعل؟** يُحدد من يستطيع الوصول لماذا.

**💡 تشبيه:** مثل مستويات الوصول في المبنى:
```
🔴 الطابق السري    → SuperAdmin فقط
🟠 مكتب المدير     → CompanyAdmin أو أعلى  
🟡 غرفة الاجتماعات → Manager أو أعلى
🟢 المكاتب العامة  → أي موظف
```

**الاستخدام في Controller:**
```csharp
[Authorize(Policy = "SuperAdmin")]
public IActionResult DeleteCompany() { ... }  // فقط SuperAdmin

[Authorize(Policy = "CompanyEmployee")]
public IActionResult ViewDashboard() { ... }  // أي موظف
```

---

### 8️⃣ إعداد CORS

```csharp
var allowedOrigins = builder.Configuration
    .GetSection("Security:AllowedOrigins")
    .Get<string[]>();

builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", policy =>
    {
        if (builder.Environment.IsDevelopment())
        {
            // التطوير: السماح لأي مصدر
            policy.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader();
        }
        else
        {
            // الإنتاج: فقط المصادر المحددة
            policy.WithOrigins(allowedOrigins)
                  .AllowAnyMethod()
                  .AllowAnyHeader();
        }
    });
});
```

**ماذا يفعل؟** يتحكم في من يستطيع إرسال طلبات للـ API.

**💡 تشبيه:** مثل قائمة الضيوف المسموح لهم بالدخول:
- **التطوير:** "اسمحوا للجميع بالدخول"
- **الإنتاج:** "فقط من في القائمة"

**لماذا CORS مهم؟**
بدونه، موقع خبيث يمكنه إرسال طلبات باسم المستخدم!

---

### 9️⃣ بناء وتشغيل التطبيق

```csharp
var app = builder.Build();  // بناء التطبيق

// معالج الأخطاء العام
app.Use(async (context, next) =>
{
    try
    {
        await next();
    }
    catch (Exception ex)
    {
        Log.Error(ex, "Unhandled exception");
        context.Response.StatusCode = 500;
        await context.Response.WriteAsJsonAsync(new { error = "Internal server error" });
    }
});

// تفعيل Swagger
app.UseSwagger();
app.UseSwaggerUI();

// تفعيل الأمان
app.UseHttpsRedirection();
app.UseCors("AllowAll");
app.UseAuthentication();  // من أنت؟
app.UseAuthorization();   // ماذا يُسمح لك؟

// ربط الـ Controllers
app.MapControllers();
app.MapHealthChecks("/health");
```

**ترتيب الـ Middleware مهم جداً:**
```
الطلب → CORS → Authentication → Authorization → Controller
                                                      ↓
الاستجابة ← ← ← ← ← ← ← ← ← ← ← ← ← ← ← ← ← ← ← ← ← ←
```

---

### 🔟 تطبيق Migrations وبذر البيانات

```csharp
using (var scope = app.Services.CreateScope())
{
    var context = scope.ServiceProvider.GetRequiredService<SadaraDbContext>();
    
    // تطبيق التحديثات على قاعدة البيانات
    if (!context.Database.IsInMemory())
    {
        await context.Database.MigrateAsync();  // تطبيق Migrations
    }
    else
    {
        await context.Database.EnsureCreatedAsync();  // إنشاء الجداول
    }
    
    // بذر البيانات الأساسية
    await SeedData.SeedAsync(context);
    
    // بذر بيانات تجريبية في التطوير
    if (app.Environment.IsDevelopment())
    {
        await SeedTestDataAsync(context);
    }
}

app.Run();  // 🚀 تشغيل التطبيق!
```

**ماذا يفعل؟**
1. **MigrateAsync** - يُطبق تغييرات الجداول على قاعدة البيانات
2. **SeedAsync** - يُضيف البيانات الأساسية (صلاحيات، خدمات، مدير النظام)
3. **SeedTestDataAsync** - يُضيف بيانات تجريبية للتطوير

---

## 🎯 ملخص

| القسم | الوظيفة |
|-------|---------|
| Serilog | تسجيل الأحداث |
| DbContext | ربط قاعدة البيانات |
| DI Container | تسجيل الخدمات |
| JWT | المصادقة |
| Policies | الصلاحيات |
| CORS | أمان الطلبات |
| Middleware | معالجة الطلبات |
| Seed Data | البيانات الأولية |

---

## ❓ أسئلة للمراجعة

1. ما الفرق بين `AddScoped` و `AddSingleton`؟
2. لماذا نستخدم InMemoryDatabase في التطوير؟
3. ما هو JWT وكيف يعمل؟
4. لماذا ترتيب Middleware مهم؟
5. ما الفرق بين Authentication و Authorization؟

---

## 🔗 الملف التالي

[02_BaseEntity.cs.md](./02_BaseEntity.cs.md) - الكيان الأساسي
