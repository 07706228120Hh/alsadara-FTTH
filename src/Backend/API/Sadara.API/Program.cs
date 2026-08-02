using FluentValidation;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using Sadara.Application.DTOs;
using Sadara.Application.Interfaces;
using Sadara.Application.Mapping;
using Sadara.Application.Services;
using Sadara.Application.Validators;
using Sadara.Domain.Interfaces;
using Sadara.Infrastructure.Data;
using Sadara.Infrastructure.Identity;
using Sadara.Infrastructure.Repositories;
using Sadara.Infrastructure.Services.Firebase;
using Sadara.Infrastructure.Services.Server;
using Serilog;
using System.Text;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.ResponseCompression;

var builder = WebApplication.CreateBuilder(args);

// Configure Serilog
Log.Logger = new LoggerConfiguration()
    .ReadFrom.Configuration(builder.Configuration)
    .Enrich.FromLogContext()
    .WriteTo.Console()
    .WriteTo.File("logs/sadara-.log", rollingInterval: RollingInterval.Day)
    .CreateLogger();

builder.Host.UseSerilog();

// Database Context
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection");
if (string.IsNullOrEmpty(connectionString))
{
    builder.Services.AddDbContext<SadaraDbContext>(options =>
        options.UseInMemoryDatabase("SadaraDb"));
}
else
{
    builder.Services.AddDbContext<SadaraDbContext>(options =>
        options.UseNpgsql(connectionString)
            .ConfigureWarnings(w => w.Ignore(Microsoft.EntityFrameworkCore.Diagnostics.RelationalEventId.PendingModelChangesWarning)));
}

// Repositories
builder.Services.AddScoped<IUnitOfWork, UnitOfWork>();

// عزل المستأجر: مزوّد الشركة الحالية (يقرأ company_id من التوكن؛ SuperAdmin يتجاوز)
builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<ICurrentTenant, Sadara.API.Services.CurrentTenant>();

// Identity Services
builder.Services.AddScoped<IPasswordHasher, PasswordHasher>();

// ═══ ADR-002: اختيار خوارزمية توقيع JWT عبر إعداد Jwt:Algorithm (يبدأ OFF = HS256) ═══
// الافتراضي HS256 ⇒ نفس مسار الإنتاج الحالي حرفياً (لا تغيير سلوك). RS256 قدرة إضافية خلف flag.
var jwtAlgorithm = (builder.Configuration["Jwt:Algorithm"] ?? "HS256").Trim().ToUpperInvariant();

// المفتاح الخاص RS256 يُقرأ من مسار ملف خارجي فقط (متغيّر بيئة/إعداد) — لا يُخزَّن في appsettings*.json.
// اسم المتغيّر: Jwt:Rs256PrivateKeyPath (مثلاً من env var Jwt__Rs256PrivateKeyPath). null = غير مهيّأ.
var rs256PrivateKeyPath = builder.Configuration["Jwt:Rs256PrivateKeyPath"];
Rs256JwtService? rs256SingletonForJwks = null;

// ADR-003 خطوة 0 («إثبات»): المكوّن المشترك للتوقيع. هو وحده من يقرّر الخوارزمية (HS256 افتراضياً / RS256 خلف flag).
// عند HS256 يبقى إصدار التوكن مطابقاً بنيوياً للحالي (بلا kid). RS256 يُضيف kid فقط.
builder.Services.AddSingleton<IJwtTokenSigner, JwtTokenSigner>();

if (jwtAlgorithm == "RS256")
{
    // fail-closed: RS256 يتطلب مسار مفتاح خاص صالح وموجود، وإلا نرفض بدل السقوط الصامت إلى HS256.
    if (string.IsNullOrWhiteSpace(rs256PrivateKeyPath) || !File.Exists(rs256PrivateKeyPath))
        throw new InvalidOperationException(
            "Jwt:Algorithm=RS256 لكن Jwt:Rs256PrivateKeyPath غير مضبوط أو الملف غير موجود — fail-closed.");

    var rs256Pem = File.ReadAllText(rs256PrivateKeyPath);
    var rs256Issuer = builder.Configuration["Jwt:Issuer"] ?? "SadaraPlatform";
    var rs256Audience = builder.Configuration["Jwt:Audience"] ?? "SadaraClients";
    var rs256Expiry = int.Parse(builder.Configuration["Jwt:ExpiryMinutes"] ?? "60");
    var rs256KeyId = builder.Configuration["Jwt:Rs256KeyId"]; // اختياري

    // نبني نسخة singleton لخدمة JWKS (نشر المفتاح العام) وللتحقّق (RS256). لم تعُد تُسجَّل كـ IJwtService —
    // المكوّن المشترك (IJwtTokenSigner) وحده يقرّر خوارزمية التوقيع الآن.
    rs256SingletonForJwks = new Rs256JwtService(rs256Pem, rs256Issuer, rs256Audience, rs256Expiry, rs256KeyId);
}

// ADR-003 خطوة 0: JwtService هو دائماً تنفيذ IJwtService؛ خوارزمية التوقيع يقرّرها IJwtTokenSigner المُحقَن.
builder.Services.AddScoped<IJwtService>(sp => new JwtService(
    sp.GetRequiredService<IJwtTokenSigner>(),
    builder.Configuration["Jwt:Secret"] ?? throw new InvalidOperationException("Jwt:Secret غير مضبوط — fail-closed."),
    builder.Configuration["Jwt:Issuer"] ?? "SadaraPlatform",
    builder.Configuration["Jwt:Audience"] ?? "SadaraClients",
    int.Parse(builder.Configuration["Jwt:ExpiryMinutes"] ?? "60")
));

// ═══ ADR-002: خدمة JWKS. عند HS256/OFF أو غياب مفتاح RS256 ⇒ { "keys": [] } (لا توليد تلقائي). ═══
builder.Services.AddSingleton(new JwksService(rs256SingletonForJwks));

// SMS Service (Mock)
builder.Services.AddScoped<ISmsService, MockSmsService>();

// Firebase Admin Service
builder.Services.AddHttpClient<IFirebaseAdminService, FirebaseAdminService>();
builder.Services.AddHttpClient();

// FCM Push Notification Service
builder.Services.AddSingleton<IFcmNotificationService, FcmNotificationService>();

// Task Hub Notifier — إشعارات المهام عبر SignalR
builder.Services.AddSingleton<Sadara.API.Hubs.TaskHubNotifier>();

// VPS Control Service
builder.Services.AddScoped<IVpsControlService, VpsControlService>();

// Application Services
builder.Services.AddScoped<IAuthService, AuthService>();
builder.Services.AddScoped<ICustomerService, CustomerService>();
builder.Services.AddScoped<IOrderService, OrderService>();

// FTTH Sync Background Service (مزامنة FTTH تلقائية)
builder.Services.AddHostedService<Sadara.API.Services.FtthSyncBackgroundService>();

// AutoMapper
builder.Services.AddAutoMapper(typeof(MappingProfile));

// FluentValidation
builder.Services.AddValidatorsFromAssemblyContaining<LoginRequestValidator>();

// JWT Authentication
// fail-closed: Jwt:Secret مطلوب — نرفض بدل السقوط الصامت. يُمرَّر كما هو إلى JwtValidationParametersFactory
// الذي يُشفّره بـ UTF8 (يطابق مسار التوقيع JwtTokenSigner؛ محايد للسرّ الحالي ASCII ويزيل قنبلة المحارف غير ASCII).
var jwtSecret = builder.Configuration["Jwt:Secret"] ?? throw new InvalidOperationException("Jwt:Secret غير مضبوط — fail-closed.");

builder.Services.AddAuthentication(options =>
{
    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
})
.AddJwtBearer(options =>
{
    options.RequireHttpsMetadata = !builder.Environment.IsDevelopment();
    options.SaveToken = true;

    // ═══ ADR-003 خطوة أ: التشغيل المزدوج للتحقّق (Dual-verify) — التوقيع يبقى حسب Jwt:Algorithm (افتراضي HS256). ═══
    // التحقّق يقبل الخوارزميتين معاً استعداداً للانتقال إلى RS256، بلا تفعيل التوقيع RS256.
    //
    // بناء البارامترات صار في مصنع ثابت قابل للاختبار (JwtValidationParametersFactory) يستدعيه
    // Program.cs والاختبار الأمني معاً — فيغطّي اختبار alg confusion المسار الإنتاجي الفعلي بدل إعادة بنائه.
    //
    // المفتاح العام RS256 يُمرَّر فقط إن كان مهيّأً (rs256SingletonForJwks ≠ null، أي Jwt:Algorithm=RS256 مع مفتاح صالح).
    // لا نولّد مفتاحاً هنا؛ نعيد استخدام نفس singleton المستهلَك من JwksService (مصدر واحد للمفتاح العام).
    // عند OFF أو غياب مفتاح RS256 ⇒ HS256 فقط ⇒ السلوك مطابق للحالي.
    var rs256PublicKey = rs256SingletonForJwks is not null
        ? new RsaSecurityKey(rs256SingletonForJwks.ExportPublicKeyParameters())
        {
            KeyId = rs256SingletonForJwks.KeyId
        }
        : null;

    options.TokenValidationParameters = JwtValidationParametersFactory.Build(
        jwtSecret,
        builder.Configuration["Jwt:Issuer"] ?? "SadaraPlatform",
        builder.Configuration["Jwt:Audience"] ?? "SadaraClients",
        rs256PublicKey);

    // ═══ SignalR: قراءة JWT من query string لاتصالات WebSocket ═══
    options.Events = new JwtBearerEvents
    {
        OnMessageReceived = context =>
        {
            var accessToken = context.Request.Query["access_token"];
            var path = context.HttpContext.Request.Path;
            if (!string.IsNullOrEmpty(accessToken) && path.StartsWithSegments("/hubs"))
            {
                context.Token = accessToken;
            }
            return Task.CompletedTask;
        },

        // إثراء انتقالي: التوكنات القديمة قد لا تحمل company_id. إن غاب، نشتقّه من قاعدة البيانات
        // مرة واحدة (بتجاوز فلتر العزل) حتى لا تنكسر جلسات المستخدمين الحاليين عند تفعيل عزل الشركات.
        OnTokenValidated = async context =>
        {
            var identity = context.Principal?.Identity as System.Security.Claims.ClaimsIdentity;
            if (identity == null) return;

            if (identity.FindFirst("company_id") != null || identity.FindFirst("companyId") != null)
                return;

            var userIdStr = identity.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value
                         ?? identity.FindFirst("sub")?.Value;
            if (!Guid.TryParse(userIdStr, out var userId)) return;

            var db = context.HttpContext.RequestServices.GetService<SadaraDbContext>();
            if (db == null) return;

            var companyId = await db.Users
                .IgnoreQueryFilters()
                .Where(u => u.Id == userId && !u.IsDeleted)
                .Select(u => u.CompanyId)
                .FirstOrDefaultAsync();

            if (companyId.HasValue && companyId.Value != Guid.Empty)
                identity.AddClaim(new System.Security.Claims.Claim("company_id", companyId.Value.ToString()));
        }
    };
});

builder.Services.AddAuthorization(options =>
{
    // مستويات الصلاحيات الهرمية (مطابق لنظام Flutter)
    
    // المدير الأعلى فقط - للتحكم الكامل بالسيرفر والنظام
    options.AddPolicy("SuperAdmin", policy => policy.RequireRole("SuperAdmin"));
    options.AddPolicy("SuperAdminOnly", policy => policy.RequireRole("SuperAdmin"));
    
    // مدير الشركة أو أعلى (SuperAdmin, CompanyAdmin)
    options.AddPolicy("CompanyAdminOrAbove", policy => 
        policy.RequireRole("SuperAdmin", "CompanyAdmin"));
    
    // مدير أو أعلى (SuperAdmin, CompanyAdmin, Manager)
    options.AddPolicy("ManagerOrAbove", policy => 
        policy.RequireRole("SuperAdmin", "CompanyAdmin", "Manager"));
    
    // قائد تقني أو أعلى
    options.AddPolicy("TechnicalLeaderOrAbove", policy => 
        policy.RequireRole("SuperAdmin", "CompanyAdmin", "Manager", "TechnicalLeader"));
    
    // فني أو أعلى
    options.AddPolicy("TechnicianOrAbove", policy =>
        policy.RequireRole("SuperAdmin", "CompanyAdmin", "Manager", "TechnicalLeader", "Technician", "Employee"));
    
    // موظف شركة (أي موظف داخل شركة)
    options.AddPolicy("CompanyEmployee", policy => 
        policy.RequireRole("SuperAdmin", "CompanyAdmin", "Manager", "TechnicalLeader", "Technician", "Employee", "Viewer"));
    
    // سياسات قديمة للتوافق مع E-commerce + HR
    options.AddPolicy("Admin", policy => policy.RequireRole("SuperAdmin", "Admin", "CompanyAdmin", "Manager", "TechnicalLeader", "Technician", "Employee"));
    options.AddPolicy("Merchant", policy => policy.RequireRole("SuperAdmin", "Admin", "Merchant"));
});

// CORS
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", policy =>
    {
        policy.AllowAnyOrigin()
            .AllowAnyMethod()
            .AllowAnyHeader();
    });
});

// Rate Limiting
builder.Services.AddRateLimiter(options =>
{
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: context.Connection.RemoteIpAddress?.ToString() ?? "anonymous",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 600,
                Window = TimeSpan.FromMinutes(1),
                QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
                QueueLimit = 50
            }));
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
});

// Response Compression
builder.Services.AddResponseCompression(options =>
{
    options.EnableForHttps = true;
    options.Providers.Add<GzipCompressionProvider>();
});

builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.PropertyNamingPolicy = null; // Keep original case
        options.JsonSerializerOptions.PropertyNameCaseInsensitive = true;
        options.JsonSerializerOptions.Converters.Add(new System.Text.Json.Serialization.JsonStringEnumConverter());
    });
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "Sadara Platform API",
        Version = "v1",
        Description = "Enterprise-grade API for Sadara Platform"
    });

    c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Description = "JWT Authorization header. Enter 'Bearer' [space] and your token",
        Name = "Authorization",
        In = ParameterLocation.Header,
        Type = SecuritySchemeType.ApiKey,
        Scheme = "Bearer"
    });

    c.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference
                {
                    Type = ReferenceType.SecurityScheme,
                    Id = "Bearer"
                }
            },
            Array.Empty<string>()
        }
    });
});

builder.Services.AddHealthChecks();

// SignalR — بث مباشر لمواقع الموظفين
builder.Services.AddSignalR(options =>
{
    options.EnableDetailedErrors = true;
    options.KeepAliveInterval = TimeSpan.FromSeconds(15);
});

var app = builder.Build();

// Global Exception Handler
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
        await context.Response.WriteAsJsonAsync(new ApiResponse<object>(false, "Internal server error", null, new[] { ex.Message }));
    }
});

// Swagger - Development only
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(c =>
    {
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "Sadara API v1");
        c.RoutePrefix = "swagger";
    });
}

app.UseCors("AllowAll");
app.UseHttpsRedirection();
app.UseResponseCompression();
app.UseRateLimiter();

// خدمة بوابة المواطن (Citizen Portal) كملفات ثابتة
var citizenPortalPath = Path.Combine(AppContext.BaseDirectory, "citizen_portal");
if (Directory.Exists(citizenPortalPath))
{
    app.UseStaticFiles(new StaticFileOptions
    {
        FileProvider = new Microsoft.Extensions.FileProviders.PhysicalFileProvider(citizenPortalPath),
        RequestPath = "/portal"
    });
    // SPA fallback for citizen portal routes
    app.MapFallbackToFile("/portal/{**slug}", "index.html", new StaticFileOptions
    {
        FileProvider = new Microsoft.Extensions.FileProviders.PhysicalFileProvider(citizenPortalPath)
    });
}

app.UseAuthentication();
app.UseAuthorization();
app.UseSerilogRequestLogging();

app.MapControllers();
app.MapHub<Sadara.API.Hubs.LocationHub>("/hubs/location");
app.MapHub<Sadara.API.Hubs.ChatHub>("/hubs/chat");
app.MapHub<Sadara.API.Hubs.TaskHub>("/hubs/tasks");
app.MapHealthChecks("/health");

// ═══ ADR-002: نقطة JWKS لنشر المفتاح العام RS256. ═══
// عند HS256/OFF أو غياب مفتاح RS256 مهيّأ ⇒ { "keys": [] } (لا توليد تلقائي، لا كشف سرّ HS256).
app.MapGet("/.well-known/jwks.json", (JwksService jwks) => Results.Json(jwks.GetJwks()))
    .AllowAnonymous();

// Apply migrations and seed data
using (var scope = app.Services.CreateScope())
{
    var context = scope.ServiceProvider.GetRequiredService<SadaraDbContext>();
    
    // Apply pending migrations only in Development (production uses manual SQL migrations)
    if (context.Database.IsInMemory())
    {
        await context.Database.EnsureCreatedAsync();
    }
    else
    {
        try { await context.Database.MigrateAsync(); }
        catch (Exception ex) { Console.WriteLine($"Migration note: {ex.Message}"); }
    }
    
    // Seed core data (permissions, services, operation types, super admin)
    await SeedData.SeedAsync(context);
    
    // Seed test data in development
    if (app.Environment.IsDevelopment())
    {
        await SeedTestDataAsync(context);
    }
}

Log.Information("Sadara Platform API starting on http://localhost:5000");
app.Run();

static async Task SeedTestDataAsync(SadaraDbContext context)
{
    if (await context.Users.AnyAsync())
        return;

    var passwordHasher = new PasswordHasher();

    // Super Admin
    var superAdmin = new Sadara.Domain.Entities.User
    {
        Id = Guid.NewGuid(),
        FullName = "Super Admin",
        PhoneNumber = "+9647801234567",
        Email = "admin@sadara.com",
        PasswordHash = passwordHasher.HashPassword("Admin@123"),
        Role = Sadara.Domain.Enums.UserRole.SuperAdmin,
        IsActive = true,
        IsPhoneVerified = true
    };

    // Merchant User
    var merchantUser = new Sadara.Domain.Entities.User
    {
        Id = Guid.NewGuid(),
        FullName = "Test Merchant",
        PhoneNumber = "+9647809876543",
        Email = "merchant@test.com",
        PasswordHash = passwordHasher.HashPassword("Merchant@123"),
        Role = Sadara.Domain.Enums.UserRole.Merchant,
        IsActive = true,
        IsPhoneVerified = true
    };

    await context.Users.AddRangeAsync(superAdmin, merchantUser);

    // Merchant
    var merchant = new Sadara.Domain.Entities.Merchant
    {
        Id = Guid.NewGuid(),
        UserId = merchantUser.Id,
        BusinessName = "Test Store",
        BusinessNameAr = "متجر تجريبي",
        Description = "A test merchant store",
        City = "Baghdad",
        Area = "Karrada",
        PhoneNumber = merchantUser.PhoneNumber,
        Email = merchantUser.Email,
        SubscriptionPlan = Sadara.Domain.Enums.SubscriptionPlan.Pro,
        MaxCustomers = 50000,
        CommissionRate = 3.5m,
        IsActive = true,
        IsVerified = true
    };

    await context.Merchants.AddAsync(merchant);

    // Customers
    var customers = Enumerable.Range(1, 5).Select(i => new Sadara.Domain.Entities.Customer
    {
        MerchantId = merchant.Id,
        CustomerCode = $"C{i:D6}",
        FullName = $"Customer {i}",
        PhoneNumber = $"+9647700000{i:D3}",
        City = "Baghdad",
        Area = i % 2 == 0 ? "Mansour" : "Karrada",
        Type = i <= 2 ? Sadara.Domain.Enums.CustomerType.VIP : Sadara.Domain.Enums.CustomerType.Regular,
        IsActive = true
    }).ToList();

    await context.Customers.AddRangeAsync(customers);

    // Products
    var products = new[]
    {
        new Sadara.Domain.Entities.Product
        {
            Id = Guid.NewGuid(),
            MerchantId = merchant.Id,
            Name = "Product 1",
            NameAr = "منتج 1",
            SKU = "SKU001",
            Price = 25000,
            CostPrice = 20000,
            StockQuantity = 100,
            IsAvailable = true
        },
        new Sadara.Domain.Entities.Product
        {
            Id = Guid.NewGuid(),
            MerchantId = merchant.Id,
            Name = "Product 2",
            NameAr = "منتج 2",
            SKU = "SKU002",
            Price = 50000,
            CostPrice = 35000,
            StockQuantity = 50,
            IsAvailable = true,
            IsFeatured = true
        }
    };

    await context.Products.AddRangeAsync(products);

    // AppVersion
    var appVersion = new Sadara.Domain.Entities.AppVersion
    {
        Platform = "Android",
        Version = "1.0.0",
        MinVersion = "1.0.0",
        ForceUpdate = false,
        ReleaseNotes = "Initial release",
        IsActive = true
    };

    await context.AppVersions.AddAsync(appVersion);

    // Advertising
    var advertising = new Sadara.Domain.Entities.Advertising
    {
        Title = "Welcome to Sadara",
        Type = "Banner",
        IsActive = true,
        SortOrder = 1
    };

    await context.Advertisings.AddAsync(advertising);

    await context.SaveChangesAsync();
    Log.Information("Test data seeded successfully");
}

// Mock SMS Service
public class MockSmsService : ISmsService
{
    private readonly ILogger<MockSmsService> _logger;

    public MockSmsService(ILogger<MockSmsService> logger)
    {
        _logger = logger;
    }

    public Task<bool> SendSmsAsync(string phoneNumber, string message)
    {
        _logger.LogInformation("SMS to {PhoneNumber}: {Message}", phoneNumber, message);
        return Task.FromResult(true);
    }
}
