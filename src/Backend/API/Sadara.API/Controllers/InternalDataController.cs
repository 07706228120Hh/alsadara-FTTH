using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;
using Sadara.Infrastructure.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

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

    public InternalDataController(IUnitOfWork unitOfWork, IConfiguration configuration, SadaraDbContext context)
    {
        _unitOfWork = unitOfWork;
        _configuration = configuration;
        _context = context;
    }

    /// <summary>
    /// التحقق من API Key - يقرأ من الإعدادات أو Environment Variable
    /// </summary>
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
                u.CreatedAt
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
                employee.CreatedAt
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
    public async Task<IActionResult> GetSubscriptionLogs()
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var logs = await _unitOfWork.SubscriptionLogs.AsQueryable()
            .OrderByDescending(l => l.CreatedAt)
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
                l.OperationType,
                l.ActivatedBy,
                l.ActivationDate,
                l.ZoneId,
                l.ZoneName,
                l.WalletBalanceBefore,
                l.WalletBalanceAfter,
                l.PartnerName,
                l.CompanyId,
                l.IsPrinted,
                l.IsWhatsAppSent,
                l.StartDate,
                l.EndDate,
                l.CreatedAt
            })
            .Take(500)
            .ToListAsync();

        return Ok(logs);
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

        log.LastUpdateDate = DateTime.UtcNow;
        log.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.SubscriptionLogs.Update(log);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تحديث السجل بنجاح" });
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
                    ? (DateTime.TryParse(p13.GetString(), out var dt) ? DateTime.SpecifyKind(dt, DateTimeKind.Utc) : DateTime.UtcNow)
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

            await _unitOfWork.SubscriptionLogs.AddAsync(log);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, data = new { log.Id }, message = "تم حفظ السجل بنجاح" });
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