using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Application.Interfaces;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class UsersController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly IPasswordHasher _passwordHasher;
    private readonly ICurrentTenant _tenant;

    public UsersController(IUnitOfWork unitOfWork, IPasswordHasher passwordHasher, ICurrentTenant tenant)
    {
        _unitOfWork = unitOfWork;
        _passwordHasher = passwordHasher;
        _tenant = tenant;
    }

    // ── عزل المستأجر: هل المستخدم المستهدف خارج نطاق شركة المتصل؟ ──
    // SuperAdmin: يصل لأي مستخدم في أي شركة (false دائماً).
    // أي مستخدم آخر: يُقيَّد بشركة توكنه؛ إن اختلفت شركة الهدف أو كانت شركة التوكن فارغة
    // يُعتبر الهدف خارج النطاق (true) ⇒ يُعامل كغير موجود (404) كي لا يُكشف وجوده لشركة أخرى.
    private bool IsOutOfTenantScope(User targetUser)
    {
        if (_tenant.IsSuperAdmin)
            return false;

        var tenantCompany = _tenant.CompanyId;
        if (tenantCompany is null || tenantCompany.Value == Guid.Empty)
            return true;

        return targetUser.CompanyId != tenantCompany.Value;
    }

    [HttpGet]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetAll([FromQuery] int page = 1, [FromQuery] int pageSize = 20)
    {
        var query = _unitOfWork.Users.AsQueryable();

        // عزل المستأجر: غير SuperAdmin يرى مستخدمي شركته فقط.
        // شركة فارغة لغير SuperAdmin ⇒ قائمة فارغة بأمان (لا تسريب عبر الشركات).
        if (!_tenant.IsSuperAdmin)
        {
            var tenantCompany = _tenant.CompanyId;
            if (tenantCompany is null || tenantCompany.Value == Guid.Empty)
                return Ok(new { success = true, data = Array.Empty<UserDto>(), total = 0, page, pageSize });

            query = query.Where(u => u.CompanyId == tenantCompany.Value);
        }

        var total = await query.CountAsync();
        var users = await query
            .OrderByDescending(u => u.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(u => new UserDto
            {
                Id = u.Id,
                FullName = u.FullName,
                PhoneNumber = u.PhoneNumber,
                Email = u.Email,
                Role = u.Role.ToString(),
                IsActive = u.IsActive,
                IsPhoneVerified = u.IsPhoneVerified,
                CreatedAt = u.CreatedAt
            })
            .ToListAsync();

        return Ok(new { success = true, data = users, total, page, pageSize });
    }

    [HttpGet("{id:guid}")]
    [Authorize]
    public async Task<IActionResult> GetById(Guid id)
    {
        var user = await _unitOfWork.Users.GetByIdAsync(id);
        if (user == null)
            return NotFound(new { success = false, message = "المستخدم غير موجود" });

        // عزل المستأجر: لا تكشف مستخدمي شركة أخرى (404 بدل 403 كي لا نؤكّد وجوده)
        if (IsOutOfTenantScope(user))
            return NotFound(new { success = false, message = "المستخدم غير موجود" });

        return Ok(new
        {
            success = true,
            data = new UserDto
            {
                Id = user.Id,
                FullName = user.FullName,
                PhoneNumber = user.PhoneNumber,
                Email = user.Email,
                Role = user.Role.ToString(),
                IsActive = user.IsActive,
                IsPhoneVerified = user.IsPhoneVerified,
                ProfileImageUrl = user.ProfileImageUrl,
                CreatedAt = user.CreatedAt
            }
        });
    }

    [HttpGet("phone/{phoneNumber}")]
    public async Task<IActionResult> GetByPhone(string phoneNumber)
    {
        var user = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.PhoneNumber == phoneNumber);
        if (user == null)
            return NotFound(new { success = false, message = "المستخدم غير موجود" });

        return Ok(new { success = true, data = new { exists = true, isActive = user.IsActive } });
    }

    [HttpPut("{id:guid}")]
    [Authorize]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateUserRequest request)
    {
        var user = await _unitOfWork.Users.GetByIdAsync(id);
        if (user == null)
            return NotFound(new { success = false, message = "المستخدم غير موجود" });

        // عزل المستأجر: امنع تعديل مستخدمي شركة أخرى (404 بدل 403 كي لا نؤكّد وجوده)
        if (IsOutOfTenantScope(user))
            return NotFound(new { success = false, message = "المستخدم غير موجود" });

        user.FullName = request.FullName ?? user.FullName;
        user.Email = request.Email ?? user.Email;
        user.ProfileImageUrl = request.ProfileImageUrl ?? user.ProfileImageUrl;
        user.City = request.City ?? user.City;
        user.Area = request.Area ?? user.Area;
        user.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Users.Update(user);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تحديث البيانات بنجاح" });
    }

    [HttpPatch("{id:guid}/password")]
    [Authorize]
    public async Task<IActionResult> ChangePassword(Guid id, [FromBody] ChangePasswordRequest request)
    {
        var user = await _unitOfWork.Users.GetByIdAsync(id);
        if (user == null)
            return NotFound(new { success = false, message = "المستخدم غير موجود" });

        if (!_passwordHasher.VerifyPassword(request.CurrentPassword, user.PasswordHash))
            return BadRequest(new { success = false, message = "كلمة المرور الحالية غير صحيحة" });

        user.PasswordHash = _passwordHasher.HashPassword(request.NewPassword);
        user.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Users.Update(user);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تغيير كلمة المرور بنجاح" });
    }

    [HttpPatch("{id:guid}/status")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> UpdateStatus(Guid id, [FromBody] UpdateStatusRequest request)
    {
        var user = await _unitOfWork.Users.GetByIdAsync(id);
        if (user == null)
            return NotFound(new { success = false, message = "المستخدم غير موجود" });

        // عزل المستأجر: امنع تعطيل/تفعيل مستخدمي شركة أخرى (404 بدل 403)
        if (IsOutOfTenantScope(user))
            return NotFound(new { success = false, message = "المستخدم غير موجود" });

        user.IsActive = request.IsActive;
        user.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Users.Update(user);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = request.IsActive ? "تم تفعيل الحساب" : "تم تعطيل الحساب" });
    }

    [HttpDelete("{id:guid}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var user = await _unitOfWork.Users.GetByIdAsync(id);
        if (user == null)
            return NotFound(new { success = false, message = "المستخدم غير موجود" });

        // عزل المستأجر: امنع حذف مستخدمي شركة أخرى (404 بدل 403)
        if (IsOutOfTenantScope(user))
            return NotFound(new { success = false, message = "المستخدم غير موجود" });

        user.IsDeleted = true;
        user.IsActive = false;
        user.DeletedAt = DateTime.UtcNow;

        _unitOfWork.Users.Update(user);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم حذف المستخدم بنجاح" });
    }
}

public class UserDto
{
    public Guid Id { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string PhoneNumber { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string Role { get; set; } = string.Empty;
    public bool IsActive { get; set; }
    public bool IsPhoneVerified { get; set; }
    public string? ProfileImageUrl { get; set; }
    public DateTime CreatedAt { get; set; }
}

public record UpdateUserRequest(
    string? FullName,
    string? Email,
    string? ProfileImageUrl,
    string? City,
    string? Area
);

public record ChangePasswordRequest(
    string CurrentPassword,
    string NewPassword
);

public record UpdateStatusRequest(bool IsActive);
