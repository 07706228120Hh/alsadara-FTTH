using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Sadara.API.Hubs;
using Sadara.Application.Interfaces;
using Sadara.Domain.Entities;
using Sadara.Infrastructure.Data;

namespace Sadara.API.Controllers;

/// <summary>
/// إدارة الجلسات — إجراءات أمنية على مستوى الشركة.
/// حالياً: إخراج إجباري لكل موظفي الشركة الحالية (ما عدا الضاغط).
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class SessionController : ControllerBase
{
    private readonly SadaraDbContext _db;
    private readonly IHubContext<TaskHub> _hub;
    private readonly ICurrentTenant _tenant;
    private readonly ILogger<SessionController> _logger;

    public SessionController(
        SadaraDbContext db,
        IHubContext<TaskHub> hub,
        ICurrentTenant tenant,
        ILogger<SessionController> logger)
    {
        _db = db;
        _hub = hub;
        _tenant = tenant;
        _logger = logger;
    }

    /// <summary>
    /// إخراج إجباري لكل موظفي الشركة الحالية (ما عدا المستخدم الضاغط):
    ///  (1) مسح RefreshToken لمنع تجديد الجلسة (يُجبر على إعادة الدخول).
    ///  (2) بثّ فوري "ForceLogout" عبر SignalR لمجموعة الشركة — المتصلون الآن يخرجون مباشرة.
    /// العزل: الشركة تؤخذ من التوكن فقط (لا من العميل). متاح لمدير الشركة (CompanyAdmin) أو SuperAdmin فقط.
    /// </summary>
    [HttpPost("force-logout-company")]
    [EnableRateLimiting("force-logout")]
    public async Task<IActionResult> ForceLogoutCompany()
    {
        // الإجراء مربوط بشركة واحدة (مجموعة SignalR + نطاق مسح التوكنات). SuperAdmin يصل بـ
        // company_id فارغ ⇒ يُرفض هنا صراحةً (عليه الدخول بحساب شركة لتنفيذ الإجراء على شركة محددة).
        var companyId = _tenant.CompanyId;
        if (companyId is null)
            return BadRequest(new { success = false, message = "تعذّر تحديد الشركة من التوكن (الإجراء على مستوى شركة واحدة)" });

        // الدور: ندعم اسمَي الـ claim (ClaimTypes.Role و"role") توافقاً مع المعمارية الموزّعة المخطّطة.
        var role = User.FindFirstValue(ClaimTypes.Role) ?? User.FindFirstValue("role");
        if (!string.Equals(role, "CompanyAdmin", StringComparison.OrdinalIgnoreCase))
            return StatusCode(403, new { success = false, message = "هذا الإجراء متاح لمدير الشركة فقط" });

        if (!Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var currentUserId)
            || currentUserId == Guid.Empty)
            return BadRequest(new { success = false, message = "تعذّر تحديد هوية المستخدم من التوكن" });

        var now = DateTime.UtcNow;

        // (1) إبطال جلسات كل موظفي الشركة عدا الضاغط — scoped صراحةً بالشركة من التوكن.
        //     SessionsRevokedAtUtc يقطع توكنات الوصول الحالية فوراً عبر فحص OnTokenValidated،
        //     ومسح RefreshToken يمنع التجديد.
        var affected = await _db.Users
            .IgnoreQueryFilters()
            .Where(u => u.CompanyId == companyId && u.Id != currentUserId && !u.IsDeleted)
            .ExecuteUpdateAsync(s => s
                .SetProperty(u => u.RefreshToken, (string?)null)
                .SetProperty(u => u.RefreshTokenExpiryTime, (DateTime?)null)
                .SetProperty(u => u.SessionsRevokedAtUtc, now)
                .SetProperty(u => u.UpdatedAt, now));

        // (2) بثّ فوري للمتصلين الآن — العميل يتجاهل الحدث إن طابق exceptUserId هويته.
        // ملاحظة: بثّ أفضل-جهد؛ لا يقطع access token لعميل غير متصل أو يتجاهل الحدث (انظر حدّ P1 الموثّق).
        await _hub.Clients.Group(TaskHub.CompanyGroup(companyId.Value.ToString()))
            .SendAsync("ForceLogout", new
            {
                exceptUserId = currentUserId.ToString(),
                reason = "admin_force_logout",
                at = DateTime.UtcNow
            });

        // (3) تدقيق دائم في قاعدة البيانات (إضافةً إلى السجلّ).
        _db.ForceLogoutAudits.Add(new ForceLogoutAudit
        {
            Id = Guid.NewGuid(),
            CompanyId = companyId.Value,
            RequestedByUserId = currentUserId,
            AffectedCount = affected,
            ExecutedAtUtc = now
        });
        await _db.SaveChangesAsync();

        _logger.LogWarning(
            "ForceLogout: الشركة {CompanyId} بواسطة {UserId} — {Affected} جلسة أُبطلت",
            companyId, currentUserId, affected);

        return Ok(new
        {
            success = true,
            data = new { affected },
            message = $"تم إخراج {affected} مستخدماً من التطبيق"
        });
    }
}
