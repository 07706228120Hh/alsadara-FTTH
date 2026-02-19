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

// Identity Services
builder.Services.AddScoped<IPasswordHasher, PasswordHasher>();
builder.Services.AddScoped<IJwtService>(sp => new JwtService(
    builder.Configuration["Jwt:Secret"] ?? "YourSuperSecretKeyThatIsAtLeast32CharactersLong!",
    builder.Configuration["Jwt:Issuer"] ?? "SadaraPlatform",
    builder.Configuration["Jwt:Audience"] ?? "SadaraClients",
    int.Parse(builder.Configuration["Jwt:ExpiryMinutes"] ?? "60")
));

// SMS Service (Mock)
builder.Services.AddScoped<ISmsService, MockSmsService>();

// Firebase Admin Service
builder.Services.AddHttpClient<IFirebaseAdminService, FirebaseAdminService>();

// VPS Control Service
builder.Services.AddScoped<IVpsControlService, VpsControlService>();

// Application Services
builder.Services.AddScoped<IAuthService, AuthService>();
builder.Services.AddScoped<ICustomerService, CustomerService>();
builder.Services.AddScoped<IOrderService, OrderService>();

// AutoMapper
builder.Services.AddAutoMapper(typeof(MappingProfile));

// FluentValidation
builder.Services.AddValidatorsFromAssemblyContaining<LoginRequestValidator>();

// JWT Authentication
var jwtSecret = builder.Configuration["Jwt:Secret"] ?? "YourSuperSecretKeyThatIsAtLeast32CharactersLong!";
var key = Encoding.ASCII.GetBytes(jwtSecret);

builder.Services.AddAuthentication(options =>
{
    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
})
.AddJwtBearer(options =>
{
    options.RequireHttpsMetadata = false;
    options.SaveToken = true;
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuerSigningKey = true,
        IssuerSigningKey = new SymmetricSecurityKey(key),
        ValidateIssuer = true,
        ValidIssuer = builder.Configuration["Jwt:Issuer"] ?? "SadaraPlatform",
        ValidateAudience = true,
        ValidAudience = builder.Configuration["Jwt:Audience"] ?? "SadaraClients",
        ValidateLifetime = true,
        ClockSkew = TimeSpan.Zero
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
        policy.RequireRole("SuperAdmin", "CompanyAdmin", "Manager", "TechnicalLeader", "Technician"));
    
    // موظف شركة (أي موظف داخل شركة)
    options.AddPolicy("CompanyEmployee", policy => 
        policy.RequireRole("SuperAdmin", "CompanyAdmin", "Manager", "TechnicalLeader", "Technician", "Employee", "Viewer"));
    
    // سياسات قديمة للتوافق مع E-commerce
    options.AddPolicy("Admin", policy => policy.RequireRole("SuperAdmin", "Admin"));
    options.AddPolicy("Merchant", policy => policy.RequireRole("SuperAdmin", "Admin", "Merchant"));
});

// CORS - تم تقييده للأمان
var allowedOrigins = builder.Configuration.GetSection("Security:AllowedOrigins").Get<string[]>() 
    ?? new[] { "http://localhost:5000" };

builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", policy =>
    {
        // السماح لجميع الأصول (Flutter Web يعمل على منافذ مختلفة)
        policy.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader();
    });
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

// Enable Swagger in all environments
app.UseSwagger();
app.UseSwaggerUI(c =>
{
    c.SwaggerEndpoint("/swagger/v1/swagger.json", "Sadara API v1");
    c.RoutePrefix = "swagger";
});

app.UseHttpsRedirection();
app.UseCors("AllowAll");

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
app.MapHealthChecks("/health");

// Apply migrations and seed data
using (var scope = app.Services.CreateScope())
{
    var context = scope.ServiceProvider.GetRequiredService<SadaraDbContext>();
    
    // Apply pending migrations only in Development (production uses manual SQL migrations)
    if (context.Database.IsInMemory())
    {
        await context.Database.EnsureCreatedAsync();
    }
    else if (app.Environment.IsDevelopment())
    {
        await context.Database.MigrateAsync();
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
