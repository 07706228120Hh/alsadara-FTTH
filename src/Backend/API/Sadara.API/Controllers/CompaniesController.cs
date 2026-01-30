using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using System.Text.Json;

namespace Sadara.API.Controllers;

/// <summary>
/// إدارة الشركات - مطابق لـ TenantService في Flutter
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class CompaniesController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly IConfiguration _configuration;
    private readonly ILogger<CompaniesController> _logger;

    public CompaniesController(
        IUnitOfWork unitOfWork,
        IConfiguration configuration,
        ILogger<CompaniesController> logger)
    {
        _unitOfWork = unitOfWork;
        _configuration = configuration;
        _logger = logger;
    }

    #region Authentication

    /// <summary>
    /// تسجيل دخول موظف شركة
    /// </summary>
    [HttpPost("login")]
    [AllowAnonymous]
    public async Task<IActionResult> Login([FromBody] CompanyLoginRequest request)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(request.CompanyCode) || 
                string.IsNullOrWhiteSpace(request.Username) || 
                string.IsNullOrWhiteSpace(request.Password))
            {
                return BadRequest(new { success = false, message = "جميع الحقول مطلوبة" });
            }

            // البحث عن الشركة
            var company = await _unitOfWork.Companies.AsQueryable()
                .FirstOrDefaultAsync(c => c.Code == request.CompanyCode && !c.IsDeleted);

            if (company == null)
            {
                return Unauthorized(new { success = false, message = "كود الشركة غير صحيح" });
            }

            // التحقق من حالة الشركة
            if (!company.IsActive)
            {
                return Unauthorized(new { success = false, message = "الشركة معطلة" });
            }

            // التحقق من انتهاء الاشتراك
            if (company.SubscriptionEndDate < DateTime.UtcNow)
            {
                return Unauthorized(new { success = false, message = "انتهى اشتراك الشركة" });
            }

            // البحث عن المستخدم
            var user = await _unitOfWork.Users.AsQueryable()
                .FirstOrDefaultAsync(u => 
                    u.CompanyId == company.Id &&
                    (u.PhoneNumber == request.Username || u.Email == request.Username || u.EmployeeCode == request.Username) &&
                    u.Role >= UserRole.Employee &&
                    !u.IsDeleted);

            if (user == null)
            {
                _logger.LogWarning("محاولة دخول فاشلة لموظف: {Username} في شركة: {CompanyCode}", 
                    request.Username, request.CompanyCode);
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
                    _logger.LogWarning("تم قفل حساب موظف بسبب محاولات فاشلة: {UserId}", user.Id);
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
            var token = GenerateJwtToken(user, company);
            var refreshToken = GenerateRefreshToken();
            
            user.RefreshToken = refreshToken;
            user.RefreshTokenExpiryTime = DateTime.UtcNow.AddDays(7);
            _unitOfWork.Users.Update(user);
            await _unitOfWork.SaveChangesAsync();

            _logger.LogInformation("تسجيل دخول ناجح لموظف: {UserId} في شركة: {CompanyId}", user.Id, company.Id);

            return Ok(new
            {
                success = true,
                message = "تم تسجيل الدخول بنجاح",
                data = new CompanyLoginResponse
                {
                    User = new CompanyUserResponse
                    {
                        Id = user.Id,
                        FullName = user.FullName,
                        PhoneNumber = user.PhoneNumber,
                        Email = user.Email,
                        Role = user.Role.ToString(),
                        Department = user.Department,
                        EmployeeCode = user.EmployeeCode,
                        FirstSystemPermissions = user.FirstSystemPermissions,
                        SecondSystemPermissions = user.SecondSystemPermissions,
                        FirstSystemPermissionsV2 = user.FirstSystemPermissionsV2,
                        SecondSystemPermissionsV2 = user.SecondSystemPermissionsV2
                    },
                    Company = new CompanyInfoResponse
                    {
                        Id = company.Id,
                        Name = company.Name,
                        Code = company.Code,
                        LogoUrl = company.LogoUrl,
                        SubscriptionEndDate = company.SubscriptionEndDate,
                        EnabledFirstSystemFeatures = company.EnabledFirstSystemFeatures,
                        EnabledSecondSystemFeatures = company.EnabledSecondSystemFeatures
                    },
                    Token = token,
                    RefreshToken = refreshToken,
                    ExpiresAt = DateTime.UtcNow.AddHours(24)
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تسجيل دخول موظف");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    /// <summary>
    /// تحديث التوكن
    /// </summary>
    [HttpPost("refresh-token")]
    [AllowAnonymous]
    public async Task<IActionResult> RefreshToken([FromBody] CompanyRefreshTokenRequest request)
    {
        try
        {
            var user = await _unitOfWork.Users.AsQueryable()
                .Include(u => u.Company)
                .FirstOrDefaultAsync(u => 
                    u.RefreshToken == request.RefreshToken &&
                    u.RefreshTokenExpiryTime > DateTime.UtcNow &&
                    u.CompanyId.HasValue &&
                    !u.IsDeleted);

            if (user == null || user.Company == null)
            {
                return Unauthorized(new { success = false, message = "التوكن غير صالح أو منتهي" });
            }

            var newToken = GenerateJwtToken(user, user.Company);
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

    private string GenerateJwtToken(User user, Company company)
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
            new Claim("role_id", ((int)user.Role).ToString()),
            new Claim("company_id", company.Id.ToString()),
            new Claim("company_code", company.Code),
            new Claim("company_name", company.Name)
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

    /// <summary>
    /// الحصول على قائمة الشركات النشطة للاختيار عند تسجيل الدخول
    /// متاح للجميع بدون مصادقة
    /// </summary>
    [HttpGet("list")]
    [AllowAnonymous]
    public async Task<IActionResult> GetCompanyList()
    {
        try
        {
            var companies = await _unitOfWork.Companies.AsQueryable()
                .Where(c => !c.IsDeleted && c.IsActive)
                .OrderBy(c => c.Name)
                .Select(c => new
                {
                    c.Id,
                    c.Name,
                    c.Code,
                    c.LogoUrl
                })
                .ToListAsync();

            return Ok(new { success = true, data = companies });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب قائمة الشركات");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    #endregion

    #region Company CRUD

    /// <summary>
    /// الحصول على جميع الشركات - للمدير الأعلى فقط
    /// </summary>
    [HttpGet]
    [Authorize(Policy = "SuperAdmin")]
    public async Task<IActionResult> GetAll([FromQuery] int page = 1, [FromQuery] int pageSize = 20)
    {
        var query = _unitOfWork.Companies.AsQueryable()
            .Where(c => !c.IsDeleted);

        var total = await query.CountAsync();
        var companies = await query
            .Include(c => c.AdminUser)
            .OrderByDescending(c => c.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(c => new CompanyResponse
            {
                Id = c.Id,
                Name = c.Name,
                Code = c.Code,
                Email = c.Email,
                Phone = c.Phone,
                Address = c.Address,
                City = c.City,
                LogoUrl = c.LogoUrl,
                SubscriptionStartDate = c.SubscriptionStartDate,
                SubscriptionEndDate = c.SubscriptionEndDate,
                MaxUsers = c.MaxUsers,
                IsActive = c.IsActive,
                EnabledFirstSystemFeatures = c.EnabledFirstSystemFeatures,
                EnabledSecondSystemFeatures = c.EnabledSecondSystemFeatures,
                AdminUserId = c.AdminUserId,
                AdminUserName = c.AdminUser != null ? c.AdminUser.FullName : null,
                EmployeeCount = c.Employees.Count(e => !e.IsDeleted),
                DaysRemaining = c.DaysRemaining,
                IsExpired = c.IsExpired,
                SubscriptionStatus = c.SubscriptionStatus.ToString(),
                CreatedAt = c.CreatedAt
            })
            .ToListAsync();

        return Ok(new { success = true, data = companies, total, page, pageSize });
    }

    /// <summary>
    /// الحصول على شركة بالمعرف
    /// </summary>
    [HttpGet("{id:guid}")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> GetById(Guid id)
    {
        var company = await _unitOfWork.Companies.AsQueryable()
            .Include(c => c.AdminUser)
            .Include(c => c.CompanyServices)
                .ThenInclude(cs => cs.Service)
            .FirstOrDefaultAsync(c => c.Id == id && !c.IsDeleted);

        if (company == null)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        return Ok(new { success = true, data = MapCompanyToResponse(company) });
    }

    /// <summary>
    /// الحصول على شركة بالكود
    /// </summary>
    [HttpGet("by-code/{code}")]
    public async Task<IActionResult> GetByCode(string code)
    {
        var company = await _unitOfWork.Companies.AsQueryable()
            .Include(c => c.AdminUser)
            .FirstOrDefaultAsync(c => c.Code == code && !c.IsDeleted);

        if (company == null)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        return Ok(new { success = true, data = MapCompanyToResponse(company) });
    }

    /// <summary>
    /// إنشاء شركة جديدة مع مدير النظام
    /// </summary>
    [HttpPost]
    [Authorize(Policy = "SuperAdmin")]
    public async Task<IActionResult> Create([FromBody] CreateCompanyRequest request)
    {
        // التحقق من تفرد الكود
        var existingCode = await _unitOfWork.Companies.FirstOrDefaultAsync(c => c.Code == request.Code);
        if (existingCode != null)
            return BadRequest(new { success = false, message = "كود الشركة مستخدم بالفعل" });

        // التحقق من تفرد البريد الإلكتروني للمدير
        var existingEmail = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.Email == request.AdminEmail);
        if (existingEmail != null)
            return BadRequest(new { success = false, message = "البريد الإلكتروني مستخدم بالفعل" });

        // إنشاء المستخدم المدير
        var adminUser = new User
        {
            Id = Guid.NewGuid(),
            FullName = request.AdminName,
            PhoneNumber = request.AdminPhone,
            Email = request.AdminEmail,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.AdminPassword),
            Role = UserRole.CompanyAdmin,
            IsActive = true,
            IsPhoneVerified = true,
            CreatedAt = DateTime.UtcNow
        };

        // إنشاء الشركة
        var company = new Company
        {
            Id = Guid.NewGuid(),
            Name = request.Name,
            Code = request.Code,
            Email = request.Email,
            Phone = request.Phone,
            Address = request.Address,
            City = request.City,
            LogoUrl = request.LogoUrl,
            SubscriptionStartDate = request.SubscriptionStartDate ?? DateTime.UtcNow,
            SubscriptionEndDate = request.SubscriptionEndDate ?? DateTime.UtcNow.AddDays(30),
            MaxUsers = request.MaxUsers ?? 10,
            IsActive = true,
            EnabledFirstSystemFeatures = JsonSerializer.Serialize(request.EnabledFirstSystemFeatures ?? GetDefaultFirstSystemFeatures()),
            EnabledSecondSystemFeatures = JsonSerializer.Serialize(request.EnabledSecondSystemFeatures ?? GetDefaultSecondSystemFeatures()),
            AdminUserId = adminUser.Id,
            CreatedAt = DateTime.UtcNow
        };

        // ربط المستخدم بالشركة
        adminUser.CompanyId = company.Id;
        adminUser.FirstSystemPermissions = company.EnabledFirstSystemFeatures;
        adminUser.SecondSystemPermissions = company.EnabledSecondSystemFeatures;

        await _unitOfWork.Users.AddAsync(adminUser);
        await _unitOfWork.Companies.AddAsync(company);
        await _unitOfWork.SaveChangesAsync();

        return CreatedAtAction(nameof(GetById), new { id = company.Id }, new 
        { 
            success = true, 
            data = MapCompanyToResponse(company),
            adminUserId = adminUser.Id
        });
    }

    /// <summary>
    /// تحديث بيانات شركة
    /// </summary>
    [HttpPut("{id:guid}")]
    [Authorize(Policy = "SuperAdmin")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateCompanyRequest request)
    {
        var company = await _unitOfWork.Companies.GetByIdAsync(id);
        if (company == null || company.IsDeleted)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        // التحقق من الكود إذا تم تغييره
        if (!string.IsNullOrEmpty(request.Code) && request.Code != company.Code)
        {
            var existingCode = await _unitOfWork.Companies.FirstOrDefaultAsync(c => c.Code == request.Code && c.Id != id);
            if (existingCode != null)
                return BadRequest(new { success = false, message = "كود الشركة مستخدم بالفعل" });
        }

        company.Name = request.Name ?? company.Name;
        company.Code = request.Code ?? company.Code;
        company.Email = request.Email ?? company.Email;
        company.Phone = request.Phone ?? company.Phone;
        company.Address = request.Address ?? company.Address;
        company.City = request.City ?? company.City;
        company.LogoUrl = request.LogoUrl ?? company.LogoUrl;
        company.MaxUsers = request.MaxUsers ?? company.MaxUsers;
        
        if (request.SubscriptionStartDate.HasValue)
            company.SubscriptionStartDate = request.SubscriptionStartDate.Value;
        if (request.SubscriptionEndDate.HasValue)
            company.SubscriptionEndDate = request.SubscriptionEndDate.Value;
        if (request.EnabledFirstSystemFeatures != null)
            company.EnabledFirstSystemFeatures = JsonSerializer.Serialize(request.EnabledFirstSystemFeatures);
        if (request.EnabledSecondSystemFeatures != null)
            company.EnabledSecondSystemFeatures = JsonSerializer.Serialize(request.EnabledSecondSystemFeatures);
        
        company.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Companies.Update(company);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, data = MapCompanyToResponse(company) });
    }

    /// <summary>
    /// تجديد اشتراك الشركة
    /// </summary>
    [HttpPatch("{id:guid}/renew")]
    [Authorize(Policy = "SuperAdmin")]
    public async Task<IActionResult> RenewSubscription(Guid id, [FromBody] RenewSubscriptionRequest request)
    {
        var company = await _unitOfWork.Companies.GetByIdAsync(id);
        if (company == null || company.IsDeleted)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        var startDate = company.IsExpired ? DateTime.UtcNow : company.SubscriptionEndDate;
        company.SubscriptionEndDate = startDate.AddDays(request.Days);
        company.IsActive = true;
        company.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Companies.Update(company);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new 
        { 
            success = true, 
            message = $"تم تجديد الاشتراك حتى {company.SubscriptionEndDate:yyyy-MM-dd}",
            data = MapCompanyToResponse(company) 
        });
    }

    /// <summary>
    /// تفعيل/تعطيل شركة
    /// </summary>
    [HttpPatch("{id:guid}/toggle-status")]
    [Authorize(Policy = "SuperAdmin")]
    public async Task<IActionResult> ToggleStatus(Guid id)
    {
        var company = await _unitOfWork.Companies.GetByIdAsync(id);
        if (company == null || company.IsDeleted)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        company.IsActive = !company.IsActive;
        company.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Companies.Update(company);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new 
        { 
            success = true, 
            message = company.IsActive ? "تم تفعيل الشركة" : "تم تعطيل الشركة",
            data = MapCompanyToResponse(company) 
        });
    }

    /// <summary>
    /// حذف شركة (Soft Delete)
    /// </summary>
    [HttpDelete("{id:guid}")]
    [Authorize(Policy = "SuperAdmin")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var company = await _unitOfWork.Companies.GetByIdAsync(id);
        if (company == null || company.IsDeleted)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        company.IsDeleted = true;
        company.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Companies.Update(company);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم حذف الشركة بنجاح" });
    }

    #endregion

    #region Company Employees

    /// <summary>
    /// الحصول على موظفي شركة
    /// </summary>
    [HttpGet("{id:guid}/employees")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> GetEmployees(Guid id, [FromQuery] int page = 1, [FromQuery] int pageSize = 20)
    {
        var company = await _unitOfWork.Companies.GetByIdAsync(id);
        if (company == null || company.IsDeleted)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        var query = _unitOfWork.Users.AsQueryable()
            .Where(u => u.CompanyId == id && !u.IsDeleted);

        var total = await query.CountAsync();
        var employees = await query
            .OrderBy(u => u.FullName)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(u => new EmployeeResponse
            {
                Id = u.Id,
                FullName = u.FullName,
                PhoneNumber = u.PhoneNumber,
                Email = u.Email,
                Role = u.Role.ToString(),
                Department = u.Department,
                EmployeeCode = u.EmployeeCode,
                Center = u.Center,
                Salary = u.Salary,
                IsActive = u.IsActive,
                FirstSystemPermissions = u.FirstSystemPermissions,
                SecondSystemPermissions = u.SecondSystemPermissions,
                CreatedAt = u.CreatedAt
            })
            .ToListAsync();

        return Ok(new { success = true, data = employees, total, page, pageSize });
    }

    /// <summary>
    /// إضافة موظف جديد للشركة
    /// </summary>
    [HttpPost("{id:guid}/employees")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> AddEmployee(Guid id, [FromBody] CreateEmployeeRequest request)
    {
        var company = await _unitOfWork.Companies.GetByIdAsync(id);
        if (company == null || company.IsDeleted)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        // التحقق من الحد الأقصى للموظفين
        var currentCount = await _unitOfWork.Users.AsQueryable()
            .CountAsync(u => u.CompanyId == id && !u.IsDeleted);
        if (currentCount >= company.MaxUsers)
            return BadRequest(new { success = false, message = $"تم الوصول للحد الأقصى للموظفين ({company.MaxUsers})" });

        // التحقق من رقم الهاتف
        var existingPhone = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.PhoneNumber == request.PhoneNumber);
        if (existingPhone != null)
            return BadRequest(new { success = false, message = "رقم الهاتف مستخدم بالفعل" });

        var employee = new User
        {
            Id = Guid.NewGuid(),
            FullName = request.FullName,
            PhoneNumber = request.PhoneNumber,
            Email = request.Email,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password),
            Role = ParseUserRole(request.Role),
            CompanyId = id,
            Department = request.Department,
            EmployeeCode = request.EmployeeCode ?? GenerateEmployeeCode(),
            Center = request.Center,
            Salary = request.Salary,
            IsActive = true,
            IsPhoneVerified = true,
            FirstSystemPermissions = JsonSerializer.Serialize(request.FirstSystemPermissions ?? new Dictionary<string, bool>()),
            SecondSystemPermissions = JsonSerializer.Serialize(request.SecondSystemPermissions ?? new Dictionary<string, bool>()),
            CreatedAt = DateTime.UtcNow
        };

        await _unitOfWork.Users.AddAsync(employee);
        await _unitOfWork.SaveChangesAsync();

        return CreatedAtAction(nameof(GetEmployeeById), new { id = id, employeeId = employee.Id }, new 
        { 
            success = true, 
            data = MapUserToEmployeeResponse(employee) 
        });
    }

    /// <summary>
    /// الحصول على موظف بالمعرف
    /// </summary>
    [HttpGet("{id:guid}/employees/{employeeId:guid}")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> GetEmployeeById(Guid id, Guid employeeId)
    {
        var employee = await _unitOfWork.Users.AsQueryable()
            .FirstOrDefaultAsync(u => u.Id == employeeId && u.CompanyId == id && !u.IsDeleted);

        if (employee == null)
            return NotFound(new { success = false, message = "الموظف غير موجود" });

        return Ok(new { success = true, data = MapUserToEmployeeResponse(employee) });
    }

    /// <summary>
    /// تحديث بيانات موظف
    /// </summary>
    [HttpPut("{id:guid}/employees/{employeeId:guid}")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> UpdateEmployee(Guid id, Guid employeeId, [FromBody] UpdateEmployeeRequest request)
    {
        var employee = await _unitOfWork.Users.AsQueryable()
            .FirstOrDefaultAsync(u => u.Id == employeeId && u.CompanyId == id && !u.IsDeleted);

        if (employee == null)
            return NotFound(new { success = false, message = "الموظف غير موجود" });

        employee.FullName = request.FullName ?? employee.FullName;
        employee.Email = request.Email ?? employee.Email;
        employee.Department = request.Department ?? employee.Department;
        employee.Center = request.Center ?? employee.Center;
        employee.Salary = request.Salary ?? employee.Salary;
        
        if (!string.IsNullOrEmpty(request.Role))
            employee.Role = ParseUserRole(request.Role);
        if (request.FirstSystemPermissions != null)
            employee.FirstSystemPermissions = JsonSerializer.Serialize(request.FirstSystemPermissions);
        if (request.SecondSystemPermissions != null)
            employee.SecondSystemPermissions = JsonSerializer.Serialize(request.SecondSystemPermissions);
        if (!string.IsNullOrEmpty(request.Password))
            employee.PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password);

        employee.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Users.Update(employee);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, data = MapUserToEmployeeResponse(employee) });
    }

    /// <summary>
    /// تحديث صلاحيات موظف
    /// </summary>
    [HttpPatch("{id:guid}/employees/{employeeId:guid}/permissions")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> UpdateEmployeePermissions(Guid id, Guid employeeId, [FromBody] UpdatePermissionsRequest request)
    {
        var employee = await _unitOfWork.Users.AsQueryable()
            .FirstOrDefaultAsync(u => u.Id == employeeId && u.CompanyId == id && !u.IsDeleted);

        if (employee == null)
            return NotFound(new { success = false, message = "الموظف غير موجود" });

        if (request.FirstSystemPermissions != null)
            employee.FirstSystemPermissions = JsonSerializer.Serialize(request.FirstSystemPermissions);
        if (request.SecondSystemPermissions != null)
            employee.SecondSystemPermissions = JsonSerializer.Serialize(request.SecondSystemPermissions);

        employee.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Users.Update(employee);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تحديث الصلاحيات بنجاح", data = MapUserToEmployeeResponse(employee) });
    }

    /// <summary>
    /// حذف موظف (Soft Delete)
    /// </summary>
    [HttpDelete("{id:guid}/employees/{employeeId:guid}")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> DeleteEmployee(Guid id, Guid employeeId)
    {
        var employee = await _unitOfWork.Users.AsQueryable()
            .FirstOrDefaultAsync(u => u.Id == employeeId && u.CompanyId == id && !u.IsDeleted);

        if (employee == null)
            return NotFound(new { success = false, message = "الموظف غير موجود" });

        var company = await _unitOfWork.Companies.GetByIdAsync(id);
        if (company?.AdminUserId == employeeId)
            return BadRequest(new { success = false, message = "لا يمكن حذف مدير الشركة" });

        employee.IsDeleted = true;
        employee.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Users.Update(employee);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم حذف الموظف بنجاح" });
    }

    #endregion

    #region Statistics

    /// <summary>
    /// إحصائيات الشركات
    /// </summary>
    [HttpGet("statistics")]
    [Authorize(Policy = "SuperAdmin")]
    public async Task<IActionResult> GetStatistics()
    {
        var companies = await _unitOfWork.Companies.AsQueryable()
            .Where(c => !c.IsDeleted)
            .ToListAsync();

        var stats = new
        {
            TotalCompanies = companies.Count,
            ActiveCompanies = companies.Count(c => c.IsActive && !c.IsExpired),
            ExpiredCompanies = companies.Count(c => c.IsExpired),
            ExpiringSoonCompanies = companies.Count(c => c.IsExpiringSoon && !c.IsExpired),
            SuspendedCompanies = companies.Count(c => !c.IsActive),
            TotalEmployees = await _unitOfWork.Users.AsQueryable().CountAsync(u => u.CompanyId != null && !u.IsDeleted)
        };

        return Ok(new { success = true, data = stats });
    }

    /// <summary>
    /// الشركات القريبة من انتهاء الاشتراك
    /// </summary>
    [HttpGet("expiring-soon")]
    [Authorize(Policy = "SuperAdmin")]
    public async Task<IActionResult> GetExpiringSoon([FromQuery] int days = 7)
    {
        var threshold = DateTime.UtcNow.AddDays(days);
        var companies = await _unitOfWork.Companies.AsQueryable()
            .Where(c => !c.IsDeleted && c.IsActive && c.SubscriptionEndDate <= threshold && c.SubscriptionEndDate > DateTime.UtcNow)
            .OrderBy(c => c.SubscriptionEndDate)
            .Select(c => new CompanyResponse
            {
                Id = c.Id,
                Name = c.Name,
                Code = c.Code,
                SubscriptionEndDate = c.SubscriptionEndDate,
                DaysRemaining = c.DaysRemaining,
                IsExpiringSoon = true
            })
            .ToListAsync();

        return Ok(new { success = true, data = companies });
    }

    #endregion

    #region Helper Methods

    private static CompanyResponse MapCompanyToResponse(Company company)
    {
        return new CompanyResponse
        {
            Id = company.Id,
            Name = company.Name,
            Code = company.Code,
            Email = company.Email,
            Phone = company.Phone,
            Address = company.Address,
            City = company.City,
            LogoUrl = company.LogoUrl,
            SubscriptionStartDate = company.SubscriptionStartDate,
            SubscriptionEndDate = company.SubscriptionEndDate,
            MaxUsers = company.MaxUsers,
            IsActive = company.IsActive,
            EnabledFirstSystemFeatures = company.EnabledFirstSystemFeatures,
            EnabledSecondSystemFeatures = company.EnabledSecondSystemFeatures,
            AdminUserId = company.AdminUserId,
            AdminUserName = company.AdminUser?.FullName,
            DaysRemaining = company.DaysRemaining,
            IsExpired = company.IsExpired,
            IsExpiringSoon = company.IsExpiringSoon,
            SubscriptionStatus = company.SubscriptionStatus.ToString(),
            CreatedAt = company.CreatedAt
        };
    }

    private static EmployeeResponse MapUserToEmployeeResponse(User user)
    {
        return new EmployeeResponse
        {
            Id = user.Id,
            FullName = user.FullName,
            PhoneNumber = user.PhoneNumber,
            Email = user.Email,
            Role = user.Role.ToString(),
            Department = user.Department,
            EmployeeCode = user.EmployeeCode,
            Center = user.Center,
            Salary = user.Salary,
            IsActive = user.IsActive,
            FirstSystemPermissions = user.FirstSystemPermissions,
            SecondSystemPermissions = user.SecondSystemPermissions,
            CreatedAt = user.CreatedAt
        };
    }

    private static Dictionary<string, bool> GetDefaultFirstSystemFeatures()
    {
        return new Dictionary<string, bool>
        {
            { "attendance", true },
            { "agent", true },
            { "tasks", true },
            { "zones", true },
            { "ai_search", false }
        };
    }

    private static Dictionary<string, bool> GetDefaultSecondSystemFeatures()
    {
        return new Dictionary<string, bool>
        {
            { "view_users", true },
            { "edit_users", false },
            { "delete_users", false },
            { "view_subscriptions", true },
            { "edit_subscriptions", false },
            { "view_tasks", true },
            { "edit_tasks", false },
            { "delete_tasks", false },
            { "view_zones", true },
            { "edit_zones", false },
            { "view_accounts", true },
            { "edit_accounts", false }
        };
    }

    private static UserRole ParseUserRole(string role)
    {
        return role?.ToLower() switch
        {
            "admin" or "companyadmin" => UserRole.CompanyAdmin,
            "manager" => UserRole.Manager,
            "technicalleader" => UserRole.TechnicalLeader,
            "technician" => UserRole.Technician,
            "employee" => UserRole.Employee,
            "viewer" => UserRole.Viewer,
            _ => UserRole.Employee
        };
    }

    private static string GenerateEmployeeCode()
    {
        return $"EMP-{DateTime.UtcNow:yyMMdd}-{Guid.NewGuid().ToString()[..4].ToUpper()}";
    }

    #endregion
}

#region DTOs

public class CompanyResponse
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Code { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string? Phone { get; set; }
    public string? Address { get; set; }
    public string? City { get; set; }
    public string? LogoUrl { get; set; }
    public DateTime SubscriptionStartDate { get; set; }
    public DateTime SubscriptionEndDate { get; set; }
    public int MaxUsers { get; set; }
    public bool IsActive { get; set; }
    public string? EnabledFirstSystemFeatures { get; set; }
    public string? EnabledSecondSystemFeatures { get; set; }
    public Guid? AdminUserId { get; set; }
    public string? AdminUserName { get; set; }
    public int EmployeeCount { get; set; }
    public int DaysRemaining { get; set; }
    public bool IsExpired { get; set; }
    public bool IsExpiringSoon { get; set; }
    public string SubscriptionStatus { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
}

public class CreateCompanyRequest
{
    public string Name { get; set; } = string.Empty;
    public string Code { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string? Phone { get; set; }
    public string? Address { get; set; }
    public string? City { get; set; }
    public string? LogoUrl { get; set; }
    public DateTime? SubscriptionStartDate { get; set; }
    public DateTime? SubscriptionEndDate { get; set; }
    public int? MaxUsers { get; set; }
    public Dictionary<string, bool>? EnabledFirstSystemFeatures { get; set; }
    public Dictionary<string, bool>? EnabledSecondSystemFeatures { get; set; }
    
    // بيانات المدير
    public string AdminName { get; set; } = string.Empty;
    public string AdminEmail { get; set; } = string.Empty;
    public string AdminPhone { get; set; } = string.Empty;
    public string AdminPassword { get; set; } = string.Empty;
}

public class UpdateCompanyRequest
{
    public string? Name { get; set; }
    public string? Code { get; set; }
    public string? Email { get; set; }
    public string? Phone { get; set; }
    public string? Address { get; set; }
    public string? City { get; set; }
    public string? LogoUrl { get; set; }
    public DateTime? SubscriptionStartDate { get; set; }
    public DateTime? SubscriptionEndDate { get; set; }
    public int? MaxUsers { get; set; }
    public Dictionary<string, bool>? EnabledFirstSystemFeatures { get; set; }
    public Dictionary<string, bool>? EnabledSecondSystemFeatures { get; set; }
}

public class RenewSubscriptionRequest
{
    public int Days { get; set; } = 30;
}

public class EmployeeResponse
{
    public Guid Id { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string PhoneNumber { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string Role { get; set; } = string.Empty;
    public string? Department { get; set; }
    public string? EmployeeCode { get; set; }
    public string? Center { get; set; }
    public string? Salary { get; set; }
    public bool IsActive { get; set; }
    public string? FirstSystemPermissions { get; set; }
    public string? SecondSystemPermissions { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class CreateEmployeeRequest
{
    public string FullName { get; set; } = string.Empty;
    public string PhoneNumber { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string Password { get; set; } = string.Empty;
    public string Role { get; set; } = "employee";
    public string? Department { get; set; }
    public string? EmployeeCode { get; set; }
    public string? Center { get; set; }
    public string? Salary { get; set; }
    public Dictionary<string, bool>? FirstSystemPermissions { get; set; }
    public Dictionary<string, bool>? SecondSystemPermissions { get; set; }
}

public class UpdateEmployeeRequest
{
    public string? FullName { get; set; }
    public string? Email { get; set; }
    public string? Password { get; set; }
    public string? Role { get; set; }
    public string? Department { get; set; }
    public string? Center { get; set; }
    public string? Salary { get; set; }
    public Dictionary<string, bool>? FirstSystemPermissions { get; set; }
    public Dictionary<string, bool>? SecondSystemPermissions { get; set; }
}

public class UpdatePermissionsRequest
{
    public Dictionary<string, bool>? FirstSystemPermissions { get; set; }
    public Dictionary<string, bool>? SecondSystemPermissions { get; set; }
}

// ============ Company Authentication DTOs ============

public class CompanyLoginRequest
{
    /// <summary>كود الشركة</summary>
    public string CompanyCode { get; set; } = string.Empty;
    
    /// <summary>اسم المستخدم (رقم الهاتف أو البريد الإلكتروني أو كود الموظف)</summary>
    public string Username { get; set; } = string.Empty;
    
    /// <summary>كلمة المرور</summary>
    public string Password { get; set; } = string.Empty;
}

public class CompanyLoginResponse
{
    public CompanyUserResponse User { get; set; } = new();
    public CompanyInfoResponse Company { get; set; } = new();
    public string Token { get; set; } = string.Empty;
    public string RefreshToken { get; set; } = string.Empty;
    public DateTime ExpiresAt { get; set; }
}

public class CompanyUserResponse
{
    public Guid Id { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string PhoneNumber { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string Role { get; set; } = string.Empty;
    public string? Department { get; set; }
    public string? EmployeeCode { get; set; }
    public string? FirstSystemPermissions { get; set; }
    public string? SecondSystemPermissions { get; set; }
    public string? FirstSystemPermissionsV2 { get; set; }
    public string? SecondSystemPermissionsV2 { get; set; }
}

public class CompanyInfoResponse
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Code { get; set; } = string.Empty;
    public string? LogoUrl { get; set; }
    public DateTime SubscriptionEndDate { get; set; }
    public string? EnabledFirstSystemFeatures { get; set; }
    public string? EnabledSecondSystemFeatures { get; set; }
}

public class CompanyRefreshTokenRequest
{
    public string RefreshToken { get; set; } = string.Empty;
}

#endregion
