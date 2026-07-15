using System.Security.Claims;
using Sadara.Application.Interfaces;

namespace Sadara.API.Services;

/// <summary>
/// تنفيذ <see cref="ICurrentTenant"/> عبر IHttpContextAccessor.
///
/// يقرأ هوية المستأجر من التوكن الحالي:
///  - الشركة: يدعم اسمَي الـ claim الموجودين في النظام ("company_id" و "companyId") لضمان التوافق.
///  - الدور: من ClaimTypes.Role أو "role"؛ إذا كان "SuperAdmin" => تجاوز كامل للعزل.
///
/// ملاحظة انتقالية: التوكنات القديمة الصادرة قبل إضافة claim الشركة (خصوصاً من تسجيل الدخول الرئيسي)
/// قد لا تحمل الشركة؛ يتم إثراؤها بـ company_id عبر حدث OnTokenValidated في Program.cs (استعلام واحد
/// عن شركة المستخدم من قاعدة البيانات) حتى لا تنكسر جلسات المستخدمين الحاليين أثناء الانتقال.
/// </summary>
public class CurrentTenant : ICurrentTenant
{
    private readonly IHttpContextAccessor _httpContextAccessor;

    public CurrentTenant(IHttpContextAccessor httpContextAccessor)
    {
        _httpContextAccessor = httpContextAccessor;
    }

    private ClaimsPrincipal? User => _httpContextAccessor.HttpContext?.User;

    public bool IsSuperAdmin
    {
        get
        {
            var role = User?.FindFirst(ClaimTypes.Role)?.Value
                    ?? User?.FindFirst("role")?.Value;
            return string.Equals(role, "SuperAdmin", StringComparison.OrdinalIgnoreCase);
        }
    }

    /// <summary>
    /// تجاوز الفلتر عند: (1) عدم وجود HttpContext أصلاً — سياق نظام (خدمات خلفية/هجرات/seed)،
    /// أو (2) كون المستخدم SuperAdmin.
    /// </summary>
    public bool BypassTenantFilter => _httpContextAccessor.HttpContext is null || IsSuperAdmin;

    public Guid? CompanyId
    {
        get
        {
            var raw = User?.FindFirst("company_id")?.Value
                   ?? User?.FindFirst("companyId")?.Value;
            return Guid.TryParse(raw, out var id) ? id : (Guid?)null;
        }
    }
}
