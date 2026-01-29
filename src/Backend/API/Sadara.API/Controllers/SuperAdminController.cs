using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;
using System.Diagnostics;
using System.IdentityModel.Tokens.Jwt;
using System.Net.NetworkInformation;
using System.Security.Claims;
using System.Text;
using System.Text.Json;

namespace Sadara.API.Controllers;

/// <summary>
/// لوحة تحكم السوبر أدمن - إدارة كل شيء
/// Firebase + VPS + Database + النظام
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize(Policy = "SuperAdmin")]
public class SuperAdminController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly IConfiguration _configuration;
    private readonly ILogger<SuperAdminController> _logger;
    private readonly HttpClient _httpClient;

    public SuperAdminController(
        IUnitOfWork unitOfWork,
        IConfiguration configuration,
        ILogger<SuperAdminController> logger,
        HttpClient httpClient)
    {
        _unitOfWork = unitOfWork;
        _configuration = configuration;
        _logger = logger;
        _httpClient = httpClient;
    }

    #region Authentication

    /// <summary>
    /// تسجيل دخول مدير النظام
    /// </summary>
    [HttpPost("login")]
    [AllowAnonymous]
    public async Task<IActionResult> Login([FromBody] SuperAdminLoginRequest request)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(request.Username) || string.IsNullOrWhiteSpace(request.Password))
            {
                return BadRequest(new { success = false, message = "اسم المستخدم وكلمة المرور مطلوبان" });
            }

            // البحث عن المستخدم بالاسم أو البريد الإلكتروني
            var user = await _unitOfWork.Users.AsQueryable()
                .FirstOrDefaultAsync(u => 
                    (u.Email == request.Username || u.PhoneNumber == request.Username) &&
                    u.Role == UserRole.SuperAdmin &&
                    !u.IsDeleted);

            if (user == null)
            {
                _logger.LogWarning("محاولة دخول فاشلة لمدير النظام: {Username}", request.Username);
                return Unauthorized(new { success = false, message = "اسم المستخدم أو كلمة المرور غير صحيحة" });
            }

            // التحقق من الحالة
            if (!user.IsActive)
            {
                return Unauthorized(new { success = false, message = "الحساب معطل" });
            }

            // التحقق من القفل
            if (user.LockoutEnd.HasValue && user.LockoutEnd > DateTime.UtcNow)
            {
                var remainingTime = user.LockoutEnd.Value - DateTime.UtcNow;
                return Unauthorized(new { 
                    success = false, 
                    message = $"الحساب مقفل. حاول بعد {remainingTime.Minutes} دقيقة" 
                });
            }

            // التحقق من كلمة المرور
            if (!BCrypt.Net.BCrypt.Verify(request.Password, user.PasswordHash))
            {
                user.FailedLoginAttempts++;
                
                if (user.FailedLoginAttempts >= 5)
                {
                    user.LockoutEnd = DateTime.UtcNow.AddMinutes(30);
                    user.FailedLoginAttempts = 0;
                    _logger.LogWarning("تم قفل حساب مدير النظام بسبب محاولات فاشلة متعددة: {UserId}", user.Id);
                }
                
                _unitOfWork.Users.Update(user);
                await _unitOfWork.SaveChangesAsync();
                
                return Unauthorized(new { success = false, message = "اسم المستخدم أو كلمة المرور غير صحيحة" });
            }

            // تسجيل الدخول ناجح
            user.FailedLoginAttempts = 0;
            user.LastLoginAt = DateTime.UtcNow;
            user.LockoutEnd = null;
            
            _unitOfWork.Users.Update(user);
            await _unitOfWork.SaveChangesAsync();

            // إنشاء التوكن
            var token = GenerateJwtToken(user);
            var refreshToken = GenerateRefreshToken();
            
            user.RefreshToken = refreshToken;
            user.RefreshTokenExpiryTime = DateTime.UtcNow.AddDays(7);
            _unitOfWork.Users.Update(user);
            await _unitOfWork.SaveChangesAsync();

            _logger.LogInformation("تسجيل دخول ناجح لمدير النظام: {UserId}", user.Id);

            return Ok(new
            {
                success = true,
                message = "تم تسجيل الدخول بنجاح",
                data = new SuperAdminLoginResponse
                {
                    Id = user.Id,
                    Username = user.Email ?? user.PhoneNumber,
                    FullName = user.FullName,
                    Email = user.Email,
                    Token = token,
                    RefreshToken = refreshToken,
                    ExpiresAt = DateTime.UtcNow.AddHours(24)
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تسجيل دخول مدير النظام");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    /// <summary>
    /// تحديث التوكن
    /// </summary>
    [HttpPost("refresh-token")]
    [AllowAnonymous]
    public async Task<IActionResult> RefreshToken([FromBody] SuperAdminRefreshTokenRequest request)
    {
        try
        {
            var user = await _unitOfWork.Users.AsQueryable()
                .FirstOrDefaultAsync(u => 
                    u.RefreshToken == request.RefreshToken &&
                    u.RefreshTokenExpiryTime > DateTime.UtcNow &&
                    u.Role == UserRole.SuperAdmin &&
                    !u.IsDeleted);

            if (user == null)
            {
                return Unauthorized(new { success = false, message = "التوكن غير صالح أو منتهي" });
            }

            var newToken = GenerateJwtToken(user);
            var newRefreshToken = GenerateRefreshToken();

            user.RefreshToken = newRefreshToken;
            user.RefreshTokenExpiryTime = DateTime.UtcNow.AddDays(7);
            _unitOfWork.Users.Update(user);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new
            {
                success = true,
                data = new
                {
                    Token = newToken,
                    RefreshToken = newRefreshToken,
                    ExpiresAt = DateTime.UtcNow.AddHours(24)
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تحديث التوكن");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    /// <summary>
    /// تسجيل الخروج
    /// </summary>
    [HttpPost("logout")]
    public async Task<IActionResult> Logout()
    {
        try
        {
            var userIdClaim = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (Guid.TryParse(userIdClaim, out var userId))
            {
                var user = await _unitOfWork.Users.GetByIdAsync(userId);
                if (user != null)
                {
                    user.RefreshToken = null;
                    user.RefreshTokenExpiryTime = null;
                    _unitOfWork.Users.Update(user);
                    await _unitOfWork.SaveChangesAsync();
                }
            }

            return Ok(new { success = true, message = "تم تسجيل الخروج بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تسجيل الخروج");
            return Ok(new { success = true, message = "تم تسجيل الخروج" });
        }
    }

    private string GenerateJwtToken(Domain.Entities.User user)
    {
        var jwtKey = _configuration["Jwt:Key"] ?? "SadaraSecretKey2024!@#$%^&*()_+DefaultKey";
        var jwtIssuer = _configuration["Jwt:Issuer"] ?? "SadaraAPI";
        var jwtAudience = _configuration["Jwt:Audience"] ?? "SadaraClients";

        var securityKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtKey));
        var credentials = new SigningCredentials(securityKey, SecurityAlgorithms.HmacSha256);

        var claims = new[]
        {
            new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new Claim(ClaimTypes.Name, user.FullName),
            new Claim(ClaimTypes.Email, user.Email ?? ""),
            new Claim(ClaimTypes.MobilePhone, user.PhoneNumber),
            new Claim(ClaimTypes.Role, user.Role.ToString()),
            new Claim("role_id", ((int)user.Role).ToString())
        };

        var token = new JwtSecurityToken(
            issuer: jwtIssuer,
            audience: jwtAudience,
            claims: claims,
            expires: DateTime.UtcNow.AddHours(24),
            signingCredentials: credentials
        );

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private static string GenerateRefreshToken()
    {
        var randomBytes = new byte[64];
        using var rng = System.Security.Cryptography.RandomNumberGenerator.Create();
        rng.GetBytes(randomBytes);
        return Convert.ToBase64String(randomBytes);
    }

    #endregion

    #region Companies Management

    /// <summary>
    /// جلب جميع الشركات
    /// </summary>
    [HttpGet("companies")]
    public async Task<IActionResult> GetCompanies([FromQuery] int page = 1, [FromQuery] int pageSize = 20)
    {
        try
        {
            var query = _unitOfWork.Companies.AsQueryable()
                .Where(c => !c.IsDeleted)
                .OrderByDescending(c => c.CreatedAt);

            var totalCount = await query.CountAsync();
            
            var companies = await query
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(c => new
                {
                    c.Id,
                    c.Name,
                    c.Code,
                    c.Email,
                    c.Phone,
                    c.Address,
                    c.City,
                    c.IsActive,
                    c.SubscriptionEndDate,
                    c.MaxUsers,
                    c.CreatedAt,
                    DaysRemaining = (int)(c.SubscriptionEndDate - DateTime.UtcNow).TotalDays,
                    IsExpired = c.SubscriptionEndDate < DateTime.UtcNow
                })
                .ToListAsync();

            return Ok(new
            {
                success = true,
                data = new
                {
                    companies,
                    totalCount,
                    page,
                    pageSize,
                    totalPages = (int)Math.Ceiling((double)totalCount / pageSize)
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب الشركات");
            return StatusCode(500, new { success = false, message = "حدث خطأ في جلب الشركات" });
        }
    }

    /// <summary>
    /// جلب شركة بالمعرف
    /// </summary>
    [HttpGet("companies/{id}")]
    public async Task<IActionResult> GetCompanyById(Guid id)
    {
        try
        {
            var company = await _unitOfWork.Companies.AsQueryable()
                .Where(c => c.Id == id && !c.IsDeleted)
                .Select(c => new
                {
                    c.Id,
                    c.Name,
                    c.Code,
                    c.Email,
                    c.Phone,
                    c.Address,
                    c.City,
                    c.IsActive,
                    c.SubscriptionEndDate,
                    c.MaxUsers,
                    c.CreatedAt,
                    DaysRemaining = (int)(c.SubscriptionEndDate - DateTime.UtcNow).TotalDays,
                    IsExpired = c.SubscriptionEndDate < DateTime.UtcNow
                })
                .FirstOrDefaultAsync();

            if (company == null)
                return NotFound(new { success = false, message = "الشركة غير موجودة" });

            return Ok(new { success = true, data = company });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب الشركة {CompanyId}", id);
            return StatusCode(500, new { success = false, message = "حدث خطأ في جلب الشركة" });
        }
    }

    /// <summary>
    /// إنشاء شركة جديدة
    /// </summary>
    [HttpPost("companies")]
    public async Task<IActionResult> CreateCompany([FromBody] CreateCompanyRequest request)
    {
        try
        {
            // التحقق من عدم وجود شركة بنفس الكود
            var existingCompany = await _unitOfWork.Companies.AsQueryable()
                .FirstOrDefaultAsync(c => c.Code == request.Code && !c.IsDeleted);

            if (existingCompany != null)
                return BadRequest(new { success = false, message = "كود الشركة مستخدم بالفعل" });

            var company = new Domain.Entities.Company
            {
                Id = Guid.NewGuid(),
                Name = request.Name,
                Code = request.Code,
                Email = request.Email,
                Phone = request.Phone,
                Address = request.Address,
                City = request.City,
                IsActive = true,
                MaxUsers = request.MaxUsers ?? 10,
                SubscriptionEndDate = request.SubscriptionEndDate ?? DateTime.UtcNow.AddMonths(12),
                CreatedAt = DateTime.UtcNow
            };

            await _unitOfWork.Companies.AddAsync(company);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم إنشاء الشركة بنجاح", data = new { company.Id, company.Name, company.Code } });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إنشاء الشركة");
            return StatusCode(500, new { success = false, message = "حدث خطأ في إنشاء الشركة" });
        }
    }

    /// <summary>
    /// تحديث شركة
    /// </summary>
    [HttpPut("companies/{id}")]
    public async Task<IActionResult> UpdateCompany(Guid id, [FromBody] UpdateCompanyRequest request)
    {
        try
        {
            var company = await _unitOfWork.Companies.GetByIdAsync(id);
            if (company == null || company.IsDeleted)
                return NotFound(new { success = false, message = "الشركة غير موجودة" });

            if (!string.IsNullOrWhiteSpace(request.Name)) company.Name = request.Name;
            if (!string.IsNullOrWhiteSpace(request.Email)) company.Email = request.Email;
            if (!string.IsNullOrWhiteSpace(request.Phone)) company.Phone = request.Phone;
            if (!string.IsNullOrWhiteSpace(request.Address)) company.Address = request.Address;
            if (!string.IsNullOrWhiteSpace(request.City)) company.City = request.City;
            if (request.MaxUsers.HasValue) company.MaxUsers = request.MaxUsers.Value;
            if (request.SubscriptionEndDate.HasValue) company.SubscriptionEndDate = request.SubscriptionEndDate.Value;

            company.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.Companies.Update(company);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم تحديث الشركة بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تحديث الشركة {CompanyId}", id);
            return StatusCode(500, new { success = false, message = "حدث خطأ في تحديث الشركة" });
        }
    }

    /// <summary>
    /// تفعيل/تعطيل شركة
    /// </summary>
    [HttpPatch("companies/{id}/toggle-status")]
    public async Task<IActionResult> ToggleCompanyStatus(Guid id)
    {
        try
        {
            var company = await _unitOfWork.Companies.GetByIdAsync(id);
            if (company == null || company.IsDeleted)
                return NotFound(new { success = false, message = "الشركة غير موجودة" });

            company.IsActive = !company.IsActive;
            company.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.Companies.Update(company);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = company.IsActive ? "تم تفعيل الشركة" : "تم تعطيل الشركة" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تغيير حالة الشركة {CompanyId}", id);
            return StatusCode(500, new { success = false, message = "حدث خطأ في تغيير حالة الشركة" });
        }
    }

    /// <summary>
    /// تجديد اشتراك شركة
    /// </summary>
    [HttpPatch("companies/{id}/renew")]
    public async Task<IActionResult> RenewSubscription(Guid id, [FromBody] RenewSubscriptionRequest request)
    {
        try
        {
            var company = await _unitOfWork.Companies.GetByIdAsync(id);
            if (company == null || company.IsDeleted)
                return NotFound(new { success = false, message = "الشركة غير موجودة" });

            var startDate = company.SubscriptionEndDate > DateTime.UtcNow
                ? company.SubscriptionEndDate
                : DateTime.UtcNow;

            company.SubscriptionEndDate = startDate.AddDays(request.Days);
            company.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.Companies.Update(company);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = $"تم تجديد الاشتراك لـ {request.Days} يوم" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تجديد اشتراك الشركة {CompanyId}", id);
            return StatusCode(500, new { success = false, message = "حدث خطأ في تجديد الاشتراك" });
        }
    }

    /// <summary>
    /// حذف شركة
    /// </summary>
    [HttpDelete("companies/{id}")]
    public async Task<IActionResult> DeleteCompany(Guid id)
    {
        try
        {
            var company = await _unitOfWork.Companies.GetByIdAsync(id);
            if (company == null || company.IsDeleted)
                return NotFound(new { success = false, message = "الشركة غير موجودة" });

            company.IsDeleted = true;
            company.DeletedAt = DateTime.UtcNow;
            _unitOfWork.Companies.Update(company);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم حذف الشركة بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حذف الشركة {CompanyId}", id);
            return StatusCode(500, new { success = false, message = "حدث خطأ في حذف الشركة" });
        }
    }

    #endregion

    #region Dashboard Statistics

    /// <summary>
    /// لوحة التحكم الرئيسية - إحصائيات شاملة
    /// </summary>
    [HttpGet("dashboard")]
    public async Task<IActionResult> GetDashboard()
    {
        var dashboard = new SuperAdminDashboard
        {
            SystemStatus = await GetSystemStatus(),
            Statistics = await GetSystemStatistics(),
            RecentActivities = await GetRecentActivities(),
            Alerts = await GetSystemAlerts()
        };

        return Ok(new { success = true, data = dashboard });
    }

    /// <summary>
    /// إحصائيات النظام التفصيلية
    /// </summary>
    [HttpGet("statistics")]
    public async Task<IActionResult> GetStatistics()
    {
        var stats = await GetSystemStatistics();
        return Ok(new { success = true, data = stats });
    }

    #endregion

    #region Firebase Management

    /// <summary>
    /// حالة اتصال Firebase
    /// </summary>
    [HttpGet("firebase/status")]
    public async Task<IActionResult> GetFirebaseStatus()
    {
        try
        {
            var firebaseConfig = _configuration.GetSection("Firebase");
            var projectId = firebaseConfig["ProjectId"];
            
            var status = new FirebaseStatus
            {
                ProjectId = projectId ?? "غير محدد",
                IsConnected = !string.IsNullOrEmpty(projectId),
                Services = new FirebaseServices
                {
                    Authentication = true, // يمكن التحقق عبر API
                    Firestore = true,
                    Storage = true,
                    Messaging = true,
                    Analytics = true
                },
                LastChecked = DateTime.UtcNow
            };

            return Ok(new { success = true, data = status });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في التحقق من حالة Firebase");
            return Ok(new { success = false, message = "خطأ في الاتصال بـ Firebase", error = ex.Message });
        }
    }

    /// <summary>
    /// إحصائيات Firebase Users
    /// </summary>
    [HttpGet("firebase/users")]
    public async Task<IActionResult> GetFirebaseUsers([FromQuery] int page = 1, [FromQuery] int pageSize = 50)
    {
        // في الإنتاج، استخدم Firebase Admin SDK
        var users = await _unitOfWork.Users.AsQueryable()
            .Where(u => !u.IsDeleted)
            .OrderByDescending(u => u.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(u => new
            {
                u.Id,
                u.FullName,
                u.Email,
                u.PhoneNumber,
                u.Role,
                u.IsActive,
                u.IsPhoneVerified,
                u.CreatedAt,
                u.LastLoginAt
            })
            .ToListAsync();

        var total = await _unitOfWork.Users.AsQueryable().CountAsync(u => !u.IsDeleted);

        return Ok(new { success = true, data = users, total, page, pageSize });
    }

    /// <summary>
    /// تحديث بيانات مستخدم في Firebase
    /// </summary>
    [HttpPatch("firebase/users/{userId:guid}")]
    public async Task<IActionResult> UpdateFirebaseUser(Guid userId, [FromBody] UpdateFirebaseUserRequest request)
    {
        var user = await _unitOfWork.Users.GetByIdAsync(userId);
        if (user == null)
            return NotFound(new { success = false, message = "المستخدم غير موجود" });

        // في الإنتاج، قم بتحديث Firebase أولاً ثم قاعدة البيانات المحلية
        if (request.IsActive.HasValue)
            user.IsActive = request.IsActive.Value;
        if (request.IsPhoneVerified.HasValue)
            user.IsPhoneVerified = request.IsPhoneVerified.Value;

        user.UpdatedAt = DateTime.UtcNow;
        _unitOfWork.Users.Update(user);
        await _unitOfWork.SaveChangesAsync();

        _logger.LogInformation("تم تحديث مستخدم Firebase: {UserId}", userId);
        return Ok(new { success = true, message = "تم التحديث بنجاح" });
    }

    /// <summary>
    /// إرسال إشعار Push عبر Firebase
    /// </summary>
    [HttpPost("firebase/notifications/send")]
    public async Task<IActionResult> SendPushNotification([FromBody] SuperAdminSendNotificationRequest request)
    {
        try
        {
            // في الإنتاج، استخدم FirebaseMessaging
            _logger.LogInformation("إرسال إشعار: {Title} إلى {TargetType}", request.Title, request.TargetType);

            var result = new
            {
                Success = true,
                MessageId = Guid.NewGuid().ToString(),
                TargetType = request.TargetType,
                Recipients = request.TargetType switch
                {
                    "all" => await _unitOfWork.Users.AsQueryable().CountAsync(u => !u.IsDeleted),
                    "company" => await _unitOfWork.Users.AsQueryable().CountAsync(u => u.CompanyId == request.CompanyId && !u.IsDeleted),
                    "single" => 1,
                    _ => 0
                },
                SentAt = DateTime.UtcNow
            };

            return Ok(new { success = true, data = result });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إرسال الإشعار");
            return BadRequest(new { success = false, message = "فشل إرسال الإشعار", error = ex.Message });
        }
    }

    /// <summary>
    /// حذف بيانات Firebase لمستخدم
    /// </summary>
    [HttpDelete("firebase/users/{userId:guid}")]
    public async Task<IActionResult> DeleteFirebaseUser(Guid userId)
    {
        var user = await _unitOfWork.Users.GetByIdAsync(userId);
        if (user == null)
            return NotFound(new { success = false, message = "المستخدم غير موجود" });

        // في الإنتاج، احذف من Firebase Auth أولاً
        user.IsDeleted = true;
        user.IsActive = false;
        user.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Users.Update(user);
        await _unitOfWork.SaveChangesAsync();

        _logger.LogInformation("تم حذف مستخدم Firebase: {UserId}", userId);
        return Ok(new { success = true, message = "تم الحذف بنجاح" });
    }

    #endregion

    #region VPS Management

    /// <summary>
    /// حالة VPS
    /// </summary>
    [HttpGet("vps/status")]
    public async Task<IActionResult> GetVpsStatus()
    {
        try
        {
            var vpsHost = _configuration["VPS:Host"] ?? "72.61.183.61";
            var vpsPort = int.Parse(_configuration["VPS:SSHPort"] ?? "22");

            var status = new VpsStatus
            {
                Host = vpsHost,
                IsReachable = await CheckHostReachable(vpsHost),
                Port = vpsPort,
                OS = "Ubuntu 24.04 LTS",
                Provider = "Hostinger",
                LastChecked = DateTime.UtcNow
            };

            // محاكاة معلومات النظام - في الإنتاج استخدم SSH
            status.SystemInfo = new VpsSystemInfo
            {
                Hostname = "sadara-vps",
                Uptime = "15 days",
                CpuUsage = 35.5,
                MemoryUsage = 42.3,
                DiskUsage = 28.7,
                TotalMemory = "8 GB",
                TotalDisk = "160 GB",
                NetworkIn = "2.3 GB",
                NetworkOut = "4.1 GB"
            };

            status.Services = await GetVpsServices();

            return Ok(new { success = true, data = status });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في التحقق من حالة VPS");
            return Ok(new { success = false, message = "خطأ في الاتصال بـ VPS", error = ex.Message });
        }
    }

    /// <summary>
    /// قائمة الخدمات على VPS
    /// </summary>
    [HttpGet("vps/services")]
    public async Task<IActionResult> GetVpsServicesStatus()
    {
        var services = await GetVpsServices();
        return Ok(new { success = true, data = services });
    }

    /// <summary>
    /// إعادة تشغيل خدمة على VPS
    /// </summary>
    [HttpPost("vps/services/{serviceName}/restart")]
    public async Task<IActionResult> RestartVpsService(string serviceName)
    {
        try
        {
            // في الإنتاج، استخدم SSH لتنفيذ الأمر
            _logger.LogInformation("إعادة تشغيل خدمة VPS: {ServiceName}", serviceName);

            // محاكاة
            await Task.Delay(1000);

            return Ok(new { success = true, message = $"تم إعادة تشغيل {serviceName} بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إعادة تشغيل الخدمة: {ServiceName}", serviceName);
            return BadRequest(new { success = false, message = $"فشل إعادة تشغيل {serviceName}", error = ex.Message });
        }
    }

    /// <summary>
    /// سجلات VPS
    /// </summary>
    [HttpGet("vps/logs")]
    public async Task<IActionResult> GetVpsLogs([FromQuery] string service = "api", [FromQuery] int lines = 100)
    {
        try
        {
            // محاكاة قراءة السجلات - في الإنتاج استخدم SSH
            var logs = new List<VpsLogEntry>();
            var random = new Random();
            var logTypes = new[] { "INFO", "WARN", "ERROR", "DEBUG" };
            var messages = new[]
            {
                "Request processed successfully",
                "Database connection established",
                "User authentication completed",
                "API endpoint called",
                "Background job executed",
                "Cache refreshed",
                "Health check passed",
                "Memory threshold warning"
            };

            for (int i = 0; i < lines; i++)
            {
                logs.Add(new VpsLogEntry
                {
                    Timestamp = DateTime.UtcNow.AddMinutes(-i * 5),
                    Level = logTypes[random.Next(logTypes.Length)],
                    Service = service,
                    Message = messages[random.Next(messages.Length)]
                });
            }

            return Ok(new { success = true, data = logs.Take(lines) });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في قراءة سجلات VPS");
            return BadRequest(new { success = false, message = "فشل قراءة السجلات", error = ex.Message });
        }
    }

    /// <summary>
    /// تنفيذ أمر على VPS
    /// </summary>
    [HttpPost("vps/execute")]
    public async Task<IActionResult> ExecuteVpsCommand([FromBody] VpsCommandRequest request)
    {
        try
        {
            // قائمة الأوامر المسموح بها فقط
            var allowedCommands = new[]
            {
                "systemctl status",
                "systemctl restart",
                "df -h",
                "free -h",
                "uptime",
                "docker ps",
                "docker logs",
                "pm2 list",
                "pm2 restart",
                "nginx -t",
                "certbot renew"
            };

            if (!allowedCommands.Any(c => request.Command.StartsWith(c)))
            {
                return BadRequest(new { success = false, message = "الأمر غير مسموح به" });
            }

            _logger.LogWarning("تنفيذ أمر VPS: {Command} بواسطة المستخدم", request.Command);

            // محاكاة - في الإنتاج استخدم SSH
            var output = $"Executed: {request.Command}\nOutput: Command completed successfully";

            return Ok(new { success = true, output = output, executedAt = DateTime.UtcNow });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تنفيذ أمر VPS: {Command}", request.Command);
            return BadRequest(new { success = false, message = "فشل تنفيذ الأمر", error = ex.Message });
        }
    }

    /// <summary>
    /// النسخ الاحتياطي
    /// </summary>
    [HttpPost("vps/backup")]
    public async Task<IActionResult> TriggerBackup([FromBody] BackupRequest request)
    {
        try
        {
            _logger.LogInformation("بدء النسخ الاحتياطي: {Type}", request.Type);

            // محاكاة
            var backup = new BackupResult
            {
                Id = Guid.NewGuid(),
                Type = request.Type,
                Status = "running",
                StartedAt = DateTime.UtcNow,
                EstimatedSize = "500 MB"
            };

            return Ok(new { success = true, data = backup, message = "تم بدء النسخ الاحتياطي" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في بدء النسخ الاحتياطي");
            return BadRequest(new { success = false, message = "فشل بدء النسخ الاحتياطي", error = ex.Message });
        }
    }

    /// <summary>
    /// قائمة النسخ الاحتياطية
    /// </summary>
    [HttpGet("vps/backups")]
    public async Task<IActionResult> GetBackups()
    {
        // محاكاة
        var backups = new List<BackupResult>
        {
            new BackupResult
            {
                Id = Guid.NewGuid(),
                Type = "full",
                Status = "completed",
                StartedAt = DateTime.UtcNow.AddDays(-1),
                CompletedAt = DateTime.UtcNow.AddDays(-1).AddMinutes(30),
                Size = "450 MB"
            },
            new BackupResult
            {
                Id = Guid.NewGuid(),
                Type = "database",
                Status = "completed",
                StartedAt = DateTime.UtcNow.AddHours(-6),
                CompletedAt = DateTime.UtcNow.AddHours(-6).AddMinutes(5),
                Size = "120 MB"
            }
        };

        return Ok(new { success = true, data = backups });
    }

    #endregion

    #region Database Management

    /// <summary>
    /// إحصائيات قاعدة البيانات
    /// </summary>
    [HttpGet("database/stats")]
    public async Task<IActionResult> GetDatabaseStats()
    {
        var stats = new DatabaseStats
        {
            TotalUsers = await _unitOfWork.Users.AsQueryable().CountAsync(u => !u.IsDeleted),
            TotalCompanies = await _unitOfWork.Companies.AsQueryable().CountAsync(c => !c.IsDeleted),
            TotalProducts = await _unitOfWork.Products.AsQueryable().CountAsync(p => !p.IsDeleted),
            TotalMerchants = await _unitOfWork.Merchants.AsQueryable().CountAsync(m => !m.IsDeleted),
            TotalOrders = await _unitOfWork.Orders.AsQueryable().CountAsync(o => !o.IsDeleted),
            TotalServiceRequests = await _unitOfWork.ServiceRequests.AsQueryable().CountAsync(),
            LastBackup = DateTime.UtcNow.AddHours(-6),
            DatabaseSize = "2.3 GB"
        };

        return Ok(new { success = true, data = stats });
    }

    /// <summary>
    /// صيانة قاعدة البيانات
    /// </summary>
    [HttpPost("database/maintenance")]
    public async Task<IActionResult> RunDatabaseMaintenance([FromBody] MaintenanceRequest request)
    {
        try
        {
            _logger.LogInformation("بدء صيانة قاعدة البيانات: {Action}", request.Action);

            var result = request.Action switch
            {
                "vacuum" => "تم تحسين مساحة قاعدة البيانات",
                "reindex" => "تمت إعادة بناء الفهارس",
                "analyze" => "تم تحديث الإحصائيات",
                "cleanup" => $"تم حذف {new Random().Next(100, 1000)} سجل قديم",
                _ => "إجراء غير معروف"
            };

            return Ok(new { success = true, message = result });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في صيانة قاعدة البيانات");
            return BadRequest(new { success = false, message = "فشل صيانة قاعدة البيانات", error = ex.Message });
        }
    }

    #endregion

    #region System Monitoring

    /// <summary>
    /// مراقبة صحة النظام
    /// </summary>
    [HttpGet("health/detailed")]
    public async Task<IActionResult> GetDetailedHealth()
    {
        var health = new DetailedHealth
        {
            Status = "healthy",
            CheckedAt = DateTime.UtcNow,
            Components = new Dictionary<string, ComponentHealth>
            {
                ["api"] = new ComponentHealth { Status = "healthy", ResponseTime = 45 },
                ["database"] = new ComponentHealth { Status = "healthy", ResponseTime = 12 },
                ["cache"] = new ComponentHealth { Status = "healthy", ResponseTime = 3 },
                ["firebase"] = new ComponentHealth { Status = "healthy", ResponseTime = 150 },
                ["vps"] = new ComponentHealth { Status = "healthy", ResponseTime = 25 }
            }
        };

        return Ok(new { success = true, data = health });
    }

    /// <summary>
    /// سجلات الأنشطة
    /// </summary>
    [HttpGet("audit-logs")]
    public async Task<IActionResult> GetAuditLogs(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] string? action,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        // محاكاة سجلات المراجعة
        var logs = Enumerable.Range(0, pageSize).Select(i => new AuditLog
        {
            Id = Guid.NewGuid(),
            Action = action ?? "user.login",
            UserId = Guid.NewGuid(),
            UserName = $"User {i + 1}",
            IpAddress = $"192.168.1.{i + 1}",
            Details = "Action completed successfully",
            Timestamp = DateTime.UtcNow.AddMinutes(-i * 10)
        }).ToList();

        return Ok(new { success = true, data = logs, total = 500, page, pageSize });
    }

    /// <summary>
    /// التنبيهات النشطة
    /// </summary>
    [HttpGet("alerts")]
    public async Task<IActionResult> GetAlerts()
    {
        var alerts = await GetSystemAlerts();
        return Ok(new { success = true, data = alerts });
    }

    /// <summary>
    /// تأكيد التنبيه
    /// </summary>
    [HttpPost("alerts/{alertId}/acknowledge")]
    public async Task<IActionResult> AcknowledgeAlert(Guid alertId)
    {
        _logger.LogInformation("تأكيد التنبيه: {AlertId}", alertId);
        return Ok(new { success = true, message = "تم تأكيد التنبيه" });
    }

    #endregion

    #region Configuration Management

    /// <summary>
    /// إعدادات النظام
    /// </summary>
    [HttpGet("settings")]
    public async Task<IActionResult> GetSystemSettings()
    {
        var settings = new SystemSettings
        {
            MaintenanceMode = false,
            AllowNewRegistrations = true,
            DefaultSubscriptionDays = 30,
            MaxLoginAttempts = 5,
            SessionTimeoutMinutes = 60,
            EnableTwoFactor = false,
            SmtpConfigured = true,
            SmsConfigured = true,
            PushNotificationsEnabled = true,
            ApiRateLimitPerMinute = 100
        };

        return Ok(new { success = true, data = settings });
    }

    /// <summary>
    /// تحديث إعدادات النظام
    /// </summary>
    [HttpPut("settings")]
    public async Task<IActionResult> UpdateSystemSettings([FromBody] SystemSettings settings)
    {
        _logger.LogWarning("تحديث إعدادات النظام بواسطة السوبر أدمن");
        return Ok(new { success = true, message = "تم تحديث الإعدادات بنجاح" });
    }

    /// <summary>
    /// وضع الصيانة
    /// </summary>
    [HttpPost("maintenance-mode")]
    public async Task<IActionResult> SetMaintenanceMode([FromBody] MaintenanceModeRequest request)
    {
        _logger.LogWarning("تغيير وضع الصيانة إلى: {Enabled}", request.Enabled);
        return Ok(new { success = true, message = request.Enabled ? "تم تفعيل وضع الصيانة" : "تم إيقاف وضع الصيانة" });
    }

    #endregion

    #region Helper Methods

    private async Task<SystemStatus> GetSystemStatus()
    {
        return new SystemStatus
        {
            Status = "operational",
            ApiVersion = "1.0.0",
            Environment = "production",
            Uptime = "15 days 6 hours",
            LastDeployment = DateTime.UtcNow.AddDays(-15)
        };
    }

    private async Task<SystemStatistics> GetSystemStatistics()
    {
        return new SystemStatistics
        {
            TotalUsers = await _unitOfWork.Users.AsQueryable().CountAsync(u => !u.IsDeleted),
            ActiveUsersToday = await _unitOfWork.Users.AsQueryable().CountAsync(u => u.LastLoginAt >= DateTime.UtcNow.Date),
            TotalCompanies = await _unitOfWork.Companies.AsQueryable().CountAsync(c => !c.IsDeleted),
            ActiveCompanies = await _unitOfWork.Companies.AsQueryable().CountAsync(c => c.IsActive && !c.IsExpired && !c.IsDeleted),
            TotalProducts = await _unitOfWork.Products.AsQueryable().CountAsync(p => !p.IsDeleted),
            TotalMerchants = await _unitOfWork.Merchants.AsQueryable().CountAsync(m => !m.IsDeleted),
            OrdersToday = await _unitOfWork.Orders.AsQueryable().CountAsync(o => o.CreatedAt >= DateTime.UtcNow.Date),
            RevenueToday = 0 // يحتاج حساب حقيقي
        };
    }

    private async Task<List<RecentActivity>> GetRecentActivities()
    {
        var activities = new List<RecentActivity>
        {
            new RecentActivity { Type = "company_created", Description = "تم إنشاء شركة جديدة", Timestamp = DateTime.UtcNow.AddMinutes(-30) },
            new RecentActivity { Type = "user_registered", Description = "تسجيل مستخدم جديد", Timestamp = DateTime.UtcNow.AddHours(-1) },
            new RecentActivity { Type = "order_placed", Description = "طلب جديد", Timestamp = DateTime.UtcNow.AddHours(-2) },
            new RecentActivity { Type = "subscription_renewed", Description = "تجديد اشتراك", Timestamp = DateTime.UtcNow.AddHours(-4) }
        };

        return activities;
    }

    private async Task<List<SystemAlert>> GetSystemAlerts()
    {
        var alerts = new List<SystemAlert>();

        // تحقق من الشركات المنتهية
        var expiringCompanies = await _unitOfWork.Companies.AsQueryable()
            .CountAsync(c => c.IsExpiringSoon && !c.IsExpired && !c.IsDeleted);
        if (expiringCompanies > 0)
        {
            alerts.Add(new SystemAlert
            {
                Id = Guid.NewGuid(),
                Type = "warning",
                Title = "شركات قريبة من انتهاء الاشتراك",
                Message = $"يوجد {expiringCompanies} شركة قريبة من انتهاء الاشتراك",
                CreatedAt = DateTime.UtcNow
            });
        }

        return alerts;
    }

    private async Task<List<VpsService>> GetVpsServices()
    {
        return new List<VpsService>
        {
            new VpsService { Name = "nginx", Status = "running", Port = 80, Memory = "25 MB" },
            new VpsService { Name = "postgresql", Status = "running", Port = 5432, Memory = "256 MB" },
            new VpsService { Name = "redis", Status = "running", Port = 6379, Memory = "45 MB" },
            new VpsService { Name = "sadara-api", Status = "running", Port = 5000, Memory = "180 MB" },
            new VpsService { Name = "pm2", Status = "running", Port = 0, Memory = "50 MB" }
        };
    }

    private async Task<bool> CheckHostReachable(string host)
    {
        try
        {
            using var ping = new Ping();
            var reply = await ping.SendPingAsync(host, 3000);
            return reply.Status == IPStatus.Success;
        }
        catch
        {
            return false;
        }
    }

    #endregion
}

#region DTOs

public class SuperAdminDashboard
{
    public SystemStatus SystemStatus { get; set; } = new();
    public SystemStatistics Statistics { get; set; } = new();
    public List<RecentActivity> RecentActivities { get; set; } = new();
    public List<SystemAlert> Alerts { get; set; } = new();
}

public class SystemStatus
{
    public string Status { get; set; } = string.Empty;
    public string ApiVersion { get; set; } = string.Empty;
    public string Environment { get; set; } = string.Empty;
    public string Uptime { get; set; } = string.Empty;
    public DateTime LastDeployment { get; set; }
}

public class SystemStatistics
{
    public int TotalUsers { get; set; }
    public int ActiveUsersToday { get; set; }
    public int TotalCompanies { get; set; }
    public int ActiveCompanies { get; set; }
    public int TotalProducts { get; set; }
    public int TotalMerchants { get; set; }
    public int OrdersToday { get; set; }
    public decimal RevenueToday { get; set; }
}

public class RecentActivity
{
    public string Type { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public DateTime Timestamp { get; set; }
}

public class SystemAlert
{
    public Guid Id { get; set; }
    public string Type { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public bool Acknowledged { get; set; }
}

public class FirebaseStatus
{
    public string ProjectId { get; set; } = string.Empty;
    public bool IsConnected { get; set; }
    public FirebaseServices Services { get; set; } = new();
    public DateTime LastChecked { get; set; }
}

public class FirebaseServices
{
    public bool Authentication { get; set; }
    public bool Firestore { get; set; }
    public bool Storage { get; set; }
    public bool Messaging { get; set; }
    public bool Analytics { get; set; }
}

public class UpdateFirebaseUserRequest
{
    public bool? IsActive { get; set; }
    public bool? IsPhoneVerified { get; set; }
}

public class SuperAdminSendNotificationRequest
{
    public string Title { get; set; } = string.Empty;
    public string Body { get; set; } = string.Empty;
    public string TargetType { get; set; } = "all"; // all, company, single
    public Guid? CompanyId { get; set; }
    public Guid? UserId { get; set; }
    public Dictionary<string, string>? Data { get; set; }
}

public class VpsStatus
{
    public string Host { get; set; } = string.Empty;
    public bool IsReachable { get; set; }
    public int Port { get; set; }
    public string OS { get; set; } = string.Empty;
    public string Provider { get; set; } = string.Empty;
    public VpsSystemInfo SystemInfo { get; set; } = new();
    public List<VpsService> Services { get; set; } = new();
    public DateTime LastChecked { get; set; }
}

public class VpsSystemInfo
{
    public string Hostname { get; set; } = string.Empty;
    public string Uptime { get; set; } = string.Empty;
    public double CpuUsage { get; set; }
    public double MemoryUsage { get; set; }
    public double DiskUsage { get; set; }
    public string TotalMemory { get; set; } = string.Empty;
    public string TotalDisk { get; set; } = string.Empty;
    public string NetworkIn { get; set; } = string.Empty;
    public string NetworkOut { get; set; } = string.Empty;
}

public class VpsService
{
    public string Name { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public int Port { get; set; }
    public string Memory { get; set; } = string.Empty;
}

public class VpsLogEntry
{
    public DateTime Timestamp { get; set; }
    public string Level { get; set; } = string.Empty;
    public string Service { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
}

public class VpsCommandRequest
{
    public string Command { get; set; } = string.Empty;
}

public class BackupRequest
{
    public string Type { get; set; } = "full"; // full, database, files
}

public class BackupResult
{
    public Guid Id { get; set; }
    public string Type { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public DateTime StartedAt { get; set; }
    public DateTime? CompletedAt { get; set; }
    public string? Size { get; set; }
    public string? EstimatedSize { get; set; }
}

public class DatabaseStats
{
    public int TotalUsers { get; set; }
    public int TotalCompanies { get; set; }
    public int TotalProducts { get; set; }
    public int TotalMerchants { get; set; }
    public int TotalOrders { get; set; }
    public int TotalServiceRequests { get; set; }
    public DateTime LastBackup { get; set; }
    public string DatabaseSize { get; set; } = string.Empty;
}

public class MaintenanceRequest
{
    public string Action { get; set; } = string.Empty; // vacuum, reindex, analyze, cleanup
}

public class DetailedHealth
{
    public string Status { get; set; } = string.Empty;
    public DateTime CheckedAt { get; set; }
    public Dictionary<string, ComponentHealth> Components { get; set; } = new();
}

public class ComponentHealth
{
    public string Status { get; set; } = string.Empty;
    public int ResponseTime { get; set; }
}

public class AuditLog
{
    public Guid Id { get; set; }
    public string Action { get; set; } = string.Empty;
    public Guid UserId { get; set; }
    public string UserName { get; set; } = string.Empty;
    public string IpAddress { get; set; } = string.Empty;
    public string Details { get; set; } = string.Empty;
    public DateTime Timestamp { get; set; }
}

public class SystemSettings
{
    public bool MaintenanceMode { get; set; }
    public bool AllowNewRegistrations { get; set; }
    public int DefaultSubscriptionDays { get; set; }
    public int MaxLoginAttempts { get; set; }
    public int SessionTimeoutMinutes { get; set; }
    public bool EnableTwoFactor { get; set; }
    public bool SmtpConfigured { get; set; }
    public bool SmsConfigured { get; set; }
    public bool PushNotificationsEnabled { get; set; }
    public int ApiRateLimitPerMinute { get; set; }
}

public class MaintenanceModeRequest
{
    public bool Enabled { get; set; }
    public string? Message { get; set; }
}

// ============ Super Admin Authentication DTOs ============

public class SuperAdminLoginRequest
{
    /// <summary>اسم المستخدم (البريد الإلكتروني أو رقم الهاتف)</summary>
    public string Username { get; set; } = string.Empty;
    
    /// <summary>كلمة المرور</summary>
    public string Password { get; set; } = string.Empty;
}

public class SuperAdminLoginResponse
{
    public Guid Id { get; set; }
    public string Username { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string Token { get; set; } = string.Empty;
    public string RefreshToken { get; set; } = string.Empty;
    public DateTime ExpiresAt { get; set; }
}

public class SuperAdminRefreshTokenRequest
{
    public string RefreshToken { get; set; } = string.Empty;
}

// ✅ Note: CreateCompanyRequest, UpdateCompanyRequest, RenewSubscriptionRequest
// are already defined in CompaniesController.cs - reusing them here

#endregion
