using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;
using Sadara.Infrastructure.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Sadara.API.Constants;

namespace Sadara.API.Controllers;

/// <summary>
/// API داخلي للوصول للبيانات من تطبيق Desktop
/// يستخدم API Key للمصادقة
/// </summary>
[ApiController]
[Route("api/internal")]
[Consumes("application/json")]
[Produces("application/json")]
public class InternalDataController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly IConfiguration _configuration;
    private readonly SadaraDbContext _context;
    private readonly ILogger<InternalDataController> _logger;

    public InternalDataController(IUnitOfWork unitOfWork, IConfiguration configuration, SadaraDbContext context, ILogger<InternalDataController> logger)
    {
        _unitOfWork = unitOfWork;
        _configuration = configuration;
        _context = context;
        _logger = logger;
    }

    /// <summary>
    /// التحقق من API Key - يقرأ من الإعدادات أو Environment Variable
    /// </summary>
    private static decimal _safeDecimal(System.Text.Json.JsonElement el, string prop)
    {
        if (!el.TryGetProperty(prop, out var val)) return 0;
        try { return val.GetDecimal(); }
        catch { return decimal.TryParse(val.GetRawText(), out var d) ? d : 0; }
    }

    private bool ValidateApiKey()
    {
        var apiKey = Request.Headers["X-Api-Key"].FirstOrDefault();
        
        // قراءة من الإعدادات أولاً، ثم Environment Variable
        var configKey = _configuration["Security:InternalApiKey"] 
            ?? Environment.GetEnvironmentVariable("SADARA_INTERNAL_API_KEY")
            ?? "sadara-internal-2024-secure-key"; // fallback للتطوير فقط - يجب إزالته في الإنتاج
        
        return !string.IsNullOrEmpty(apiKey) && apiKey == configKey;
    }

    // ═══════════════════════════════════════════════════════
    // مساعدات فلترة الصلاحيات حسب صلاحيات الشركة
    // ═══════════════════════════════════════════════════════

    /// <summary>
    /// تحويل JSON string إلى Dictionary&lt;string, bool&gt;
    /// </summary>
    private static Dictionary<string, bool> DeserializeBoolDict(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new();
        try { return JsonSerializer.Deserialize<Dictionary<string, bool>>(json) ?? new(); }
        catch { return new(); }
    }

    /// <summary>
    /// تحويل JSON string إلى Dictionary&lt;string, Dictionary&lt;string, bool&gt;&gt;
    /// </summary>
    private static Dictionary<string, Dictionary<string, bool>> DeserializeV2Dict(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new();
        try { return JsonSerializer.Deserialize<Dictionary<string, Dictionary<string, bool>>>(json) ?? new(); }
        catch { return new(); }
    }

    /// <summary>
    /// فلترة صلاحيات V1 للموظف: يُسمح فقط بالصلاحيات المفعلة للشركة
    /// </summary>
    private static Dictionary<string, bool> FilterPermissionsByCompany(
        Dictionary<string, bool> requested,
        Dictionary<string, bool> companyFeatures)
    {
        var result = new Dictionary<string, bool>();
        foreach (var kvp in requested)
        {
            // إذا الشركة لديها هذه الميزة مفعلة → نقبل قيمة الموظف
            // إذا الشركة ليس لديها هذه الميزة → نفرض false
            if (companyFeatures.TryGetValue(kvp.Key, out var companyHas) && companyHas)
                result[kvp.Key] = kvp.Value;
            else
                result[kvp.Key] = false;
        }
        return result;
    }

    /// <summary>
    /// فلترة صلاحيات V2 للموظف: يُسمح فقط بالإجراءات المفعلة للشركة
    /// إذا الشركة ليس لديها V2 لكن لديها V1 مفعل، نسمح بالإجراءات
    /// </summary>
    private static Dictionary<string, Dictionary<string, bool>> FilterPermissionsV2ByCompany(
        Dictionary<string, Dictionary<string, bool>> requested,
        Dictionary<string, Dictionary<string, bool>> companyV2,
        Dictionary<string, bool> companyV1)
    {
        var result = new Dictionary<string, Dictionary<string, bool>>();
        foreach (var module in requested)
        {
            var filteredActions = new Dictionary<string, bool>();

            // هل الشركة لديها V2 لهذه الوحدة؟
            if (companyV2.TryGetValue(module.Key, out var companyActions))
            {
                // فلترة كل إجراء حسب ما هو مفعل للشركة
                foreach (var action in module.Value)
                {
                    if (companyActions.TryGetValue(action.Key, out var allowed) && allowed)
                        filteredActions[action.Key] = action.Value;
                    else
                        filteredActions[action.Key] = false;
                }
            }
            // fallback: إذا الشركة لديها V1 مفعل لهذه الوحدة، نسمح
            else if (companyV1.TryGetValue(module.Key, out var v1Enabled) && v1Enabled)
            {
                filteredActions = new Dictionary<string, bool>(module.Value);
            }
            else
            {
                // الشركة ليس لديها هذه الميزة أصلاً → كل الإجراءات false
                foreach (var action in module.Value)
                    filteredActions[action.Key] = false;
            }

            result[module.Key] = filteredActions;
        }
        return result;
    }

    /// <summary>
    /// الحصول على جميع الشركات
    /// </summary>
    [HttpGet("companies")]
    [AllowAnonymous]
    public async Task<IActionResult> GetCompanies()
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var now = DateTime.UtcNow;
        
        // جلب الشركات مع عدد الموظفين الفعلي
        var companiesWithEmployees = await _context.Companies
            .Where(c => !c.IsDeleted)
            .OrderByDescending(c => c.CreatedAt)
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
                c.SubscriptionStartDate,
                c.SubscriptionEndDate,
                c.MaxUsers,
                c.CreatedAt,
                c.EnabledFirstSystemFeatures,
                c.EnabledSecondSystemFeatures,
                // حساب عدد الموظفين الفعلي من قاعدة البيانات
                EmployeeCount = _context.Users.Count(u => u.CompanyId == c.Id && !u.IsDeleted)
            })
            .ToListAsync();

        // حساب الحقول المشتقة في الذاكرة
        var companies = companiesWithEmployees.Select(c => new
        {
            c.Id,
            c.Name,
            c.Code,
            c.Email,
            c.Phone,
            c.Address,
            c.City,
            c.IsActive,
            c.SubscriptionStartDate,
            c.SubscriptionEndDate,
            c.MaxUsers,
            c.CreatedAt,
            c.EnabledFirstSystemFeatures,
            c.EnabledSecondSystemFeatures,
            c.EmployeeCount,
            DaysRemaining = c.SubscriptionEndDate >= now ? (c.SubscriptionEndDate - now).Days : 0,
            IsExpired = c.SubscriptionEndDate < now,
            SubscriptionStatus = c.SubscriptionEndDate < now ? "expired" 
                : (c.SubscriptionEndDate - now).Days <= 7 ? "critical" 
                : (c.SubscriptionEndDate - now).Days <= 30 ? "warning" 
                : "active"
        }).ToList();

        return Ok(companies);
    }

    /// <summary>
    /// تحديث بيانات شركة
    /// </summary>
    [HttpPut("companies/{id}")]
    [AllowAnonymous]
    public async Task<IActionResult> UpdateCompany(Guid id, [FromBody] InternalUpdateCompanyRequest request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var company = await _unitOfWork.Companies.GetByIdAsync(id);
        if (company == null || company.IsDeleted)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        // تحديث البيانات الأساسية
        if (!string.IsNullOrEmpty(request.Name))
            company.Name = request.Name;
        if (!string.IsNullOrEmpty(request.Phone))
            company.Phone = request.Phone;
        if (!string.IsNullOrEmpty(request.Email))
            company.Email = request.Email;
        if (!string.IsNullOrEmpty(request.Address))
            company.Address = request.Address;
        if (!string.IsNullOrEmpty(request.City))
            company.City = request.City;
        if (request.MaxUsers.HasValue)
            company.MaxUsers = request.MaxUsers.Value;
        if (request.SubscriptionEndDate.HasValue)
            company.SubscriptionEndDate = request.SubscriptionEndDate.Value;
        if (request.IsActive.HasValue)
            company.IsActive = request.IsActive.Value;

        // تحديث الصلاحيات
        if (request.EnabledFirstSystemFeatures != null)
            company.EnabledFirstSystemFeatures = System.Text.Json.JsonSerializer.Serialize(request.EnabledFirstSystemFeatures);
        if (request.EnabledSecondSystemFeatures != null)
            company.EnabledSecondSystemFeatures = System.Text.Json.JsonSerializer.Serialize(request.EnabledSecondSystemFeatures);

        company.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Companies.Update(company);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { 
            success = true, 
            message = "تم تحديث بيانات الشركة بنجاح",
            data = new {
                company.Id,
                company.Name,
                company.Code,
                company.Email,
                company.Phone,
                company.Address,
                company.City,
                company.IsActive,
                company.MaxUsers,
                company.SubscriptionEndDate,
                company.EnabledFirstSystemFeatures,
                company.EnabledSecondSystemFeatures
            }
        });
    }

    /// <summary>
    /// تعليق شركة
    /// </summary>
    [HttpPatch("companies/{id}/suspend")]
    [AllowAnonymous]
    public async Task<IActionResult> SuspendCompany(Guid id, [FromBody] SuspendCompanyRequest? request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var company = await _unitOfWork.Companies.GetByIdAsync(id);
        if (company == null || company.IsDeleted)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        company.IsActive = false;
        company.SuspensionReason = request?.Reason ?? "تم التعليق من لوحة التحكم";
        company.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Companies.Update(company);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تعليق الشركة بنجاح" });
    }

    /// <summary>
    /// تفعيل شركة
    /// </summary>
    [HttpPatch("companies/{id}/activate")]
    [AllowAnonymous]
    public async Task<IActionResult> ActivateCompany(Guid id)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var company = await _unitOfWork.Companies.GetByIdAsync(id);
        if (company == null || company.IsDeleted)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        company.IsActive = true;
        company.SuspensionReason = null;
        company.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Companies.Update(company);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تفعيل الشركة بنجاح" });
    }

    /// <summary>
    /// تحديث صلاحيات شركة
    /// </summary>
    [HttpPut("companies/{id}/permissions")]
    [AllowAnonymous]
    public async Task<IActionResult> UpdateCompanyPermissions(Guid id, [FromBody] InternalUpdatePermissionsRequest request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var company = await _unitOfWork.Companies.GetByIdAsync(id);
        if (company == null || company.IsDeleted)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        // تحديث صلاحيات النظام الأول
        if (request.EnabledFirstSystemFeatures != null)
            company.EnabledFirstSystemFeatures = System.Text.Json.JsonSerializer.Serialize(request.EnabledFirstSystemFeatures);

        // تحديث صلاحيات النظام الثاني
        if (request.EnabledSecondSystemFeatures != null)
            company.EnabledSecondSystemFeatures = System.Text.Json.JsonSerializer.Serialize(request.EnabledSecondSystemFeatures);

        company.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Companies.Update(company);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { 
            success = true, 
            message = "تم تحديث صلاحيات الشركة بنجاح",
            data = new {
                company.Id,
                company.Name,
                company.EnabledFirstSystemFeatures,
                company.EnabledSecondSystemFeatures
            }
        });
    }

    // ==========================================
    // V2 - صلاحيات الشركة المفصلة (إجراءات)
    // ==========================================

    /// <summary>
    /// الحصول على صلاحيات V2 للشركة (مع إجراءات مفصلة)
    /// </summary>
    [HttpGet("companies/{id}/permissions-v2")]
    [AllowAnonymous]
    public async Task<IActionResult> GetCompanyPermissionsV2(Guid id)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var company = await _unitOfWork.Companies.GetByIdAsync(id);
        if (company == null || company.IsDeleted)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        return Ok(new { 
            success = true, 
            data = new {
                company.Id,
                company.Name,
                // V1 - للتوافق العكسي
                company.EnabledFirstSystemFeatures,
                company.EnabledSecondSystemFeatures,
                // V2 - الجديد
                company.EnabledFirstSystemFeaturesV2,
                company.EnabledSecondSystemFeaturesV2
            }
        });
    }

    /// <summary>
    /// تحديث صلاحيات V2 للشركة (مع إجراءات مفصلة)
    /// </summary>
    [HttpPut("companies/{id}/permissions-v2")]
    [AllowAnonymous]
    public async Task<IActionResult> UpdateCompanyPermissionsV2(Guid id, [FromBody] InternalUpdatePermissionsV2Request request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var company = await _unitOfWork.Companies.GetByIdAsync(id);
        if (company == null || company.IsDeleted)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        // تحديث صلاحيات V2 للنظام الأول
        if (request.EnabledFirstSystemFeaturesV2 != null)
            company.EnabledFirstSystemFeaturesV2 = System.Text.Json.JsonSerializer.Serialize(request.EnabledFirstSystemFeaturesV2);

        // تحديث صلاحيات V2 للنظام الثاني
        if (request.EnabledSecondSystemFeaturesV2 != null)
            company.EnabledSecondSystemFeaturesV2 = System.Text.Json.JsonSerializer.Serialize(request.EnabledSecondSystemFeaturesV2);

        company.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Companies.Update(company);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { 
            success = true, 
            message = "تم تحديث صلاحيات V2 للشركة بنجاح",
            data = new {
                company.Id,
                company.Name,
                company.EnabledFirstSystemFeaturesV2,
                company.EnabledSecondSystemFeaturesV2
            }
        });
    }

    /// <summary>
    /// تجديد اشتراك شركة
    /// </summary>
    [HttpPatch("companies/{id}/renew")]
    [AllowAnonymous]
    public async Task<IActionResult> RenewCompanySubscription(Guid id, [FromBody] InternalRenewSubscriptionRequest request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var company = await _unitOfWork.Companies.GetByIdAsync(id);
        if (company == null || company.IsDeleted)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        if (request.NewEndDate.HasValue)
        {
            company.SubscriptionEndDate = request.NewEndDate.Value;
        }
        else if (request.Months.HasValue && request.Months.Value > 0)
        {
            var baseDate = company.SubscriptionEndDate > DateTime.UtcNow 
                ? company.SubscriptionEndDate 
                : DateTime.UtcNow;
            company.SubscriptionEndDate = baseDate.AddMonths(request.Months.Value);
        }

        company.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Companies.Update(company);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { 
            success = true, 
            message = "تم تجديد الاشتراك بنجاح",
            newEndDate = company.SubscriptionEndDate
        });
    }

    /// <summary>
    /// حذف شركة (Soft Delete)
    /// </summary>
    [HttpDelete("companies/{id}")]
    [AllowAnonymous]
    public async Task<IActionResult> DeleteCompany(Guid id)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var company = await _unitOfWork.Companies.GetByIdAsync(id);
        if (company == null || company.IsDeleted)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        company.IsDeleted = true;
        company.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Companies.Update(company);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم حذف الشركة بنجاح" });
    }



    /// <summary>
    /// الحصول على موظفي شركة معينة
    /// </summary>
    [HttpGet("companies/{id}/employees")]
    [AllowAnonymous]
    public async Task<IActionResult> GetCompanyEmployees(Guid id)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var company = await _unitOfWork.Companies.GetByIdAsync(id);
        if (company == null || company.IsDeleted)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        var employees = await _unitOfWork.Users.AsQueryable()
            .Where(u => u.CompanyId == id && !u.IsDeleted)
            .OrderBy(u => u.FullName)
            .Select(u => new
            {
                u.Id,
                u.FullName,
                u.PhoneNumber,
                u.Email,
                Role = u.Role.ToString(),
                u.Department,
                u.EmployeeCode,
                u.Center,
                u.Salary,
                u.IsActive,
                u.FirstSystemPermissions,
                u.SecondSystemPermissions,
                u.CreatedAt,
                u.FtthUsername,
            })
            .ToListAsync();

        return Ok(new { success = true, data = employees, total = employees.Count });
    }

    /// <summary>
    /// الحصول على موظف بالمعرف
    /// </summary>
    [HttpGet("companies/{id}/employees/{employeeId}")]
    [AllowAnonymous]
    public async Task<IActionResult> GetCompanyEmployeeById(Guid id, Guid employeeId)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var employee = await _unitOfWork.Users.AsQueryable()
            .FirstOrDefaultAsync(u => u.Id == employeeId && u.CompanyId == id && !u.IsDeleted);

        if (employee == null)
            return NotFound(new { success = false, message = "الموظف غير موجود" });

        return Ok(new
        {
            success = true,
            data = new
            {
                employee.Id,
                employee.FullName,
                employee.PhoneNumber,
                employee.Email,
                Role = employee.Role.ToString(),
                employee.Department,
                employee.EmployeeCode,
                employee.Center,
                employee.Salary,
                employee.IsActive,
                employee.FirstSystemPermissions,
                employee.SecondSystemPermissions,
                employee.CreatedAt,
                // HR fields
                employee.NationalId,
                employee.DateOfBirth,
                employee.HireDate,
                employee.ContractType,
                employee.BankAccountNumber,
                employee.BankName,
                employee.EmergencyContactName,
                employee.EmergencyContactPhone,
                employee.HrNotes,
                // Schedule fields
                employee.WorkScheduleId,
                CustomWorkStartTime = employee.CustomWorkStartTime?.ToString("HH:mm"),
                CustomWorkEndTime = employee.CustomWorkEndTime?.ToString("HH:mm"),
                // Attendance security code
                employee.AttendanceSecurityCode,
                // FTTH Integration
                employee.FtthUsername,
                employee.FtthPasswordEncrypted,
                // كلمة المرور (للإدارة الداخلية فقط)
                employee.PlainPassword,
            }
        });
    }

    /// <summary>
    /// تحديث بيانات موظف
    /// </summary>
    [HttpPut("companies/{id}/employees/{employeeId}")]
    [AllowAnonymous]
    public async Task<IActionResult> UpdateCompanyEmployee(Guid id, Guid employeeId, [FromBody] InternalUpdateEmployeeRequest request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var employee = await _unitOfWork.Users.AsQueryable()
            .FirstOrDefaultAsync(u => u.Id == employeeId && u.CompanyId == id && !u.IsDeleted);

        if (employee == null)
            return NotFound(new { success = false, message = "الموظف غير موجود" });

        // تحديث البيانات
        if (!string.IsNullOrEmpty(request.FullName))
        {
            employee.FullName = request.FullName;
            employee.Username = request.FullName;
        }
        if (!string.IsNullOrEmpty(request.PhoneNumber))
            employee.PhoneNumber = request.PhoneNumber;
        if (!string.IsNullOrEmpty(request.Email))
            employee.Email = request.Email;
        if (!string.IsNullOrEmpty(request.Department))
            employee.Department = request.Department;
        if (!string.IsNullOrEmpty(request.EmployeeCode))
            employee.EmployeeCode = request.EmployeeCode;
        if (!string.IsNullOrEmpty(request.Center))
            employee.Center = request.Center;
        if (request.Salary.HasValue)
            employee.Salary = request.Salary;
        if (!string.IsNullOrEmpty(request.Role))
        {
            employee.Role = request.Role?.ToLower() switch
            {
                "admin" or "companyadmin" => UserRole.CompanyAdmin,
                "manager" => UserRole.Manager,
                "technicalleader" => UserRole.TechnicalLeader,
                "technician" => UserRole.Technician,
                "viewer" => UserRole.Viewer,
                "employee" => UserRole.Employee,
                _ => employee.Role // keep current if unknown
            };
        }
        if (request.IsActive.HasValue)
            employee.IsActive = request.IsActive.Value;

        // HR fields
        if (request.NationalId != null)
            employee.NationalId = request.NationalId;
        if (request.DateOfBirth != null && DateTime.TryParse(request.DateOfBirth, out var dob))
            employee.DateOfBirth = DateTime.SpecifyKind(dob, DateTimeKind.Utc);
        if (request.HireDate != null && DateTime.TryParse(request.HireDate, out var hire))
            employee.HireDate = DateTime.SpecifyKind(hire, DateTimeKind.Utc);
        if (request.ContractType != null)
            employee.ContractType = request.ContractType;
        if (request.BankAccountNumber != null)
            employee.BankAccountNumber = request.BankAccountNumber;
        if (request.BankName != null)
            employee.BankName = request.BankName;
        if (request.EmergencyContactName != null)
            employee.EmergencyContactName = request.EmergencyContactName;
        if (request.EmergencyContactPhone != null)
            employee.EmergencyContactPhone = request.EmergencyContactPhone;
        if (request.HrNotes != null)
            employee.HrNotes = request.HrNotes;

        // Schedule fields
        if (request.WorkScheduleId.HasValue)
            employee.WorkScheduleId = request.WorkScheduleId.Value == 0 ? null : request.WorkScheduleId.Value;
        if (request.CustomWorkStartTime != null)
        {
            if (string.IsNullOrEmpty(request.CustomWorkStartTime))
                employee.CustomWorkStartTime = null;
            else if (TimeOnly.TryParse(request.CustomWorkStartTime, out var startTime))
                employee.CustomWorkStartTime = startTime;
        }
        if (request.CustomWorkEndTime != null)
        {
            if (string.IsNullOrEmpty(request.CustomWorkEndTime))
                employee.CustomWorkEndTime = null;
            else if (TimeOnly.TryParse(request.CustomWorkEndTime, out var endTime))
                employee.CustomWorkEndTime = endTime;
        }

        // Password fields
        if (!string.IsNullOrEmpty(request.NewPassword) && request.NewPassword.Length >= 4)
        {
            employee.PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.NewPassword);
            employee.PlainPassword = request.NewPassword;
        }
        if (request.FtthPassword != null)
            employee.FtthPasswordEncrypted = request.FtthPassword;

        // Attendance security code — with uniqueness check
        if (request.AttendanceSecurityCode != null)
        {
            var newCode = request.AttendanceSecurityCode.Trim();
            if (!string.IsNullOrEmpty(newCode))
            {
                var duplicate = await _unitOfWork.Users.AsQueryable()
                    .AnyAsync(u => u.CompanyId == id && !u.IsDeleted
                        && u.Id != employeeId
                        && u.AttendanceSecurityCode == newCode);
                if (duplicate)
                    return BadRequest(new { success = false, message = $"كود الأمان '{newCode}' مستخدم بالفعل لموظف آخر" });
            }
            employee.AttendanceSecurityCode = string.IsNullOrEmpty(newCode) ? null : newCode;
        }

        employee.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Users.Update(employee);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تحديث بيانات الموظف بنجاح" });
    }

    /// <summary>
    /// تغيير كلمة مرور موظف
    /// </summary>
    [HttpPatch("companies/{id}/employees/{employeeId}/password")]
    [AllowAnonymous]
    public async Task<IActionResult> UpdateEmployeePassword(Guid id, Guid employeeId, [FromBody] InternalUpdatePasswordRequest request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var employee = await _unitOfWork.Users.AsQueryable()
            .FirstOrDefaultAsync(u => u.Id == employeeId && u.CompanyId == id && !u.IsDeleted);

        if (employee == null)
            return NotFound(new { success = false, message = "الموظف غير موجود" });

        if (string.IsNullOrEmpty(request.NewPassword) || request.NewPassword.Length < 6)
            return BadRequest(new { success = false, message = "كلمة المرور يجب أن تكون 6 أحرف على الأقل" });

        employee.PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.NewPassword);
        employee.PlainPassword = request.NewPassword;
        employee.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Users.Update(employee);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تغيير كلمة المرور بنجاح" });
    }

    /// <summary>
    /// تحديث صلاحيات موظف
    /// </summary>
    [HttpPut("companies/{id}/employees/{employeeId}/permissions")]
    [AllowAnonymous]
    public async Task<IActionResult> UpdateEmployeePermissions(Guid id, Guid employeeId, [FromBody] InternalUpdateEmployeePermissionsRequest request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var company = await _unitOfWork.Companies.GetByIdAsync(id);
        if (company == null || company.IsDeleted)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        var employee = await _unitOfWork.Users.AsQueryable()
            .FirstOrDefaultAsync(u => u.Id == employeeId && u.CompanyId == id && !u.IsDeleted);

        if (employee == null)
            return NotFound(new { success = false, message = "الموظف غير موجود" });

        // ═══ فلترة الصلاحيات: لا يمكن منح صلاحية غير ممنوحة للشركة ═══
        var companyFirstFeatures = DeserializeBoolDict(company.EnabledFirstSystemFeatures);
        var companySecondFeatures = DeserializeBoolDict(company.EnabledSecondSystemFeatures);

        // تحديث صلاحيات النظام الأول (مفلترة)
        if (request.FirstSystemPermissions != null)
        {
            var filtered = FilterPermissionsByCompany(request.FirstSystemPermissions, companyFirstFeatures);
            employee.FirstSystemPermissions = JsonSerializer.Serialize(filtered);
        }

        // تحديث صلاحيات النظام الثاني (مفلترة)
        if (request.SecondSystemPermissions != null)
        {
            var filtered = FilterPermissionsByCompany(request.SecondSystemPermissions, companySecondFeatures);
            employee.SecondSystemPermissions = JsonSerializer.Serialize(filtered);
        }

        employee.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Users.Update(employee);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { 
            success = true, 
            message = "تم تحديث صلاحيات الموظف بنجاح",
            data = new {
                employee.Id,
                employee.FullName,
                employee.FirstSystemPermissions,
                employee.SecondSystemPermissions
            }
        });
    }

    // ==========================================
    // V2 - صلاحيات الموظف المفصلة (إجراءات)
    // ==========================================

    /// <summary>
    /// الحصول على صلاحيات V2 للموظف
    /// </summary>
    [HttpGet("companies/{id}/employees/{employeeId}/permissions-v2")]
    [AllowAnonymous]
    public async Task<IActionResult> GetEmployeePermissionsV2(Guid id, Guid employeeId)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var employee = await _unitOfWork.Users.AsQueryable()
            .FirstOrDefaultAsync(u => u.Id == employeeId && u.CompanyId == id && !u.IsDeleted);

        if (employee == null)
            return NotFound(new { success = false, message = "الموظف غير موجود" });

        return Ok(new { 
            success = true, 
            data = new {
                employee.Id,
                employee.FullName,
                // V1 - للتوافق العكسي
                employee.FirstSystemPermissions,
                employee.SecondSystemPermissions,
                // V2 - الجديد
                employee.FirstSystemPermissionsV2,
                employee.SecondSystemPermissionsV2
            }
        });
    }

    /// <summary>
    /// تحديث صلاحيات V2 للموظف (مع إجراءات مفصلة)
    /// </summary>
    [HttpPut("companies/{id}/employees/{employeeId}/permissions-v2")]
    [AllowAnonymous]
    public async Task<IActionResult> UpdateEmployeePermissionsV2(Guid id, Guid employeeId, [FromBody] InternalUpdateEmployeePermissionsV2Request request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var company = await _unitOfWork.Companies.GetByIdAsync(id);
        if (company == null || company.IsDeleted)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        var employee = await _unitOfWork.Users.AsQueryable()
            .FirstOrDefaultAsync(u => u.Id == employeeId && u.CompanyId == id && !u.IsDeleted);

        if (employee == null)
            return NotFound(new { success = false, message = "الموظف غير موجود" });

        // ═══ فلترة الصلاحيات V2: لا يمكن منح إجراء غير مفعل للشركة ═══
        var companyFirstV2 = DeserializeV2Dict(company.EnabledFirstSystemFeaturesV2);
        var companySecondV2 = DeserializeV2Dict(company.EnabledSecondSystemFeaturesV2);
        var companyFirstV1 = DeserializeBoolDict(company.EnabledFirstSystemFeatures);
        var companySecondV1 = DeserializeBoolDict(company.EnabledSecondSystemFeatures);

        // تحديث صلاحيات V2 للنظام الأول (مفلترة)
        if (request.FirstSystemPermissionsV2 != null)
        {
            var filtered = FilterPermissionsV2ByCompany(request.FirstSystemPermissionsV2, companyFirstV2, companyFirstV1);
            employee.FirstSystemPermissionsV2 = JsonSerializer.Serialize(filtered);
        }

        // تحديث صلاحيات V2 للنظام الثاني (مفلترة)
        if (request.SecondSystemPermissionsV2 != null)
        {
            var filtered = FilterPermissionsV2ByCompany(request.SecondSystemPermissionsV2, companySecondV2, companySecondV1);
            employee.SecondSystemPermissionsV2 = JsonSerializer.Serialize(filtered);
        }

        employee.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Users.Update(employee);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { 
            success = true, 
            message = "تم تحديث صلاحيات V2 للموظف بنجاح",
            data = new {
                employee.Id,
                employee.FullName,
                employee.FirstSystemPermissionsV2,
                employee.SecondSystemPermissionsV2
            }
        });
    }

    /// <summary>
    /// حذف موظف
    /// </summary>
    [HttpDelete("companies/{id}/employees/{employeeId}")]
    [AllowAnonymous]
    public async Task<IActionResult> DeleteCompanyEmployee(Guid id, Guid employeeId)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var employee = await _unitOfWork.Users.AsQueryable()
            .FirstOrDefaultAsync(u => u.Id == employeeId && u.CompanyId == id && !u.IsDeleted);

        if (employee == null)
            return NotFound(new { success = false, message = "الموظف غير موجود" });

        employee.IsDeleted = true;
        employee.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Users.Update(employee);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم حذف الموظف بنجاح" });
    }

    // ══════════════════════════════════════
    // قوالب الصلاحيات المخصصة للشركة
    // ══════════════════════════════════════

    /// <summary>جلب قوالب الصلاحيات المخصصة للشركة</summary>
    [HttpGet("companies/{id}/permission-templates")]
    [AllowAnonymous]
    public async Task<IActionResult> GetPermissionTemplates(Guid id)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var company = await _unitOfWork.Companies.GetByIdAsync(id);
        if (company == null || company.IsDeleted)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        return Ok(new
        {
            success = true,
            data = company.CustomPermissionTemplates
        });
    }

    /// <summary>حفظ قوالب الصلاحيات المخصصة للشركة (مدير الشركة فقط)</summary>
    [HttpPut("companies/{id}/permission-templates")]
    [AllowAnonymous]
    public async Task<IActionResult> SavePermissionTemplates(Guid id, [FromBody] SaveTemplatesRequest request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var company = await _unitOfWork.Companies.GetByIdAsync(id);
        if (company == null || company.IsDeleted)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        company.CustomPermissionTemplates = request.Templates;
        company.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Companies.Update(company);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم حفظ القوالب بنجاح" });
    }

    /// <summary>
    /// إضافة موظف جديد للشركة
    /// </summary>
    [HttpPost("companies/{id}/employees")]
    [AllowAnonymous]
    public async Task<IActionResult> CreateCompanyEmployee(Guid id, [FromBody] InternalCreateEmployeeRequest request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var company = await _unitOfWork.Companies.GetByIdAsync(id);
        if (company == null || company.IsDeleted)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        // التحقق من الحد الأقصى للموظفين
        var currentCount = await _unitOfWork.Users.AsQueryable()
            .CountAsync(u => u.CompanyId == id && !u.IsDeleted);
        if (currentCount >= company.MaxUsers)
            return BadRequest(new { success = false, message = $"تم الوصول للحد الأقصى للموظفين ({company.MaxUsers})" });

        // التحقق من رقم الهاتف
        var existingPhone = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.PhoneNumber == request.PhoneNumber && !u.IsDeleted);
        if (existingPhone != null)
            return BadRequest(new { success = false, message = "رقم الهاتف مستخدم بالفعل" });

        // التحقق من البريد الإلكتروني
        if (!string.IsNullOrEmpty(request.Email))
        {
            var existingEmail = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.Email == request.Email && !u.IsDeleted);
            if (existingEmail != null)
                return BadRequest(new { success = false, message = "البريد الإلكتروني مستخدم بالفعل" });
        }

        // توليد كود أمان بصمة فريد تلقائياً
        var securityCode = await GenerateUniqueSecurityCodeAsync(id);

        var employee = new Sadara.Domain.Entities.User
        {
            Id = Guid.NewGuid(),
            FullName = request.FullName,
            Username = request.FullName,
            PhoneNumber = request.PhoneNumber,
            Email = request.Email,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password ?? "123456"),
            Role = ParseUserRole(request.Role ?? "Employee"),
            CompanyId = id,
            Department = request.Department,
            EmployeeCode = request.EmployeeCode ?? GenerateEmployeeCode(),
            Center = request.Center,
            Salary = request.Salary,
            AttendanceSecurityCode = securityCode,
            IsActive = true,
            IsPhoneVerified = true,
            CreatedAt = DateTime.UtcNow
        };

        await _unitOfWork.Users.AddAsync(employee);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new
        {
            success = true,
            message = "تم إضافة الموظف بنجاح",
            data = new
            {
                employee.Id,
                employee.FullName,
                employee.PhoneNumber,
                employee.Email,
                Role = employee.Role.ToString(),
                employee.Department,
                employee.EmployeeCode,
                employee.Center,
                employee.Salary,
                employee.AttendanceSecurityCode,
                employee.IsActive,
                employee.CreatedAt
            }
        });
    }

    private Sadara.Domain.Enums.UserRole ParseUserRole(string role)
    {
        return role?.ToLower() switch
        {
            "admin" or "companyadmin" => Sadara.Domain.Enums.UserRole.CompanyAdmin,
            "manager" => Sadara.Domain.Enums.UserRole.Manager,
            "technician" => Sadara.Domain.Enums.UserRole.Technician,
            "technicalleader" or "leader" => Sadara.Domain.Enums.UserRole.TechnicalLeader,
            "viewer" => Sadara.Domain.Enums.UserRole.Viewer,
            _ => Sadara.Domain.Enums.UserRole.Employee
        };
    }

    private string GenerateEmployeeCode()
    {
        return $"EMP-{DateTime.UtcNow:yyMMdd}-{new Random().Next(1000, 9999)}";
    }

    /// <summary>توليد كود أمان بصمة فريد (4 أرقام)</summary>
    private async Task<string> GenerateUniqueSecurityCodeAsync(Guid companyId)
    {
        var existingCodes = await _unitOfWork.Users.AsQueryable()
            .Where(u => u.CompanyId == companyId && !u.IsDeleted && u.AttendanceSecurityCode != null)
            .Select(u => u.AttendanceSecurityCode!)
            .ToListAsync();

        var rng = new Random();
        string code;
        do
        {
            code = rng.Next(1000, 9999).ToString();
        } while (existingCodes.Contains(code));

        return code;
    }



    /// <summary>
    /// الحصول على جميع المستخدمين
    /// </summary>
    [HttpGet("users")]
    [AllowAnonymous]
    public async Task<IActionResult> GetUsers()
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var users = await _unitOfWork.Users.AsQueryable()
            .Where(u => !u.IsDeleted)
            .OrderByDescending(u => u.CreatedAt)
            .Select(u => new
            {
                u.Id,
                u.FullName,
                u.Username,
                u.FtthUsername,
                u.PhoneNumber,
                u.Email,
                u.Role,
                u.IsActive,
                u.CompanyId,
                u.CreatedAt
            })
            .ToListAsync();

        return Ok(users);
    }

    /// <summary>
    /// الحصول على جميع العملاء
    /// </summary>
    [HttpGet("customers")]
    [AllowAnonymous]
    public async Task<IActionResult> GetCustomers()
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var customers = await _unitOfWork.Customers.AsQueryable()
            .Where(c => !c.IsDeleted)
            .OrderByDescending(c => c.CreatedAt)
            .Select(c => new
            {
                c.Id,
                c.FullName,
                c.PhoneNumber,
                c.Email,
                c.City,
                c.Area,
                c.IsActive,
                c.CreatedAt
            })
            .ToListAsync();

        return Ok(customers);
    }

    /// <summary>
    /// الحصول على جميع التجار
    /// </summary>
    [HttpGet("merchants")]
    [AllowAnonymous]
    public async Task<IActionResult> GetMerchants()
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var merchants = await _unitOfWork.Merchants.AsQueryable()
            .Where(m => !m.IsDeleted)
            .OrderByDescending(m => m.CreatedAt)
            .Select(m => new
            {
                m.Id,
                m.BusinessName,
                m.PhoneNumber,
                m.Email,
                m.IsActive,
                m.IsVerified,
                m.CreatedAt
            })
            .ToListAsync();

        return Ok(merchants);
    }

    /// <summary>
    /// الحصول على جميع المنتجات
    /// </summary>
    [HttpGet("products")]
    [AllowAnonymous]
    public async Task<IActionResult> GetProducts()
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var products = await _unitOfWork.Products.AsQueryable()
            .Where(p => !p.IsDeleted)
            .OrderByDescending(p => p.CreatedAt)
            .Select(p => new
            {
                p.Id,
                p.Name,
                p.NameAr,
                p.Price,
                p.DiscountPrice,
                p.StockQuantity,
                p.IsActive,
                p.CategoryId,
                p.MerchantId,
                p.CreatedAt
            })
            .Take(500)
            .ToListAsync();

        return Ok(products);
    }

    /// <summary>
    /// الحصول على جميع الطلبات
    /// </summary>
    [HttpGet("orders")]
    [AllowAnonymous]
    public async Task<IActionResult> GetOrders()
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var orders = await _unitOfWork.Orders.AsQueryable()
            .OrderByDescending(o => o.CreatedAt)
            .Select(o => new
            {
                o.Id,
                o.OrderNumber,
                o.Status,
                o.TotalAmount,
                o.CustomerId,
                o.MerchantId,
                o.CreatedAt
            })
            .Take(500)
            .ToListAsync();

        return Ok(orders);
    }

    /// <summary>
    /// الحصول على المدن
    /// </summary>
    [HttpGet("cities")]
    [AllowAnonymous]
    public async Task<IActionResult> GetCities()
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var cities = await _unitOfWork.Cities.AsQueryable()
            .Where(c => !c.IsDeleted)
            .OrderBy(c => c.NameAr)
            .Select(c => new
            {
                c.Id,
                c.Name,
                c.NameAr,
                c.IsActive
            })
            .ToListAsync();

        return Ok(cities);
    }

    /// <summary>
    /// الحصول على طلبات الخدمة
    /// </summary>
    [HttpGet("servicerequests")]
    [AllowAnonymous]
    public async Task<IActionResult> GetServiceRequests()
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var requests = await _unitOfWork.ServiceRequests.AsQueryable()
            .OrderByDescending(r => r.CreatedAt)
            .Select(r => new
            {
                r.Id,
                r.RequestNumber,
                r.Status,
                r.City,
                r.CitizenId,
                r.CompanyId,
                r.CreatedAt
            })
            .Take(500)
            .ToListAsync();

        return Ok(requests);
    }

    /// <summary>
    /// <summary>
    /// اختبار الاتصال
    /// </summary>
    [HttpGet("ping")]
    [AllowAnonymous]
    public IActionResult Ping()
    {
        return Ok(new { 
            success = true, 
            message = "Sadara Internal API is running",
            timestamp = DateTime.UtcNow,
            version = "1.0"
        });
    }

    // ============= CRUD Operations =============

    /// <summary>
    /// إضافة عميل جديد
    /// </summary>
    [HttpPost("customers")]
    [AllowAnonymous]
    public async Task<IActionResult> CreateCustomer([FromBody] CreateCustomerDto dto)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            // البحث عن أول تاجر أو إنشاء واحد افتراضي
            var merchant = await _unitOfWork.Merchants.AsQueryable()
                .FirstOrDefaultAsync(m => !m.IsDeleted);
            
            if (merchant == null)
            {
                // البحث عن مستخدم افتراضي لربط التاجر به
                var defaultUser = await _unitOfWork.Users.AsQueryable()
                    .FirstOrDefaultAsync(u => !u.IsDeleted);
                
                if (defaultUser == null)
                {
                    return BadRequest(new { success = false, message = "لا يوجد مستخدم لربط التاجر به. يرجى إنشاء مستخدم أولاً." });
                }

                // إنشاء تاجر افتراضي إذا لم يوجد
                merchant = new Sadara.Domain.Entities.Merchant
                {
                    BusinessName = "تاجر افتراضي",
                    PhoneNumber = "0000000000",
                    Email = "default@merchant.com",
                    City = "غير محدد",
                    UserId = defaultUser.Id,
                    IsActive = true,
                    IsVerified = true,
                    CreatedAt = DateTime.UtcNow
                };
                await _unitOfWork.Merchants.AddAsync(merchant);
                await _unitOfWork.SaveChangesAsync();
            }

            var customer = new Sadara.Domain.Entities.Customer
            {
                FullName = dto.Name ?? dto.FullName ?? "عميل جديد",
                PhoneNumber = dto.PhoneNumber ?? "",
                Email = dto.Email ?? "",
                City = dto.City ?? "",
                Area = dto.Area ?? "",
                MerchantId = merchant.Id,
                CustomerCode = $"CUS{DateTime.UtcNow:yyyyMMddHHmmss}",
                IsActive = true,
                CreatedAt = DateTime.UtcNow
            };

            await _unitOfWork.Customers.AddAsync(customer);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم إضافة العميل بنجاح", id = customer.Id });
        }
        catch (Exception ex)
        {
            return BadRequest(new { success = false, message = ex.Message });
        }
    }

    /// <summary>
    /// تعديل عميل
    /// </summary>
    [HttpPut("customers/{id}")]
    [AllowAnonymous]
    public async Task<IActionResult> UpdateCustomer(int id, [FromBody] CreateCustomerDto dto)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var customer = await _unitOfWork.Customers.GetByIdAsync(id);
            if (customer == null)
                return NotFound(new { success = false, message = "العميل غير موجود" });

            if (!string.IsNullOrEmpty(dto.Name)) customer.FullName = dto.Name;
            if (!string.IsNullOrEmpty(dto.FullName)) customer.FullName = dto.FullName;
            if (!string.IsNullOrEmpty(dto.PhoneNumber)) customer.PhoneNumber = dto.PhoneNumber;
            if (!string.IsNullOrEmpty(dto.Email)) customer.Email = dto.Email;
            if (!string.IsNullOrEmpty(dto.City)) customer.City = dto.City;
            if (!string.IsNullOrEmpty(dto.Area)) customer.Area = dto.Area;

            _unitOfWork.Customers.Update(customer);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم تحديث العميل بنجاح" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { success = false, message = ex.Message });
        }
    }

    /// <summary>
    /// حذف عميل
    /// </summary>
    [HttpDelete("customers/{id}")]
    [AllowAnonymous]
    public async Task<IActionResult> DeleteCustomer(int id)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var customer = await _unitOfWork.Customers.GetByIdAsync(id);
            if (customer == null)
                return NotFound(new { success = false, message = "العميل غير موجود" });

            customer.IsDeleted = true;
            _unitOfWork.Customers.Update(customer);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم حذف العميل بنجاح" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { success = false, message = ex.Message });
        }
    }

    /// <summary>
    /// إضافة مدينة جديدة
    /// </summary>
    [HttpPost("cities")]
    [AllowAnonymous]
    public async Task<IActionResult> CreateCity([FromBody] CreateCityDto dto)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var city = new Sadara.Domain.Entities.City
            {
                Name = dto.Name ?? "",
                NameAr = dto.NameAr ?? dto.Name ?? "",
                IsActive = true,
                CreatedAt = DateTime.UtcNow
            };

            await _unitOfWork.Cities.AddAsync(city);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم إضافة المدينة بنجاح", id = city.Id });
        }
        catch (Exception ex)
        {
            return BadRequest(new { success = false, message = ex.Message });
        }
    }

    /// <summary>
    /// تعديل مدينة
    /// </summary>
    [HttpPut("cities/{id}")]
    [AllowAnonymous]
    public async Task<IActionResult> UpdateCity(Guid id, [FromBody] CreateCityDto dto)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var city = await _unitOfWork.Cities.GetByIdAsync(id);
            if (city == null)
                return NotFound(new { success = false, message = "المدينة غير موجودة" });

            if (!string.IsNullOrEmpty(dto.Name)) city.Name = dto.Name;
            if (!string.IsNullOrEmpty(dto.NameAr)) city.NameAr = dto.NameAr;

            _unitOfWork.Cities.Update(city);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم تحديث المدينة بنجاح" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { success = false, message = ex.Message });
        }
    }

    /// <summary>
    /// حذف مدينة
    /// </summary>
    [HttpDelete("cities/{id}")]
    [AllowAnonymous]
    public async Task<IActionResult> DeleteCity(Guid id)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var city = await _unitOfWork.Cities.GetByIdAsync(id);
            if (city == null)
                return NotFound(new { success = false, message = "المدينة غير موجودة" });

            city.IsDeleted = true;
            _unitOfWork.Cities.Update(city);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم حذف المدينة بنجاح" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { success = false, message = ex.Message });
        }
    }

    /// <summary>
    /// إضافة تاجر جديد
    /// </summary>
    [HttpPost("merchants")]
    [AllowAnonymous]
    public async Task<IActionResult> CreateMerchant([FromBody] CreateMerchantDto dto)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            // البحث عن مستخدم افتراضي أو إنشاء واحد
            var defaultUser = await _unitOfWork.Users.AsQueryable()
                .FirstOrDefaultAsync(u => !u.IsDeleted);
            
            Guid userId = defaultUser?.Id ?? Guid.Empty;

            var merchant = new Sadara.Domain.Entities.Merchant
            {
                BusinessName = dto.Name ?? dto.BusinessName ?? "تاجر جديد",
                PhoneNumber = dto.PhoneNumber ?? "",
                Email = dto.Email ?? "",
                City = dto.City ?? "غير محدد",
                UserId = userId,
                IsActive = true,
                IsVerified = false,
                CreatedAt = DateTime.UtcNow
            };

            await _unitOfWork.Merchants.AddAsync(merchant);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم إضافة التاجر بنجاح", id = merchant.Id });
        }
        catch (Exception ex)
        {
            return BadRequest(new { success = false, message = ex.Message });
        }
    }

    /// <summary>
    /// تعديل تاجر
    /// </summary>
    [HttpPut("merchants/{id}")]
    [AllowAnonymous]
    public async Task<IActionResult> UpdateMerchant(Guid id, [FromBody] CreateMerchantDto dto)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var merchant = await _unitOfWork.Merchants.GetByIdAsync(id);
            if (merchant == null)
                return NotFound(new { success = false, message = "التاجر غير موجود" });

            if (!string.IsNullOrEmpty(dto.Name)) merchant.BusinessName = dto.Name;
            if (!string.IsNullOrEmpty(dto.BusinessName)) merchant.BusinessName = dto.BusinessName;
            if (!string.IsNullOrEmpty(dto.PhoneNumber)) merchant.PhoneNumber = dto.PhoneNumber;
            if (!string.IsNullOrEmpty(dto.Email)) merchant.Email = dto.Email;

            _unitOfWork.Merchants.Update(merchant);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم تحديث التاجر بنجاح" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { success = false, message = ex.Message });
        }
    }

    /// <summary>
    /// حذف تاجر
    /// </summary>
    [HttpDelete("merchants/{id}")]
    [AllowAnonymous]
    public async Task<IActionResult> DeleteMerchant(Guid id)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var merchant = await _unitOfWork.Merchants.GetByIdAsync(id);
            if (merchant == null)
                return NotFound(new { success = false, message = "التاجر غير موجود" });

            merchant.IsDeleted = true;
            _unitOfWork.Merchants.Update(merchant);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم حذف التاجر بنجاح" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { success = false, message = ex.Message });
        }
    }

    /// <summary>
    /// إضافة منتج جديد
    /// </summary>
    [HttpPost("products")]
    [AllowAnonymous]
    public async Task<IActionResult> CreateProduct([FromBody] CreateProductDto dto)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            // البحث عن تاجر لربط المنتج به
            var merchant = await _unitOfWork.Merchants.AsQueryable()
                .FirstOrDefaultAsync(m => !m.IsDeleted);
            
            if (merchant == null)
            {
                return BadRequest(new { success = false, message = "يجب إنشاء تاجر أولاً قبل إضافة المنتجات" });
            }

            var product = new Sadara.Domain.Entities.Product
            {
                Name = dto.Name ?? "منتج جديد",
                NameAr = dto.NameAr ?? dto.Name ?? "منتج جديد",
                Price = dto.Price ?? 0,
                CostPrice = dto.CostPrice ?? 0,
                StockQuantity = dto.Stock ?? 0,
                SKU = dto.SKU ?? $"SKU{DateTime.UtcNow:yyyyMMddHHmmss}",
                MerchantId = merchant.Id,
                IsActive = true,
                IsAvailable = true,
                CreatedAt = DateTime.UtcNow
            };

            await _unitOfWork.Products.AddAsync(product);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم إضافة المنتج بنجاح", id = product.Id });
        }
        catch (Exception ex)
        {
            return BadRequest(new { success = false, message = ex.Message });
        }
    }

    /// <summary>
    /// تعديل منتج
    /// </summary>
    [HttpPut("products/{id}")]
    [AllowAnonymous]
    public async Task<IActionResult> UpdateProduct(Guid id, [FromBody] CreateProductDto dto)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var product = await _unitOfWork.Products.GetByIdAsync(id);
            if (product == null)
                return NotFound(new { success = false, message = "المنتج غير موجود" });

            if (!string.IsNullOrEmpty(dto.Name)) product.Name = dto.Name;
            if (!string.IsNullOrEmpty(dto.NameAr)) product.NameAr = dto.NameAr;
            if (dto.Price.HasValue) product.Price = dto.Price.Value;
            if (dto.Stock.HasValue) product.StockQuantity = dto.Stock.Value;

            _unitOfWork.Products.Update(product);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم تحديث المنتج بنجاح" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { success = false, message = ex.Message });
        }
    }

    /// <summary>
    /// حذف منتج
    /// </summary>
    [HttpDelete("products/{id}")]
    [AllowAnonymous]
    public async Task<IActionResult> DeleteProduct(Guid id)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var product = await _unitOfWork.Products.GetByIdAsync(id);
            if (product == null)
                return NotFound(new { success = false, message = "المنتج غير موجود" });

            product.IsDeleted = true;
            _unitOfWork.Products.Update(product);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم حذف المنتج بنجاح" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { success = false, message = ex.Message });
        }
    }

    // ==================== إدارة المواطنين ====================

    /// <summary>
    /// الحصول على جميع المواطنين
    /// </summary>
    /// <summary>
    /// الحصول على سجلات الاشتراكات
    /// </summary>
    [HttpGet("subscriptionlogs")]
    [AllowAnonymous]
    public async Task<IActionResult> GetSubscriptionLogs(
        [FromQuery] string? companyId,
        [FromQuery] DateTime? fromDate,
        [FromQuery] DateTime? toDate,
        [FromQuery] int pageSize = 500)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var query = _unitOfWork.SubscriptionLogs.AsQueryable()
            .Where(l => !l.IsDeleted);

        if (!string.IsNullOrEmpty(companyId) && Guid.TryParse(companyId, out var cId))
            query = query.Where(l => l.CompanyId == cId);

        if (fromDate.HasValue)
        {
            var from = DateTime.SpecifyKind(fromDate.Value.AddHours(-3), DateTimeKind.Utc);
            query = query.Where(l => l.ActivationDate >= from);
        }

        if (toDate.HasValue)
        {
            var to = DateTime.SpecifyKind(toDate.Value.AddDays(1).AddHours(-3), DateTimeKind.Utc);
            query = query.Where(l => l.ActivationDate <= to);
        }

        var effectivePageSize = Math.Min(pageSize < 1 ? 500 : pageSize, 2000);

        var logs = await query
            .OrderByDescending(l => l.ActivationDate)
            .Take(effectivePageSize)
            .Select(l => new
            {
                l.Id,
                l.CustomerId,
                l.CustomerName,
                l.PhoneNumber,
                l.SubscriptionId,
                l.PlanName,
                l.PlanPrice,
                l.CommitmentPeriod,
                l.BundleId,
                l.CurrentStatus,
                l.DeviceUsername,
                l.OperationType,
                l.ActivatedBy,
                l.ActivationDate,
                l.ZoneId,
                l.ZoneName,
                l.WalletBalanceBefore,
                l.WalletBalanceAfter,
                l.PartnerName,
                l.CompanyId,
                l.CollectionType,
                l.PaymentMethod,
                l.IsPrinted,
                l.IsWhatsAppSent,
                l.PaymentStatus,
                l.StartDate,
                l.EndDate,
                l.CreatedAt,
                l.TechnicianName,
                l.LinkedTechnicianId,
                l.LinkedAgentId,
                l.SubscriptionNotes,
                l.FbgInfo,
                l.FatInfo,
                l.FdtInfo,
                l.UserId,
                l.BasePrice,
                l.CompanyDiscount,
                l.ManualDiscount,
                l.MaintenanceFee,
                l.SystemDiscountEnabled,
                l.IsReconciled,
                l.JournalEntryId,
                l.FtthTransactionId,
            })
            .ToListAsync();

        // إضافة FtthUsername من جدول Users
        var userIds = logs.Where(l => l.UserId.HasValue).Select(l => l.UserId!.Value).Distinct().ToList();
        var userLookup = userIds.Any()
            ? await _unitOfWork.Users.AsQueryable()
                .Where(u => userIds.Contains(u.Id))
                .Select(u => new { u.Id, u.FtthUsername })
                .ToDictionaryAsync(u => u.Id, u => u.FtthUsername ?? "")
            : new Dictionary<Guid, string>();

        var result = logs.Select(l => new
        {
            l.Id, l.CustomerId, l.CustomerName, l.PhoneNumber,
            l.SubscriptionId, l.PlanName, l.PlanPrice, l.CommitmentPeriod,
            l.BundleId, l.CurrentStatus, l.DeviceUsername, l.OperationType,
            l.ActivatedBy, l.ActivationDate, l.ZoneId, l.ZoneName,
            l.WalletBalanceBefore, l.WalletBalanceAfter, l.PartnerName,
            l.CompanyId, l.CollectionType, l.PaymentMethod,
            l.IsPrinted, l.IsWhatsAppSent, l.PaymentStatus,
            l.StartDate, l.EndDate, l.CreatedAt,
            l.TechnicianName, l.LinkedTechnicianId, l.LinkedAgentId,
            l.SubscriptionNotes, l.FbgInfo, l.FatInfo, l.FdtInfo,
            l.UserId,
            l.BasePrice, l.CompanyDiscount, l.ManualDiscount,
            l.MaintenanceFee, l.SystemDiscountEnabled,
            l.IsReconciled, l.JournalEntryId, l.FtthTransactionId,
            // حقول مالية محسوبة (نفس منطق FtthAccountingController)
            PageDeduction = (l.BasePrice ?? 0) > 0
                ? (l.BasePrice ?? 0) - (l.CompanyDiscount ?? 0)
                : l.SystemDiscountEnabled
                    ? (l.PlanPrice ?? 0)
                    : (l.PlanPrice ?? 0) - (l.CompanyDiscount ?? 0),
            Revenue = (l.MaintenanceFee ?? 0) + (l.SystemDiscountEnabled ? 0 : (l.CompanyDiscount ?? 0)),
            Expense = l.ManualDiscount ?? 0,
            FtthUsername = l.UserId.HasValue && userLookup.ContainsKey(l.UserId.Value)
                ? userLookup[l.UserId.Value] : ""
        });

        return Ok(result);
    }

    /// <summary>
    /// تحديث حالة سجل اشتراك (طباعة/واتساب/ملاحظات)
    /// </summary>
    [HttpPut("subscriptionlogs/{id}")]
    [AllowAnonymous]
    [Consumes("application/json")]
    public async Task<IActionResult> UpdateSubscriptionLog(long id, [FromBody] JsonElement request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var log = await _unitOfWork.SubscriptionLogs.GetByIdAsync(id);
        if (log == null)
            return NotFound(new { success = false, message = "السجل غير موجود" });

        // تحديث الحقول المرسلة فقط
        if (request.TryGetProperty("isPrinted", out var pp) && pp.ValueKind == JsonValueKind.True)
            log.IsPrinted = true;
        if (request.TryGetProperty("isPrinted", out var ppf) && ppf.ValueKind == JsonValueKind.False)
            log.IsPrinted = false;
        if (request.TryGetProperty("isWhatsAppSent", out var pw) && pw.ValueKind == JsonValueKind.True)
            log.IsWhatsAppSent = true;
        if (request.TryGetProperty("isWhatsAppSent", out var pwf) && pwf.ValueKind == JsonValueKind.False)
            log.IsWhatsAppSent = false;
        if (request.TryGetProperty("subscriptionNotes", out var pn) && pn.ValueKind == JsonValueKind.String)
            log.SubscriptionNotes = pn.GetString();
        if (request.TryGetProperty("ActivatedBy", out var pab) && pab.ValueKind == JsonValueKind.String)
            log.ActivatedBy = pab.GetString();
        if (request.TryGetProperty("PlanPrice", out var ppr) && ppr.ValueKind == JsonValueKind.Number)
        {
            log.PlanPrice = ppr.GetDecimal();
            // تحديث BasePrice أيضاً ليطابق المستقطع الجديد
            log.BasePrice = ppr.GetDecimal();
            log.CompanyDiscount = 0;
        }
        if (request.TryGetProperty("CollectionType", out var pct) && pct.ValueKind == JsonValueKind.String)
            log.CollectionType = pct.GetString();
        if (request.TryGetProperty("TechnicianName", out var ptn) && ptn.ValueKind == JsonValueKind.String)
            log.TechnicianName = ptn.GetString();
        if (request.TryGetProperty("PaymentMethod", out var ppm) && ppm.ValueKind == JsonValueKind.String)
            log.PaymentMethod = ppm.GetString();
        if (request.TryGetProperty("ManualDiscount", out var pmd) && pmd.ValueKind == JsonValueKind.Number)
            log.ManualDiscount = pmd.GetDecimal();
        if (request.TryGetProperty("MaintenanceFee", out var pmf) && pmf.ValueKind == JsonValueKind.Number)
            log.MaintenanceFee = pmf.GetDecimal();
        if (request.TryGetProperty("PhoneNumber", out var ppn) && ppn.ValueKind == JsonValueKind.String)
            log.PhoneNumber = ppn.GetString();
        if (request.TryGetProperty("CommitmentPeriod", out var pcp) && pcp.ValueKind == JsonValueKind.Number)
            log.CommitmentPeriod = pcp.GetInt32();

        // ═══ تحديث الفني/الوكيل المرتبط + تعديل القيد المحاسبي ═══
        Guid? newLinkedTechnicianId = null;
        Guid? newLinkedAgentId = null;
        bool technicianChanged = false;
        bool agentChanged = false;

        if (request.TryGetProperty("LinkedTechnicianId", out var pLt) && pLt.ValueKind == JsonValueKind.String && Guid.TryParse(pLt.GetString(), out var ltGuid))
        {
            if (log.LinkedTechnicianId != ltGuid)
            {
                newLinkedTechnicianId = ltGuid;
                technicianChanged = true;
            }
        }
        if (request.TryGetProperty("LinkedAgentId", out var pLa) && pLa.ValueKind == JsonValueKind.String && Guid.TryParse(pLa.GetString(), out var laGuid))
        {
            if (log.LinkedAgentId != laGuid)
            {
                newLinkedAgentId = laGuid;
                agentChanged = true;
            }
        }

        // تعديل القيد المحاسبي عند تغيير الفني أو الوكيل
        if ((technicianChanged || agentChanged) && log.JournalEntryId.HasValue && log.CompanyId.HasValue)
        {
            try
            {
                await UpdateJournalEntryForReassignment(log, newLinkedTechnicianId, newLinkedAgentId, technicianChanged, agentChanged);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "فشل تعديل القيد المحاسبي عند تغيير الفني/الوكيل للسجل {LogId}", id);
                return StatusCode(500, new { success = false, message = "فشل تعديل القيد المحاسبي", error = ex.Message });
            }
        }

        // تطبيق التغيير على السجل
        if (technicianChanged)
        {
            log.LinkedTechnicianId = newLinkedTechnicianId;
            // تحديث اسم الفني
            var newTech = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.Id == newLinkedTechnicianId!.Value);
            if (newTech != null) log.TechnicianName = newTech.FullName;
        }
        if (agentChanged)
        {
            log.LinkedAgentId = newLinkedAgentId;
            // تحديث اسم الوكيل
            var newAgent = await _unitOfWork.Agents.FirstOrDefaultAsync(a => a.Id == newLinkedAgentId!.Value);
            if (newAgent != null) log.TechnicianName = newAgent.Name;
        }

        log.LastUpdateDate = DateTime.UtcNow;
        log.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.SubscriptionLogs.Update(log);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تحديث السجل بنجاح", journalUpdated = technicianChanged || agentChanged });
    }

    /// <summary>
    /// تعديل القيد المحاسبي عند إعادة تعيين الفني أو الوكيل
    /// يُحدّث سطر المدين في القيد من الحساب الفرعي القديم إلى الجديد + تحديث الأرصدة
    /// </summary>
    private async Task UpdateJournalEntryForReassignment(
        Sadara.Domain.Entities.SubscriptionLog log,
        Guid? newTechnicianId, Guid? newAgentId,
        bool technicianChanged, bool agentChanged)
    {
        var companyId = log.CompanyId!.Value;
        var amount = log.PlanPrice ?? 0;
        if (amount <= 0) return;

        // جلب القيد المحاسبي مع أسطره
        var entry = await _unitOfWork.JournalEntries.AsQueryable()
            .Include(j => j.Lines)
            .FirstOrDefaultAsync(j => j.Id == log.JournalEntryId!.Value);

        if (entry == null || entry.Status != JournalEntryStatus.Posted) return;

        // تحديد الحساب القديم (سطر المدين — الأصول)
        var debitLine = entry.Lines.FirstOrDefault(l => l.DebitAmount > 0);
        if (debitLine == null) return;

        var oldAccountId = debitLine.AccountId;
        var oldAccount = await _unitOfWork.Accounts.GetByIdAsync(oldAccountId);

        // ═══ تحديد الحساب الجديد ═══
        Account newAccount;
        string newDescription;
        var opType = log.OperationType?.ToLower() == "purchase" ? "شراء" : "تجديد";
        var planName = log.PlanName ?? "اشتراك";
        var customerName = log.CustomerName ?? "عميل";

        if (technicianChanged && newTechnicianId.HasValue)
        {
            var newTech = await _unitOfWork.Users.GetByIdAsync(newTechnicianId.Value);
            if (newTech == null) throw new Exception("الفني الجديد غير موجود");

            newAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(
                _unitOfWork, AccountCodes.TechnicianReceivables, newTech.Id, newTech.FullName, companyId);
            await _unitOfWork.SaveChangesAsync();
            newDescription = $"{opType} {planName} - {customerName} - على فني {newTech.FullName} (معدّل)";

            // تحديث رصيد الفني القديم (إزالة الشحنة)
            if (log.LinkedTechnicianId.HasValue)
            {
                var oldTech = await _unitOfWork.Users.GetByIdAsync(log.LinkedTechnicianId.Value);
                if (oldTech != null)
                {
                    oldTech.TechTotalCharges -= amount;
                    oldTech.TechNetBalance = oldTech.TechTotalPayments - oldTech.TechTotalCharges;
                    _unitOfWork.Users.Update(oldTech);

                    // حذف TechnicianTransaction القديمة
                    var oldTechTx = await _unitOfWork.TechnicianTransactions.AsQueryable()
                        .FirstOrDefaultAsync(t => t.ReferenceNumber == log.Id.ToString()
                            && t.TechnicianId == oldTech.Id && !t.IsDeleted);
                    if (oldTechTx != null)
                    {
                        oldTechTx.IsDeleted = true;
                        _unitOfWork.TechnicianTransactions.Update(oldTechTx);
                    }
                }
            }

            // تحديث رصيد الفني الجديد (إضافة الشحنة)
            newTech.TechTotalCharges += amount;
            newTech.TechNetBalance = newTech.TechTotalPayments - newTech.TechTotalCharges;
            _unitOfWork.Users.Update(newTech);

            // إنشاء TechnicianTransaction جديدة
            var newTechTx = new TechnicianTransaction
            {
                TechnicianId = newTech.Id,
                Type = TechnicianTransactionType.Charge,
                Category = TechnicianTransactionCategory.Subscription,
                Amount = amount,
                BalanceAfter = newTech.TechNetBalance,
                Description = $"{opType} {planName} - {customerName} (محوّل)",
                ReferenceNumber = log.Id.ToString(),
                CreatedById = log.UserId ?? Guid.Empty,
                CompanyId = companyId,
                JournalEntryId = entry.Id,
                CreatedAt = DateTime.UtcNow
            };
            await _unitOfWork.TechnicianTransactions.AddAsync(newTechTx);
        }
        else if (agentChanged && newAgentId.HasValue)
        {
            var newAgent = await _unitOfWork.Agents.GetByIdAsync(newAgentId.Value);
            if (newAgent == null) throw new Exception("الوكيل الجديد غير موجود");

            newAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(
                _unitOfWork, AccountCodes.AgentReceivables, newAgent.Id, newAgent.Name, companyId);
            await _unitOfWork.SaveChangesAsync();
            newDescription = $"{opType} {planName} - {customerName} - على وكيل {newAgent.Name} (معدّل)";

            // تحديث رصيد الوكيل القديم (إزالة الشحنة)
            if (log.LinkedAgentId.HasValue)
            {
                var oldAgent = await _unitOfWork.Agents.GetByIdAsync(log.LinkedAgentId.Value);
                if (oldAgent != null)
                {
                    oldAgent.TotalCharges -= amount;
                    oldAgent.NetBalance = oldAgent.TotalPayments - oldAgent.TotalCharges;
                    _unitOfWork.Agents.Update(oldAgent);

                    // حذف AgentTransaction القديمة
                    var oldAgentTx = await _unitOfWork.AgentTransactions.AsQueryable()
                        .FirstOrDefaultAsync(t => t.ReferenceNumber == log.Id.ToString()
                            && t.AgentId == oldAgent.Id && !t.IsDeleted);
                    if (oldAgentTx != null)
                    {
                        oldAgentTx.IsDeleted = true;
                        _unitOfWork.AgentTransactions.Update(oldAgentTx);
                    }
                }
            }

            // تحديث رصيد الوكيل الجديد (إضافة الشحنة)
            newAgent.TotalCharges += amount;
            newAgent.NetBalance = newAgent.TotalPayments - newAgent.TotalCharges;
            _unitOfWork.Agents.Update(newAgent);

            // إنشاء AgentTransaction جديدة
            var agentTxCat = log.OperationType?.ToLower() == "purchase"
                ? TransactionCategory.NewSubscription
                : TransactionCategory.RenewalSubscription;
            var newAgentTx = new AgentTransaction
            {
                AgentId = newAgent.Id,
                Type = TransactionType.Charge,
                Category = agentTxCat,
                Amount = amount,
                BalanceAfter = newAgent.NetBalance,
                Description = $"{opType} {planName} - {customerName} (محوّل)",
                ReferenceNumber = log.Id.ToString(),
                CreatedById = log.UserId ?? Guid.Empty,
                JournalEntryId = entry.Id,
                Notes = "تحويل من فني/وكيل آخر"
            };
            await _unitOfWork.AgentTransactions.AddAsync(newAgentTx);
        }
        else
        {
            return; // لا تغيير فعلي
        }

        // ═══ تحديث أرصدة الحسابات ═══
        // عكس الرصيد من الحساب القديم
        if (oldAccount != null)
        {
            if (oldAccount.AccountType == AccountType.Assets || oldAccount.AccountType == AccountType.Expenses)
                oldAccount.CurrentBalance -= amount; // عكس المدين
            else
                oldAccount.CurrentBalance += amount;
            _unitOfWork.Accounts.Update(oldAccount);
        }

        // إضافة الرصيد للحساب الجديد
        if (newAccount.AccountType == AccountType.Assets || newAccount.AccountType == AccountType.Expenses)
            newAccount.CurrentBalance += amount; // مدين جديد
        else
            newAccount.CurrentBalance -= amount;
        _unitOfWork.Accounts.Update(newAccount);

        // ═══ تعديل سطر القيد ═══
        debitLine.AccountId = newAccount.Id;
        debitLine.Description = $"{newAccount.Name} - {opType} {planName}";

        // تعديل وصف القيد
        entry.Description = newDescription;

        _unitOfWork.JournalEntries.Update(entry);
        await _unitOfWork.SaveChangesAsync();
    }

    /// <summary>
    /// البحث عن سجل بواسطة SessionId
    /// </summary>
    [HttpGet("subscriptionlogs/by-session/{sessionId}")]
    [AllowAnonymous]
    public async Task<IActionResult> GetSubscriptionLogBySession(string sessionId)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var log = await _unitOfWork.SubscriptionLogs.AsQueryable()
            .Where(l => l.SessionId == sessionId)
            .OrderByDescending(l => l.CreatedAt)
            .Select(l => new { l.Id, l.SessionId, l.IsPrinted, l.IsWhatsAppSent })
            .FirstOrDefaultAsync();

        if (log == null)
            return NotFound(new { success = false, message = "السجل غير موجود" });

        return Ok(log);
    }

    /// <summary>
    /// حذف سجل اشتراك
    /// </summary>
    [HttpDelete("subscriptionlogs/{id}")]
    [AllowAnonymous]
    public async Task<IActionResult> DeleteSubscriptionLog(long id)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var log = await _unitOfWork.SubscriptionLogs.GetByIdAsync(id);
        if (log == null)
            return NotFound(new { success = false, message = "السجل غير موجود" });

        _unitOfWork.SubscriptionLogs.Delete(log);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم حذف السجل بنجاح" });
    }

    /// <summary>
    /// إضافة سجل اشتراك جديد (يُستخدم من Flutter بعد كل عملية تجديد/شراء)
    /// </summary>
    [HttpPost("subscriptionlogs")]
    [AllowAnonymous]
    [Consumes("application/json")]
    public async Task<IActionResult> CreateSubscriptionLog([FromBody] JsonElement request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var log = new Sadara.Domain.Entities.SubscriptionLog
            {
                CustomerId = request.TryGetProperty("customerId", out var p1) ? p1.GetString() : null,
                CustomerName = request.TryGetProperty("customerName", out var p2) ? p2.GetString() : null,
                PhoneNumber = request.TryGetProperty("phoneNumber", out var p3) ? p3.GetString() : null,
                SubscriptionId = request.TryGetProperty("subscriptionId", out var p4) ? p4.GetString() : null,
                PlanName = request.TryGetProperty("planName", out var p5) ? p5.GetString() : null,
                PlanPrice = request.TryGetProperty("planPrice", out var p6) && p6.ValueKind == JsonValueKind.Number ? p6.GetDecimal() : null,
                CommitmentPeriod = request.TryGetProperty("commitmentPeriod", out var p7) && p7.ValueKind == JsonValueKind.Number ? p7.GetInt32() : null,
                BundleId = request.TryGetProperty("bundleId", out var p8) ? p8.GetString() : null,
                CurrentStatus = request.TryGetProperty("currentStatus", out var p9) ? p9.GetString() : null,
                DeviceUsername = request.TryGetProperty("deviceUsername", out var p10) ? p10.GetString() : null,
                OperationType = request.TryGetProperty("operationType", out var p11) ? p11.GetString() : null,
                ActivatedBy = request.TryGetProperty("activatedBy", out var p12) ? p12.GetString() : null,
                ActivationDate = request.TryGetProperty("activationDate", out var p13) && p13.ValueKind == JsonValueKind.String
                    ? (DateTime.TryParse(p13.GetString(), System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.AdjustToUniversal, out var dt) ? dt : DateTime.UtcNow)
                    : DateTime.UtcNow,
                ActivationTime = request.TryGetProperty("activationTime", out var p14) ? p14.GetString() : null,
                SessionId = request.TryGetProperty("sessionId", out var p15) ? p15.GetString() : null,
                LastUpdateDate = DateTime.UtcNow,
                ZoneId = request.TryGetProperty("zoneId", out var p16) ? p16.GetString() : null,
                ZoneName = request.TryGetProperty("zoneName", out var p17) ? p17.GetString() : null,
                FbgInfo = request.TryGetProperty("fbgInfo", out var p18) ? p18.GetString() : null,
                FatInfo = request.TryGetProperty("fatInfo", out var p19) ? p19.GetString() : null,
                FdtInfo = request.TryGetProperty("fdtInfo", out var p20) ? p20.GetString() : null,
                WalletBalanceBefore = request.TryGetProperty("walletBalanceBefore", out var p21) && p21.ValueKind == JsonValueKind.Number ? p21.GetDecimal() : null,
                WalletBalanceAfter = request.TryGetProperty("walletBalanceAfter", out var p22) && p22.ValueKind == JsonValueKind.Number ? p22.GetDecimal() : null,
                PartnerWalletBalanceBefore = request.TryGetProperty("partnerWalletBalanceBefore", out var p23) && p23.ValueKind == JsonValueKind.Number ? p23.GetDecimal() : null,
                CustomerWalletBalanceBefore = request.TryGetProperty("customerWalletBalanceBefore", out var p24) && p24.ValueKind == JsonValueKind.Number ? p24.GetDecimal() : null,
                Currency = request.TryGetProperty("currency", out var p25) ? p25.GetString() : null,
                PaymentMethod = request.TryGetProperty("paymentMethod", out var p26) ? p26.GetString() : null,
                PartnerName = request.TryGetProperty("partnerName", out var p27) ? p27.GetString() : null,
                PartnerId = request.TryGetProperty("partnerId", out var p28) ? p28.GetString() : null,
                IsPrinted = request.TryGetProperty("isPrinted", out var p29) && p29.ValueKind == JsonValueKind.True,
                IsWhatsAppSent = request.TryGetProperty("isWhatsAppSent", out var p30) && p30.ValueKind == JsonValueKind.True,
                SubscriptionNotes = request.TryGetProperty("subscriptionNotes", out var p31) ? p31.GetString() : null,
                StartDate = request.TryGetProperty("startDate", out var p32) ? p32.GetString() : null,
                EndDate = request.TryGetProperty("endDate", out var p33) ? p33.GetString() : null,
                ApiResponse = request.TryGetProperty("apiResponse", out var p34) ? p34.GetString() : null,
            };

            // معالجة userId و companyId كـ Guid
            if (request.TryGetProperty("userId", out var uid) && uid.ValueKind == JsonValueKind.String && Guid.TryParse(uid.GetString(), out var userGuid))
                log.UserId = userGuid;
            if (request.TryGetProperty("companyId", out var cid) && cid.ValueKind == JsonValueKind.String && Guid.TryParse(cid.GetString(), out var companyGuid))
                log.CompanyId = companyGuid;

            // حقول تكامل المحاسبة الجديدة
            log.CollectionType = request.TryGetProperty("collectionType", out var pCt) ? pCt.GetString() : null;
            log.FtthTransactionId = request.TryGetProperty("ftthTransactionId", out var pFt) ? pFt.GetString() : null;
            if (request.TryGetProperty("serviceRequestId", out var pSr) && pSr.ValueKind == JsonValueKind.String && Guid.TryParse(pSr.GetString(), out var srGuid))
                log.ServiceRequestId = srGuid;
            if (request.TryGetProperty("linkedAgentId", out var pLa) && pLa.ValueKind == JsonValueKind.String && Guid.TryParse(pLa.GetString(), out var laGuid))
                log.LinkedAgentId = laGuid;
            if (request.TryGetProperty("linkedTechnicianId", out var pLt) && pLt.ValueKind == JsonValueKind.String && Guid.TryParse(pLt.GetString(), out var ltGuid))
                log.LinkedTechnicianId = ltGuid;

            // أجور الصيانة وحقول التسعير
            if (request.TryGetProperty("maintenanceFee", out var pMf) && pMf.ValueKind == JsonValueKind.Number)
                log.MaintenanceFee = pMf.GetDecimal();
            if (request.TryGetProperty("basePrice", out var pBp) && pBp.ValueKind == JsonValueKind.Number)
                log.BasePrice = pBp.GetDecimal();
            if (request.TryGetProperty("systemDiscount", out var pSd) && pSd.ValueKind == JsonValueKind.Number)
                log.CompanyDiscount = pSd.GetDecimal();
            if (request.TryGetProperty("manualDiscount", out var pMd) && pMd.ValueKind == JsonValueKind.Number)
                log.ManualDiscount = pMd.GetDecimal();
            if (request.TryGetProperty("systemDiscountEnabled", out var pSde))
                log.SystemDiscountEnabled = pSde.ValueKind == JsonValueKind.True;

            // حفظ اسم الفني من الطلب — تجاهل القيم الخاطئة مثل "فني" أو "وكيل"
            if (request.TryGetProperty("technicianName", out var pTn) && pTn.ValueKind == JsonValueKind.String)
            {
                var tn = pTn.GetString()?.Trim();
                // القيم الخاطئة التي كانت ترسلها النسخ القديمة من التطبيق
                var invalidNames = new[] { "فني", "وكيل", "technician", "agent", "نقد", "cash", "آجل", "credit", "ماستر", "master" };
                if (!string.IsNullOrEmpty(tn) && !invalidNames.Contains(tn))
                    log.TechnicianName = tn;
            }

            // جلب اسم الفني من قاعدة البيانات عبر LinkedTechnicianId
            if (string.IsNullOrEmpty(log.TechnicianName) && log.LinkedTechnicianId.HasValue)
            {
                var tech = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.Id == log.LinkedTechnicianId.Value);
                if (tech != null) log.TechnicianName = tech.FullName;
            }
            // جلب اسم الوكيل عبر LinkedAgentId
            if (string.IsNullOrEmpty(log.TechnicianName) && log.CollectionType == "agent" && log.LinkedAgentId.HasValue)
            {
                var agent = await _unitOfWork.Agents.FirstOrDefaultAsync(a => a.Id == log.LinkedAgentId.Value);
                if (agent != null) log.TechnicianName = agent.Name;
            }

            // حماية من التكرار — إذا وصل نفس الطلب مرتين (ضغط مزدوج أو خطأ شبكة)
            if (!string.IsNullOrEmpty(log.SessionId))
            {
                var duplicate = await _unitOfWork.SubscriptionLogs.AsQueryable()
                    .AnyAsync(l => l.SessionId == log.SessionId && !l.IsDeleted);
                if (duplicate)
                {
                    _logger.LogWarning("طلب مكرر — SessionId {SessionId} موجود مسبقاً", log.SessionId);
                    var existing = await _unitOfWork.SubscriptionLogs.AsQueryable()
                        .FirstOrDefaultAsync(l => l.SessionId == log.SessionId && !l.IsDeleted);
                    return Ok(new { success = true, id = existing?.Id, message = "السجل موجود مسبقاً", duplicate = true });
                }
            }

            await _unitOfWork.SubscriptionLogs.AddAsync(log);
            await _unitOfWork.SaveChangesAsync();

            // إنشاء قيد محاسبي تلقائي إذا توفرت البيانات
            Guid? journalEntryId = null;
            if (log.CompanyId.HasValue && log.UserId.HasValue && log.PlanPrice.HasValue && log.PlanPrice > 0 && !string.IsNullOrEmpty(log.CollectionType))
            {
                try
                {
                    journalEntryId = await CreateAccountingEntryForLog(log);
                    if (journalEntryId.HasValue)
                    {
                        log.JournalEntryId = journalEntryId;
                        _unitOfWork.SubscriptionLogs.Update(log);
                        await _unitOfWork.SaveChangesAsync();
                    }
                }
                catch (Exception acEx)
                {
                    _logger.LogWarning(acEx, "فشل إنشاء القيد المحاسبي لسجل FTTH {LogId} — السجل حُفظ بدونه", log.Id);
                }
            }

            return Ok(new { success = true, data = new { log.Id, JournalEntryId = journalEntryId }, message = "تم حفظ السجل بنجاح" });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { success = false, message = "خطأ في حفظ السجل", error = ex.Message });
        }
    }

    [HttpGet("citizens")]
    [AllowAnonymous]
    public async Task<IActionResult> GetCitizens()
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var citizens = await _context.Citizens
            .Where(c => !c.IsDeleted)
            .OrderByDescending(c => c.CreatedAt)
            .Select(c => new
            {
                c.Id,
                c.FullName,
                c.PhoneNumber,
                c.Email,
                c.City,
                c.District,
                c.IsActive,
                c.IsPhoneVerified,
                c.IsBanned,
                c.CompanyId,
                c.CreatedAt
            })
            .ToListAsync();

        return Ok(new { success = true, data = citizens, count = citizens.Count });
    }

    /// <summary>
    /// إضافة مواطن جديد
    /// </summary>
    [HttpPost("citizens")]
    [AllowAnonymous]
    [Consumes("application/json")]
    public async Task<IActionResult> CreateCitizen([FromBody] CreateCitizenDto dto)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            // تنظيف رقم الهاتف
            var cleanPhone = dto.PhoneNumber?.Replace(" ", "").Replace("-", "") ?? "";
            if (cleanPhone.StartsWith("966"))
                cleanPhone = "+" + cleanPhone;
            else if (cleanPhone.StartsWith("0"))
                cleanPhone = "+966" + cleanPhone.Substring(1);
            else if (!cleanPhone.StartsWith("+"))
                cleanPhone = "+966" + cleanPhone;

            // التحقق من عدم وجود الرقم
            var existingCitizen = await _context.Citizens.FirstOrDefaultAsync(c => c.PhoneNumber == cleanPhone);
            if (existingCitizen != null)
            {
                return BadRequest(new { success = false, message = "رقم الهاتف مسجل مسبقاً" });
            }

            // البحث عن أول شركة لربط المواطن بها
            var company = await _unitOfWork.Companies.AsQueryable()
                .FirstOrDefaultAsync(c => !c.IsDeleted);

            if (company == null)
            {
                return BadRequest(new { success = false, message = "يجب إنشاء شركة أولاً" });
            }

            var citizen = new Sadara.Domain.Entities.Citizen
            {
                Id = Guid.NewGuid(),
                FullName = dto.FullName ?? dto.Name ?? "مواطن جديد",
                PhoneNumber = cleanPhone,
                PasswordHash = HashPassword(dto.Password ?? "123456"),
                Email = dto.Email ?? "",
                City = dto.City ?? "",
                District = dto.District ?? "",
                CompanyId = dto.CompanyId ?? company.Id,
                IsActive = true,
                IsPhoneVerified = true, // نفعّله مباشرة من لوحة التحكم
                LanguagePreference = "ar",
                CreatedAt = DateTime.UtcNow
            };

            _context.Citizens.Add(citizen);
            await _context.SaveChangesAsync();

            return Ok(new { success = true, message = "تم إضافة المواطن بنجاح", id = citizen.Id });
        }
        catch (Exception ex)
        {
            return BadRequest(new { success = false, message = ex.Message });
        }
    }

    /// <summary>
    /// تعديل مواطن
    /// </summary>
    [HttpPut("citizens/{id}")]
    [AllowAnonymous]
    public async Task<IActionResult> UpdateCitizen(Guid id, [FromBody] CreateCitizenDto dto)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var citizen = await _context.Citizens.FindAsync(id);
            if (citizen == null)
                return NotFound(new { success = false, message = "المواطن غير موجود" });

            if (!string.IsNullOrEmpty(dto.FullName)) citizen.FullName = dto.FullName;
            if (!string.IsNullOrEmpty(dto.Name)) citizen.FullName = dto.Name;
            if (!string.IsNullOrEmpty(dto.Email)) citizen.Email = dto.Email;
            if (!string.IsNullOrEmpty(dto.City)) citizen.City = dto.City;
            if (!string.IsNullOrEmpty(dto.District)) citizen.District = dto.District;
            if (!string.IsNullOrEmpty(dto.Password)) citizen.PasswordHash = HashPassword(dto.Password);

            await _context.SaveChangesAsync();

            return Ok(new { success = true, message = "تم تحديث المواطن بنجاح" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { success = false, message = ex.Message });
        }
    }

    /// <summary>
    /// حذف مواطن
    /// </summary>
    [HttpDelete("citizens/{id}")]
    [AllowAnonymous]
    public async Task<IActionResult> DeleteCitizen(Guid id)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var citizen = await _context.Citizens.FindAsync(id);
            if (citizen == null)
                return NotFound(new { success = false, message = "المواطن غير موجود" });

            citizen.IsDeleted = true;
            await _context.SaveChangesAsync();

            return Ok(new { success = true, message = "تم حذف المواطن بنجاح" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { success = false, message = ex.Message });
        }
    }

    /// <summary>
    /// تشفير كلمة المرور
    /// </summary>
    private static string HashPassword(string password)
    {
        using var sha256 = SHA256.Create();
        var hashedBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(password));
        return Convert.ToBase64String(hashedBytes);
    }

    /// <summary>
    /// تقرير ربحية التفعيلات — يحسب التكلفة والربح لكل عملية
    /// </summary>
    [HttpGet("subscriptionlogs/profitability")]
    [AllowAnonymous]
    public async Task<IActionResult> GetProfitabilityReport(
        [FromQuery] string? companyId,
        [FromQuery] DateTime? fromDate,
        [FromQuery] DateTime? toDate,
        [FromQuery] string? operatorName,
        [FromQuery] string? collectionType)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var query = _unitOfWork.SubscriptionLogs.AsQueryable()
            .Where(l => !l.IsDeleted && l.PlanPrice.HasValue && l.PlanPrice > 0);

        if (!string.IsNullOrEmpty(companyId) && Guid.TryParse(companyId, out var cId))
            query = query.Where(l => l.CompanyId == cId);
        if (fromDate.HasValue)
            query = query.Where(l => l.ActivationDate >= DateTime.SpecifyKind(fromDate.Value.AddHours(-3), DateTimeKind.Utc));
        if (toDate.HasValue)
            query = query.Where(l => l.ActivationDate <= DateTime.SpecifyKind(toDate.Value.AddDays(1).AddHours(-3), DateTimeKind.Utc));
        if (!string.IsNullOrEmpty(operatorName))
            query = query.Where(l => l.ActivatedBy == operatorName);
        if (!string.IsNullOrEmpty(collectionType))
            query = query.Where(l => l.CollectionType == collectionType);

        var logs = await query
            .OrderByDescending(l => l.ActivationDate)
            .Select(l => new
            {
                l.Id,
                l.CustomerName,
                l.PlanName,
                l.PlanPrice,
                l.OperationType,
                l.ActivatedBy,
                l.ActivationDate,
                l.CollectionType,
                l.TechnicianName,
                l.ZoneName,
                l.MaintenanceFee,
                l.WalletBalanceBefore,
                l.WalletBalanceAfter,
                WalletCost = (l.WalletBalanceBefore ?? 0) - (l.WalletBalanceAfter ?? 0),
            })
            .ToListAsync();

        // حساب الربحية لكل سجل
        var details = logs.Select(l =>
        {
            var walletCost = l.WalletCost > 0 ? l.WalletCost : 0;
            var maintenance = l.MaintenanceFee ?? 0;
            var subscriptionPrice = (l.PlanPrice ?? 0) - maintenance;
            var discountProfit = subscriptionPrice - walletCost;
            var totalProfit = discountProfit + maintenance;

            return new
            {
                l.Id,
                l.CustomerName,
                l.PlanName,
                l.ActivationDate,
                l.OperationType,
                l.ActivatedBy,
                l.CollectionType,
                l.TechnicianName,
                l.ZoneName,
                PaidBySubscriber = l.PlanPrice ?? 0,        // ما دفعه المشترك
                WalletCost = walletCost,                     // تكلفة المحفظة
                SubscriptionPrice = subscriptionPrice,       // سعر الاشتراك (بدون صيانة)
                MaintenanceFee = maintenance,                // أجور الصيانة
                DiscountProfit = discountProfit,              // ربح الخصم المخفي
                TotalProfit = totalProfit,                    // إجمالي الربح
            };
        }).ToList();

        // ملخص
        var summary = new
        {
            TotalTransactions = details.Count,
            TotalPaidBySubscribers = details.Sum(d => d.PaidBySubscriber),
            TotalWalletCost = details.Sum(d => d.WalletCost),
            TotalSubscriptionRevenue = details.Sum(d => d.SubscriptionPrice),
            TotalMaintenanceRevenue = details.Sum(d => d.MaintenanceFee),
            TotalDiscountProfit = details.Sum(d => d.DiscountProfit),
            TotalProfit = details.Sum(d => d.TotalProfit),
        };

        return Ok(new { success = true, summary, data = details });
    }

    /// <summary>
    /// إنشاء القيد المحاسبي — النظام الجديد:
    ///   مدين: حساب التحصيل (المبلغ المحصّل من العميل)
    ///   دائن: رصيد الصفحة 11102 (صافي الشركة)
    ///   دائن: إيراد صيانة 4110 (إن وُجدت)
    ///   دائن: إيراد خصم الشركة 4120 (إن لم يُمرَّر)
    /// </summary>
    private async Task<Guid?> CreateAccountingEntryForLog(Sadara.Domain.Entities.SubscriptionLog log)
    {
        var companyId = log.CompanyId!.Value;
        var userId = log.UserId!.Value;
        var collectionType = log.CollectionType ?? "cash";

        // ═══ حساب المبالغ ═══
        // المعادلات الثابتة:
        //   رصيد الصفحة (دائن)     = السعر الأساسي - خصم الشركة  ← ثابت دائماً
        //   إيراد خصم الشركة (دائن) = خصم الشركة                 ← فقط عند عدم التفعيل
        //   مصاريف عروض (مدين)      = الخصم الاختياري             ← إن وُجد
        //   إيراد صيانة (دائن)      = رسوم الصيانة               ← إن وُجدت
        //   حساب التحصيل (مدين)     = PlanPrice (ما يدفعه العميل) ← دائماً

        var collectedAmount = log.PlanPrice ?? 0;       // ما يدفعه العميل
        var maintenanceFee = log.MaintenanceFee ?? 0;   // رسوم صيانة
        var manualDiscount = log.ManualDiscount ?? 0;   // خصم اختياري
        var companyDiscount = log.CompanyDiscount ?? 0;  // خصم الشركة
        var basePrice = log.BasePrice ?? 0;              // السعر الأساسي

        // صافي الشركة = السعر الأساسي - خصم الشركة (ثابت دائماً)
        decimal netFromCompany;
        if (basePrice > 0)
        {
            // الحقول الجديدة متوفرة — حساب دقيق
            netFromCompany = basePrice - companyDiscount;
        }
        else
        {
            // fallback (تطبيق قديم): نحسب من المعادلة العكسية
            // إذا الخصم مفعّل: PlanPrice = BasePrice - CompanyDiscount - ManualDiscount + MaintenanceFee
            //   إذاً: netFromCompany = PlanPrice + ManualDiscount - MaintenanceFee
            // إذا الخصم غير مفعّل: PlanPrice = BasePrice - ManualDiscount + MaintenanceFee
            //   إذاً: netFromCompany = PlanPrice + ManualDiscount - MaintenanceFee - CompanyDiscount
            if (log.SystemDiscountEnabled)
                netFromCompany = collectedAmount + manualDiscount - maintenanceFee;
            else
                netFromCompany = collectedAmount + manualDiscount - maintenanceFee - companyDiscount;

            if (netFromCompany <= 0) netFromCompany = collectedAmount;
        }

        // ربح خصم الشركة = خصم الشركة عند عدم تفعيله (إيراد)
        var companyDiscountProfit = log.SystemDiscountEnabled ? 0 : companyDiscount;

        // ═══ جلب حسابات القيد ═══
        var pageBalanceAccount = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.PageBalance, companyId);
        if (pageBalanceAccount == null)
        {
            _logger.LogWarning("حساب رصيد الصفحة 11102 غير موجود للشركة {CompanyId}", companyId);
            return null;
        }

        Sadara.Domain.Entities.Account? maintenanceRevenueAccount = maintenanceFee > 0
            ? await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.MaintenanceRevenue, companyId) : null;
        Sadara.Domain.Entities.Account? discountRevenueAccount = companyDiscountProfit > 0
            ? await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.CompanyDiscountRevenue, companyId) : null;
        Sadara.Domain.Entities.Account? promotionExpenseAccount = manualDiscount > 0
            ? await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.PromotionExpense, companyId) : null;

        var user = await _unitOfWork.Users.GetByIdAsync(userId);
        var operatorName = user?.FullName ?? "مشغل";
        var planName = log.PlanName ?? "اشتراك";
        var customerName = log.CustomerName ?? "عميل";
        var opType = log.OperationType?.ToLower() == "purchase" ? "شراء" : "تجديد";

        Sadara.Domain.Entities.Account debitAccount;
        string description;

        switch (collectionType.ToLower())
        {
            case "cash":
                debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, AccountCodes.Cash, userId, $"صندوق {operatorName}", companyId);
                await _unitOfWork.SaveChangesAsync();
                description = $"{opType} {planName} - {customerName} - نقد عبر {operatorName}";
                break;

            case "credit":
                debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, AccountCodes.OperatorReceivables, userId, $"ذمة {operatorName}", companyId);
                await _unitOfWork.SaveChangesAsync();
                description = $"{opType} {planName} - {customerName} - آجل على {operatorName}";
                break;

            case "master":
                debitAccount = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.ElectronicPayment, companyId)
                    ?? throw new Exception("حساب 1170 غير موجود");
                description = $"{opType} {planName} - {customerName} - ماستر (إلكتروني)";
                break;

            case "agent":
                if (!log.LinkedAgentId.HasValue) throw new Exception("لا يوجد وكيل");
                var agent = await _unitOfWork.Agents.GetByIdAsync(log.LinkedAgentId.Value);
                if (agent == null) throw new Exception("الوكيل غير موجود");
                debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, AccountCodes.AgentReceivables, agent.Id, agent.Name, companyId);
                await _unitOfWork.SaveChangesAsync();
                description = $"{opType} {planName} - {customerName} - على وكيل {agent.Name} عبر {operatorName}";

                // ═══ توحيد: تحديث رصيد الوكيل + إنشاء AgentTransaction ═══
                agent.TotalCharges += collectedAmount;
                agent.NetBalance = agent.TotalPayments - agent.TotalCharges;
                _unitOfWork.Agents.Update(agent);

                var agentTxCat = log.OperationType?.ToLower() == "purchase"
                    ? TransactionCategory.NewSubscription
                    : TransactionCategory.RenewalSubscription;

                var agentTx2 = new AgentTransaction
                {
                    AgentId = agent.Id,
                    Type = TransactionType.Charge,
                    Category = agentTxCat,
                    Amount = collectedAmount,
                    BalanceAfter = agent.NetBalance,
                    Description = $"{opType} {planName} - {customerName}",
                    ReferenceNumber = log.Id.ToString(),
                    CreatedById = userId,
                    Notes = $"تفعيل عبر {operatorName}"
                };
                await _unitOfWork.AgentTransactions.AddAsync(agentTx2);
                break;

            case "technician":
                if (!log.LinkedTechnicianId.HasValue) throw new Exception("لا يوجد فني");
                var tech = await _unitOfWork.Users.GetByIdAsync(log.LinkedTechnicianId.Value);
                if (tech == null) throw new Exception("الفني غير موجود");
                debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, AccountCodes.TechnicianReceivables, tech.Id, tech.FullName, companyId);
                await _unitOfWork.SaveChangesAsync();
                description = $"{opType} {planName} - {customerName} - على فني {tech.FullName} عبر {operatorName}";

                // ═══ توحيد: تحديث رصيد الفني + إنشاء TechnicianTransaction ═══
                tech.TechTotalCharges += collectedAmount;
                tech.TechNetBalance = tech.TechTotalPayments - tech.TechTotalCharges;
                _unitOfWork.Users.Update(tech);

                var techTx2 = new TechnicianTransaction
                {
                    TechnicianId = tech.Id,
                    Type = TechnicianTransactionType.Charge,
                    Category = TechnicianTransactionCategory.Subscription,
                    Amount = collectedAmount,
                    BalanceAfter = tech.TechNetBalance,
                    Description = $"{opType} {planName} - {customerName}",
                    ReferenceNumber = log.Id.ToString(),
                    CreatedById = userId,
                    CompanyId = companyId,
                    CreatedAt = DateTime.UtcNow
                };
                await _unitOfWork.TechnicianTransactions.AddAsync(techTx2);
                break;

            default:
                debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, AccountCodes.Cash, userId, $"صندوق {operatorName}", companyId);
                await _unitOfWork.SaveChangesAsync();
                description = $"{opType} {planName} - {customerName} - عبر {operatorName}";
                break;
        }

        // ═══ بناء سطور القيد الجديد ═══
        var lines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>();

        // مدين: حساب التحصيل (المبلغ المحصّل من العميل)
        if (collectedAmount > 0)
            lines.Add((debitAccount.Id, collectedAmount, 0, $"{debitAccount.Name} - {opType} {planName}"));

        // مدين: مصاريف عروض (الخصم الاختياري)
        if (manualDiscount > 0 && promotionExpenseAccount != null)
            lines.Add((promotionExpenseAccount.Id, manualDiscount, 0, $"خصم اختياري - {customerName}"));

        // دائن: رصيد الصفحة (صافي الشركة)
        if (netFromCompany > 0)
            lines.Add((pageBalanceAccount.Id, 0, netFromCompany, $"خصم من رصيد الصفحة - {opType} {planName}"));

        // دائن: إيراد صيانة
        if (maintenanceFee > 0 && maintenanceRevenueAccount != null)
            lines.Add((maintenanceRevenueAccount.Id, 0, maintenanceFee, $"إيراد صيانة - {customerName}"));

        // دائن: إيراد خصم الشركة (ربح عدم تمرير الخصم)
        if (companyDiscountProfit > 0 && discountRevenueAccount != null)
            lines.Add((discountRevenueAccount.Id, 0, companyDiscountProfit, $"إيراد خصم الشركة - {customerName}"));

        if (lines.Count < 2)
        {
            _logger.LogWarning("لا توجد سطور كافية للقيد المحاسبي — تم التخطي");
            return null;
        }

        await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
            _unitOfWork, companyId, userId, description,
            JournalReferenceType.FtthSubscription, log.Id.ToString(), lines);

        await _unitOfWork.SaveChangesAsync();

        var entry = await _unitOfWork.JournalEntries.AsQueryable()
            .Where(j => j.ReferenceType == JournalReferenceType.FtthSubscription
                && j.ReferenceId == log.Id.ToString()
                && j.CompanyId == companyId)
            .OrderByDescending(j => j.CreatedAt)
            .FirstOrDefaultAsync();

        // ربط JournalEntryId بالمعاملات المُنشأة
        if (entry != null)
        {
            var linkedTechTx = await _unitOfWork.TechnicianTransactions.AsQueryable()
                .FirstOrDefaultAsync(t => t.ReferenceNumber == log.Id.ToString() && t.JournalEntryId == null && !t.IsDeleted);
            if (linkedTechTx != null)
            {
                linkedTechTx.JournalEntryId = entry.Id;
                _unitOfWork.TechnicianTransactions.Update(linkedTechTx);
            }

            var linkedAgentTx = await _unitOfWork.AgentTransactions.AsQueryable()
                .FirstOrDefaultAsync(t => t.ReferenceNumber == log.Id.ToString() && t.JournalEntryId == null && !t.IsDeleted);
            if (linkedAgentTx != null)
            {
                linkedAgentTx.JournalEntryId = entry.Id;
                _unitOfWork.AgentTransactions.Update(linkedAgentTx);
            }

            await _unitOfWork.SaveChangesAsync();
        }

        return entry?.Id;
    }

    /// <summary>
    /// إصلاح أسماء الفنيين/الوكلاء القديمة المحفوظة بشكل خاطئ (مثل "فني" بدلاً من الاسم الحقيقي)
    /// يُستدعى مرة واحدة لتصحيح البيانات التاريخية
    /// </summary>
    [HttpPost("fix-technician-names")]
    [AllowAnonymous]
    public async Task<IActionResult> FixTechnicianNames()
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var invalidNames = new[] { "فني", "وكيل", "technician", "agent", "نقد", "cash", "آجل", "credit", "ماستر", "master" };

        // إصلاح سجلات الفنيين
        var techLogs = await _unitOfWork.SubscriptionLogs.AsQueryable()
            .Where(l => l.CollectionType == "technician"
                     && l.LinkedTechnicianId.HasValue
                     && (l.TechnicianName == null || l.TechnicianName == "" || invalidNames.Contains(l.TechnicianName)))
            .ToListAsync();

        int techFixed = 0;
        foreach (var log in techLogs)
        {
            var tech = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.Id == log.LinkedTechnicianId!.Value);
            if (tech != null)
            {
                log.TechnicianName = tech.FullName;
                _unitOfWork.SubscriptionLogs.Update(log);
                techFixed++;
            }
        }

        // إصلاح سجلات الوكلاء
        var agentLogs = await _unitOfWork.SubscriptionLogs.AsQueryable()
            .Where(l => l.CollectionType == "agent"
                     && l.LinkedAgentId.HasValue
                     && (l.TechnicianName == null || l.TechnicianName == "" || invalidNames.Contains(l.TechnicianName)))
            .ToListAsync();

        int agentFixed = 0;
        foreach (var log in agentLogs)
        {
            var agent = await _unitOfWork.Agents.FirstOrDefaultAsync(a => a.Id == log.LinkedAgentId!.Value);
            if (agent != null)
            {
                log.TechnicianName = agent.Name;
                _unitOfWork.SubscriptionLogs.Update(log);
                agentFixed++;
            }
        }

        await _unitOfWork.SaveChangesAsync();

        return Ok(new
        {
            success = true,
            message = $"تم إصلاح {techFixed} سجل فني و {agentFixed} سجل وكيل",
            techFixed,
            agentFixed
        });
    }

    // ═══════════════════════════════════════════════════════
    // تقارير التسديدات اليومية - Daily Settlement Reports
    // ═══════════════════════════════════════════════════════

    /// <summary>
    /// جلب تقارير التسديدات اليومية
    /// </summary>
    [HttpGet("settlement-reports")]
    [AllowAnonymous]
    public async Task<IActionResult> GetSettlementReports(
        [FromQuery] string? operatorName,
        [FromQuery] string? companyId,
        [FromQuery] DateTime? fromDate,
        [FromQuery] DateTime? toDate,
        [FromQuery] int pageSize = 500)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var query = _unitOfWork.DailySettlementReports.AsQueryable()
            .Where(r => !r.IsDeleted);

        if (!string.IsNullOrEmpty(operatorName))
            query = query.Where(r => r.OperatorName == operatorName);

        if (!string.IsNullOrEmpty(companyId) && Guid.TryParse(companyId, out var cId))
            query = query.Where(r => r.CompanyId == cId);

        if (fromDate.HasValue)
        {
            var from = DateTime.SpecifyKind(fromDate.Value.Date.AddHours(-3), DateTimeKind.Utc);
            query = query.Where(r => r.ReportDate >= from);
        }

        if (toDate.HasValue)
        {
            var to = DateTime.SpecifyKind(toDate.Value.Date.AddDays(1).AddHours(-3), DateTimeKind.Utc);
            query = query.Where(r => r.ReportDate < to);
        }

        var effectivePageSize = Math.Min(pageSize < 1 ? 500 : pageSize, 2000);

        var reports = await query
            .OrderByDescending(r => r.ReportDate)
            .ThenBy(r => r.OperatorName)
            .Take(effectivePageSize)
            .Select(r => new
            {
                r.Id,
                r.ReportDate,
                r.OperatorName,
                r.OperatorId,
                r.CompanyId,
                r.Notes,
                r.ItemsJson,
                r.TotalAmount,
                r.CreatedAt,
                r.UpdatedAt,
                r.DeliveredToId,
                r.DeliveredToName,
                r.JournalEntryId,
                r.SystemTotal,
                r.SystemCashTotal,
                r.SystemCreditTotal,
                r.SystemMasterTotal,
                r.SystemTechTotal,
                r.SystemAgentTotal,
                r.TotalExpenses,
                r.NetCashAmount,
                r.ReceivedAmount,
            })
            .ToListAsync();

        return Ok(reports);
    }

    /// <summary>
    /// إنشاء أو تحديث تقرير تسديد يومي (upsert: تقرير واحد لكل مشغل لكل يوم)
    /// </summary>
    [HttpPost("settlement-reports")]
    [AllowAnonymous]
    public async Task<IActionResult> CreateSettlementReport([FromBody] JsonElement request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var operatorName = request.GetProperty("operatorName").GetString() ?? "";
            var reportDateStr = request.TryGetProperty("reportDate", out var rdProp) ? rdProp.GetString() : null;
            var reportDate = !string.IsNullOrEmpty(reportDateStr)
                ? DateTime.SpecifyKind(DateTime.Parse(reportDateStr).Date.AddHours(-3), DateTimeKind.Utc)
                : DateTime.SpecifyKind(DateTime.UtcNow.AddHours(3).Date.AddHours(-3), DateTimeKind.Utc);

            var operatorId = request.TryGetProperty("operatorId", out var oiProp) ? oiProp.GetString() : null;
            var notes = request.TryGetProperty("notes", out var nProp) ? nProp.GetString() : null;
            Guid? companyId = request.TryGetProperty("companyId", out var ciProp) && Guid.TryParse(ciProp.GetString(), out var parsedCid)
                ? parsedCid : null;

            // بيانات المستلم
            var deliveredToId = request.TryGetProperty("deliveredToId", out var dtiProp) ? dtiProp.GetString() : null;
            var deliveredToName = request.TryGetProperty("deliveredToName", out var dtnProp) ? dtnProp.GetString() : null;

            // Parse items
            var itemsJson = "[]";
            decimal totalAmount = 0;
            if (request.TryGetProperty("items", out var itemsProp))
            {
                itemsJson = itemsProp.GetRawText();
                foreach (var item in itemsProp.EnumerateArray())
                {
                    if (item.TryGetProperty("amount", out var amtProp))
                        totalAmount += amtProp.GetDecimal();
                }
            }

            // Upsert: check if report exists for this operator + date
            var existing = await _unitOfWork.DailySettlementReports.AsQueryable()
                .FirstOrDefaultAsync(r => !r.IsDeleted && r.OperatorName == operatorName && r.ReportDate == reportDate);

            bool isUpdate = existing != null;
            DailySettlementReport report;

            if (existing != null)
            {
                report = existing;
                report.Notes = notes;
                report.ItemsJson = itemsJson;
                report.TotalAmount = totalAmount;
                report.OperatorId = operatorId;
                report.CompanyId = companyId;
                report.DeliveredToId = deliveredToId;
                report.DeliveredToName = deliveredToName;
                report.UpdatedAt = DateTime.UtcNow;

                // تحديث تفاصيل النظام
                report.SystemTotal = _safeDecimal(request, "systemTotal");
                report.SystemCashTotal = _safeDecimal(request, "systemCashTotal");
                report.SystemCreditTotal = _safeDecimal(request, "systemCreditTotal");
                report.SystemMasterTotal = _safeDecimal(request, "systemMasterTotal");
                report.SystemTechTotal = _safeDecimal(request, "systemTechTotal");
                report.SystemAgentTotal = _safeDecimal(request, "systemAgentTotal");
                report.TotalExpenses = _safeDecimal(request, "totalExpenses");
                report.NetCashAmount = _safeDecimal(request, "netCashAmount");

                // إلغاء القيد المحاسبي السابق (Void) إذا موجود
                if (report.JournalEntryId.HasValue)
                {
                    var oldEntry = await _unitOfWork.JournalEntries.GetByIdAsync(report.JournalEntryId.Value);
                    if (oldEntry != null && oldEntry.Status == JournalEntryStatus.Posted)
                    {
                        // عكس تأثير القيد على الأرصدة
                        var oldLines = await _unitOfWork.JournalEntryLines.AsQueryable()
                            .Where(l => l.JournalEntryId == oldEntry.Id)
                            .ToListAsync();
                        foreach (var line in oldLines)
                        {
                            var account = await _unitOfWork.Accounts.GetByIdAsync(line.AccountId);
                            if (account != null)
                            {
                                if (account.AccountType == AccountType.Assets || account.AccountType == AccountType.Expenses)
                                {
                                    account.CurrentBalance -= line.DebitAmount;
                                    account.CurrentBalance += line.CreditAmount;
                                }
                                else
                                {
                                    account.CurrentBalance += line.DebitAmount;
                                    account.CurrentBalance -= line.CreditAmount;
                                }
                                _unitOfWork.Accounts.Update(account);
                            }
                        }
                        oldEntry.Status = JournalEntryStatus.Voided;
                        _unitOfWork.JournalEntries.Update(oldEntry);
                    }
                    report.JournalEntryId = null;
                }

                _unitOfWork.DailySettlementReports.Update(report);
            }
            else
            {
                report = new DailySettlementReport
                {
                    ReportDate = reportDate,
                    OperatorName = operatorName,
                    OperatorId = operatorId,
                    CompanyId = companyId,
                    Notes = notes,
                    ItemsJson = itemsJson,
                    TotalAmount = totalAmount,
                    DeliveredToId = deliveredToId,
                    DeliveredToName = deliveredToName,
                    // تفاصيل النظام (داخل المُهيئ لضمان الحفظ)
                    SystemTotal = _safeDecimal(request, "systemTotal"),
                    SystemCashTotal = _safeDecimal(request, "systemCashTotal"),
                    SystemCreditTotal = _safeDecimal(request, "systemCreditTotal"),
                    SystemMasterTotal = _safeDecimal(request, "systemMasterTotal"),
                    SystemTechTotal = _safeDecimal(request, "systemTechTotal"),
                    SystemAgentTotal = _safeDecimal(request, "systemAgentTotal"),
                    TotalExpenses = _safeDecimal(request, "totalExpenses"),
                    NetCashAmount = _safeDecimal(request, "netCashAmount"),
                };
                await _unitOfWork.DailySettlementReports.AddAsync(report);
            }

            await _unitOfWork.SaveChangesAsync();
            _logger.LogInformation("✅ Settlement report saved: SystemTotal={ST}, CashTotal={CT}, NetCash={NC}",
                report.SystemTotal, report.SystemCashTotal, report.NetCashAmount);

            // الترحيل المحاسبي يتم يدوياً من صفحة المحاسب (accountant-post endpoint)
            Guid? journalEntryId = report.JournalEntryId;

            var msg = isUpdate ? "تم تحديث التقرير" : "تم إنشاء التقرير";
            if (journalEntryId.HasValue) msg += " مع قيد محاسبي";
            return Ok(new { success = true, message = msg, id = report.Id, updated = isUpdate, journalEntryId });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating settlement report");
            return BadRequest(new { success = false, message = ex.Message });
        }
    }

    /// <summary>
    /// ترحيل محاسبي يدوي من المحاسب — ينقل المبلغ المستلم من صندوق المشغل إلى صندوق الشركة
    /// </summary>
    [HttpPost("settlement-reports/{id}/accountant-post")]
    [AllowAnonymous]
    public async Task<IActionResult> AccountantPostSettlementReport(long id, [FromBody] JsonElement request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var report = await _unitOfWork.DailySettlementReports.GetByIdAsync(id);
            if (report == null)
                return NotFound(new { success = false, message = "التقرير غير موجود" });

            decimal receivedAmount = _safeDecimal(request, "receivedAmount");
            if (receivedAmount <= 0)
                return BadRequest(new { success = false, message = "المبلغ المستلم يجب أن يكون أكبر من صفر" });

            // حفظ المبلغ المستلم
            report.ReceivedAmount = receivedAmount;

            // ═══ استكمال البيانات الناقصة تلقائياً ═══
            Guid opGuid;

            // 1) محاولة إيجاد المشغل في جدول المستخدمين بالاسم
            if (!report.CompanyId.HasValue || string.IsNullOrEmpty(report.OperatorId) || !Guid.TryParse(report.OperatorId, out opGuid))
            {
                var operatorUser = await _unitOfWork.Users.AsQueryable()
                    .Where(u => !u.IsDeleted && u.FullName == report.OperatorName)
                    .Select(u => new { u.Id, u.CompanyId })
                    .FirstOrDefaultAsync();

                if (operatorUser != null)
                {
                    if (!report.CompanyId.HasValue && operatorUser.CompanyId.HasValue)
                        report.CompanyId = operatorUser.CompanyId;
                    if (string.IsNullOrEmpty(report.OperatorId))
                        report.OperatorId = operatorUser.Id.ToString();
                }
            }

            // 2) إذا CompanyId لا تزال فارغة → أول شركة موجودة
            if (!report.CompanyId.HasValue)
            {
                var firstCompanyId = await _unitOfWork.Companies.AsQueryable()
                    .Where(c => !c.IsDeleted)
                    .Select(c => c.Id)
                    .FirstOrDefaultAsync();
                if (firstCompanyId != default)
                    report.CompanyId = firstCompanyId;
            }

            if (!report.CompanyId.HasValue)
                return BadRequest(new { success = false, message = "لم يتم العثور على شركة — يرجى التواصل مع المسؤول" });

            // 3) إذا OperatorId لا يزال فارغاً → GUID ثابت من اسم المشغل
            if (string.IsNullOrEmpty(report.OperatorId) || !Guid.TryParse(report.OperatorId, out opGuid))
            {
                using var md5 = System.Security.Cryptography.MD5.Create();
                var hash = md5.ComputeHash(System.Text.Encoding.UTF8.GetBytes($"operator:{report.OperatorName}"));
                opGuid = new Guid(hash);
                report.OperatorId = opGuid.ToString();
            }

            var companyId = report.CompanyId.Value;

            // ═══ إلغاء القيد القديم إذا موجود ═══
            if (report.JournalEntryId.HasValue)
            {
                var oldEntry = await _unitOfWork.JournalEntries.GetByIdAsync(report.JournalEntryId.Value);
                if (oldEntry != null && oldEntry.Status == JournalEntryStatus.Posted)
                {
                    var oldLines = await _unitOfWork.JournalEntryLines.AsQueryable()
                        .Where(l => l.JournalEntryId == oldEntry.Id).ToListAsync();
                    foreach (var line in oldLines)
                    {
                        var account = await _unitOfWork.Accounts.GetByIdAsync(line.AccountId);
                        if (account != null)
                        {
                            if (account.AccountType == AccountType.Assets || account.AccountType == AccountType.Expenses)
                            {
                                account.CurrentBalance -= line.DebitAmount;
                                account.CurrentBalance += line.CreditAmount;
                            }
                            else
                            {
                                account.CurrentBalance += line.DebitAmount;
                                account.CurrentBalance -= line.CreditAmount;
                            }
                            _unitOfWork.Accounts.Update(account);
                        }
                    }
                    oldEntry.Status = JournalEntryStatus.Voided;
                    _unitOfWork.JournalEntries.Update(oldEntry);
                }
                report.JournalEntryId = null;
            }

            // ═══ إنشاء القيد المحاسبي الجديد ═══
            // حساب صندوق المشغل (Credit — المبلغ يخرج)
            var operatorAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(
                _unitOfWork, AccountCodes.Cash, opGuid, $"صندوق {report.OperatorName}", companyId);
            await _unitOfWork.SaveChangesAsync();

            // حساب صندوق الشركة (Debit — المبلغ يدخل)
            var companyAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(
                _unitOfWork, AccountCodes.Cash, companyId, "صندوق الشركة", companyId);
            await _unitOfWork.SaveChangesAsync();

            var description = $"استلام نقدي {receivedAmount:N0} من صندوق {report.OperatorName} — {report.ReportDate:yyyy-MM-dd}";
            var lines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>
            {
                (companyAccount.Id, receivedAmount, 0, $"استلام نقدي من صندوق {report.OperatorName}"),
                (operatorAccount.Id, 0, receivedAmount, $"تسليم نقدي إلى صندوق الشركة")
            };

            // جلب أول مستخدم فعلي في الشركة لاستخدامه كـ CreatedBy/ApprovedBy
            var systemUserId = await _unitOfWork.Users.AsQueryable()
                .Where(u => !u.IsDeleted && u.CompanyId == companyId)
                .Select(u => u.Id)
                .FirstOrDefaultAsync();
            var createdByGuid = systemUserId != default ? systemUserId : companyId;

            var journalEntryId = await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
                _unitOfWork, companyId, createdByGuid, description,
                JournalReferenceType.OperatorCashDelivery, report.Id.ToString(), lines);

            report.JournalEntryId = journalEntryId;
            _unitOfWork.DailySettlementReports.Update(report);
            await _unitOfWork.SaveChangesAsync();

            _logger.LogInformation("✅ Accountant posted settlement #{Id}: {Amount} from {Op} to company",
                report.Id, receivedAmount, report.OperatorName);

            return Ok(new { success = true, message = "تم الترحيل بنجاح", journalEntryId });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in accountant-post for settlement {Id}", id);
            return BadRequest(new { success = false, message = ex.Message });
        }
    }

    /// <summary>
    /// تحديث تقرير تسديد موجود
    /// </summary>
    [HttpPut("settlement-reports/{id}")]
    [AllowAnonymous]
    public async Task<IActionResult> UpdateSettlementReport(long id, [FromBody] JsonElement request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var report = await _unitOfWork.DailySettlementReports.GetByIdAsync(id);
        if (report == null)
            return NotFound(new { success = false, message = "التقرير غير موجود" });

        if (request.TryGetProperty("notes", out var nProp))
            report.Notes = nProp.GetString();

        if (request.TryGetProperty("items", out var itemsProp))
        {
            report.ItemsJson = itemsProp.GetRawText();
            decimal totalAmount = 0;
            foreach (var item in itemsProp.EnumerateArray())
            {
                if (item.TryGetProperty("amount", out var amtProp))
                    totalAmount += amtProp.GetDecimal();
            }
            report.TotalAmount = totalAmount;
        }

        report.UpdatedAt = DateTime.UtcNow;
        _unitOfWork.DailySettlementReports.Update(report);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تحديث التقرير" });
    }

    /// <summary>
    /// حذف تقرير تسديد (soft delete)
    /// </summary>
    [HttpDelete("settlement-reports/{id}")]
    [AllowAnonymous]
    public async Task<IActionResult> DeleteSettlementReport(long id)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var report = await _unitOfWork.DailySettlementReports.GetByIdAsync(id);
        if (report == null)
            return NotFound(new { success = false, message = "التقرير غير موجود" });

        report.IsDeleted = true;
        report.DeletedAt = DateTime.UtcNow;
        _unitOfWork.DailySettlementReports.Update(report);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم حذف التقرير" });
    }

    /// <summary>
    /// فحص هل المشغل أرسل تقرير اليوم
    /// </summary>
    [HttpGet("settlement-reports/check")]
    [AllowAnonymous]
    public async Task<IActionResult> CheckSettlementReport(
        [FromQuery] string operatorName,
        [FromQuery] string? date)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var checkDate = !string.IsNullOrEmpty(date)
            ? DateTime.SpecifyKind(DateTime.Parse(date).Date.AddHours(-3), DateTimeKind.Utc)
            : DateTime.SpecifyKind(DateTime.UtcNow.AddHours(3).Date.AddHours(-3), DateTimeKind.Utc);

        var report = await _unitOfWork.DailySettlementReports.AsQueryable()
            .FirstOrDefaultAsync(r => !r.IsDeleted && r.OperatorName == operatorName && r.ReportDate == checkDate);

        return Ok(new
        {
            submitted = report != null,
            reportId = report?.Id,
            totalAmount = report?.TotalAmount ?? 0,
        });
    }
}

// DTOs for Create/Update operations
public class CreateCustomerDto
{
    public string? Name { get; set; }
    public string? FullName { get; set; }
    public string? PhoneNumber { get; set; }
    public string? Email { get; set; }
    public string? City { get; set; }
    public string? Area { get; set; }
    public Guid? MerchantId { get; set; }
}

public class CreateCityDto
{
    public string? Name { get; set; }
    public string? NameAr { get; set; }
}

public class CreateMerchantDto
{
    public string? Name { get; set; }
    public string? BusinessName { get; set; }
    public string? PhoneNumber { get; set; }
    public string? Email { get; set; }
    public string? City { get; set; }
}

public class CreateProductDto
{
    public string? Name { get; set; }
    public string? NameAr { get; set; }
    public decimal? Price { get; set; }
    public decimal? CostPrice { get; set; }
    public int? Stock { get; set; }
    public string? SKU { get; set; }
    public Guid? MerchantId { get; set; }
}

public class CreateCitizenDto
{
    public string? Name { get; set; }
    public string? FullName { get; set; }
    public string? PhoneNumber { get; set; }
    public string? Password { get; set; }
    public string? Email { get; set; }
    public string? City { get; set; }
    public string? District { get; set; }
    public Guid? CompanyId { get; set; }
}

/// <summary>
/// طلب تحديث بيانات الشركة
/// </summary>
public class InternalUpdateCompanyRequest
{
    public string? Name { get; set; }
    public string? Phone { get; set; }
    public string? Email { get; set; }
    public string? Address { get; set; }
    public string? City { get; set; }
    public int? MaxUsers { get; set; }
    public DateTime? SubscriptionEndDate { get; set; }
    public bool? IsActive { get; set; }
    public Dictionary<string, bool>? EnabledFirstSystemFeatures { get; set; }
    public Dictionary<string, bool>? EnabledSecondSystemFeatures { get; set; }
}

/// <summary>
/// طلب تعليق الشركة
/// </summary>
public class SuspendCompanyRequest
{
    public string? Reason { get; set; }
}

/// <summary>
/// طلب تحديث صلاحيات الشركة (Internal API)
/// </summary>
public class InternalUpdatePermissionsRequest
{
    public Dictionary<string, bool>? EnabledFirstSystemFeatures { get; set; }
    public Dictionary<string, bool>? EnabledSecondSystemFeatures { get; set; }
}

/// <summary>
/// طلب تجديد الاشتراك (Internal API)
/// </summary>
public class InternalRenewSubscriptionRequest
{
    public int? Months { get; set; }
    public DateTime? NewEndDate { get; set; }
}

/// <summary>
/// طلب إنشاء موظف جديد (Internal API)
/// </summary>
public class InternalCreateEmployeeRequest
{
    public string FullName { get; set; } = string.Empty;
    public string PhoneNumber { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string? Password { get; set; }
    public string? Role { get; set; }
    public string? Department { get; set; }
    public string? EmployeeCode { get; set; }
    public string? Center { get; set; }
    public decimal? Salary { get; set; }
}

/// <summary>
/// طلب تحديث بيانات موظف (Internal API)
/// </summary>
public class InternalUpdateEmployeeRequest
{
    public string? FullName { get; set; }
    public string? PhoneNumber { get; set; }
    public string? Email { get; set; }
    public string? Role { get; set; }
    public string? Department { get; set; }
    public string? EmployeeCode { get; set; }
    public string? Center { get; set; }
    public decimal? Salary { get; set; }
    public bool? IsActive { get; set; }
    // HR fields
    public string? NationalId { get; set; }
    public string? DateOfBirth { get; set; }
    public string? HireDate { get; set; }
    public string? ContractType { get; set; }
    public string? BankAccountNumber { get; set; }
    public string? BankName { get; set; }
    public string? EmergencyContactName { get; set; }
    public string? EmergencyContactPhone { get; set; }
    public string? HrNotes { get; set; }
    // Schedule fields
    public int? WorkScheduleId { get; set; }
    public string? CustomWorkStartTime { get; set; }
    public string? CustomWorkEndTime { get; set; }
    // Password fields
    public string? NewPassword { get; set; }
    public string? FtthPassword { get; set; }
    // Attendance security code
    public string? AttendanceSecurityCode { get; set; }
}

/// <summary>
/// طلب تغيير كلمة المرور (Internal API)
/// </summary>
public class InternalUpdatePasswordRequest
{
    public string NewPassword { get; set; } = string.Empty;
}

/// <summary>
/// طلب تحديث صلاحيات الموظف (Internal API)
/// </summary>
public class InternalUpdateEmployeePermissionsRequest
{
    public Dictionary<string, bool>? FirstSystemPermissions { get; set; }
    public Dictionary<string, bool>? SecondSystemPermissions { get; set; }
}

// ==========================================
// V2 - نظام الصلاحيات المفصل (إجراءات)
// ==========================================

/// <summary>
/// طلب تحديث صلاحيات V2 للشركة (مع إجراءات مفصلة)
/// </summary>
public class InternalUpdatePermissionsV2Request
{
    /// <summary>
    /// صلاحيات النظام الأول V2
    /// مثال: {"attendance":{"view":true,"add":false,"edit":false,"delete":false}}
    /// </summary>
    public Dictionary<string, Dictionary<string, bool>>? EnabledFirstSystemFeaturesV2 { get; set; }
    
    /// <summary>
    /// صلاحيات النظام الثاني V2
    /// مثال: {"users":{"view":true,"add":true,"edit":false,"delete":false,"export":false}}
    /// </summary>
    public Dictionary<string, Dictionary<string, bool>>? EnabledSecondSystemFeaturesV2 { get; set; }
}

/// <summary>
/// طلب تحديث صلاحيات V2 للموظف (مع إجراءات مفصلة)
/// </summary>
public class InternalUpdateEmployeePermissionsV2Request
{
    /// <summary>
    /// صلاحيات النظام الأول V2
    /// </summary>
    public Dictionary<string, Dictionary<string, bool>>? FirstSystemPermissionsV2 { get; set; }
    
    /// <summary>
    /// صلاحيات النظام الثاني V2
    /// </summary>
    public Dictionary<string, Dictionary<string, bool>>? SecondSystemPermissionsV2 { get; set; }
}

/// <summary>طلب حفظ قوالب الصلاحيات المخصصة</summary>
public class SaveTemplatesRequest
{
    /// <summary>JSON string يحتوي القوالب المخصصة</summary>
    public string? Templates { get; set; }
}