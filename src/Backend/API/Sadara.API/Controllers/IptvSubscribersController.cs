using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.API.Authorization;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

/// <summary>
/// إدارة مشتركي IPTV — JWT موظف الشركة (الشركة من التوكن) أو المفتاح القديم
/// </summary>
[ApiController]
[Route("api/iptv-subscribers")]
public class IptvSubscribersController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly IConfiguration _configuration;

    public IptvSubscribersController(IUnitOfWork unitOfWork, IConfiguration configuration)
    {
        _unitOfWork = unitOfWork;
        _configuration = configuration;
    }

    // ══════════════════════════════════════
    // المصادقة (المرحلة 0 / A2): JWT موظف الشركة، أو المفتاح القديم
    // ══════════════════════════════════════
    //
    // IptvSubscriber.CompanyId نصّي (لا Guid) فلا يشمله أي فلتر مركزي ⇒ العزل هنا: على مسار JWT
    // الشركة = شركة التوكن دائماً (companyId في الطلب يُتجاهل/يُرفض إن خالف)، وأي سجل بالمعرّف يجب أن
    // يكون لشركة الطالب. الصلاحية: iptv (نفس بوابة الواجهة، دلالة RequirePermission).

    private const string IptvPermission = "iptv";

    private async Task<(InternalCaller Caller, IActionResult? Error)> AuthorizeIptvAsync()
    {
        var (caller, error) = await LegacyKeyOrJwtGate.AuthorizeAsync(HttpContext, _configuration, _unitOfWork);
        if (error != null) return (caller, error);
        if (caller.IsJwt && !caller.IsManagerOrHasPermission(IptvPermission))
            return (caller, LegacyKeyOrJwtGate.Forbidden(LegacyKeyOrJwtGate.MsgNoPermission));
        return (caller, null);
    }

    private static string CompanyKey(Guid companyId) => companyId.ToString().ToLowerInvariant();

    /// <summary>هل يحق للطالب الوصول لسجل بهذه الشركة النصية؟</summary>
    private static bool CanAccess(InternalCaller caller, string? recordCompanyId)
    {
        if (!caller.IsTenantBound) return true;
        return Guid.TryParse(recordCompanyId, out var g) && g == caller.CompanyId!.Value;
    }

    /// <summary>جلب جميع مشتركي IPTV لشركة محددة</summary>
    [HttpGet]
    public async Task<IActionResult> GetAll([FromQuery] string? companyId)
    {
        var (caller, authError) = await AuthorizeIptvAsync();
        if (authError != null) return authError;

        if (caller.IsTenantBound)
        {
            if (!string.IsNullOrEmpty(companyId) && !CanAccess(caller, companyId))
                return LegacyKeyOrJwtGate.Forbidden(LegacyKeyOrJwtGate.MsgOtherCompany);
            var key = CompanyKey(caller.CompanyId!.Value);
            var own = await _unitOfWork.IptvSubscribers.AsQueryable()
                .Where(s => s.CompanyId.ToLower() == key)
                .OrderByDescending(s => s.CreatedAt)
                .ToListAsync();
            return Ok(new { data = own });
        }

        if (string.IsNullOrEmpty(companyId)) return BadRequest(new { message = "companyId مطلوب" });

        var items = await _unitOfWork.IptvSubscribers.AsQueryable()
            .Where(s => s.CompanyId == companyId)
            .OrderByDescending(s => s.CreatedAt)
            .ToListAsync();

        return Ok(new { data = items });
    }

    /// <summary>جلب مشترك IPTV بالمعرف</summary>
    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(long id)
    {
        var (caller, authError) = await AuthorizeIptvAsync();
        if (authError != null) return authError;

        var subscriber = await _unitOfWork.IptvSubscribers.GetByIdAsync(id);
        if (subscriber == null || !CanAccess(caller, subscriber.CompanyId))
            return NotFound(new { message = "المشترك غير موجود" });

        return Ok(new { data = subscriber });
    }

    /// <summary>إنشاء مشترك IPTV جديد</summary>
    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateIptvSubscriberRequest request)
    {
        var (caller, authError) = await AuthorizeIptvAsync();
        if (authError != null) return authError;

        var companyId = request.CompanyId;
        if (caller.IsTenantBound)
        {
            if (!string.IsNullOrEmpty(companyId) && !CanAccess(caller, companyId))
                return LegacyKeyOrJwtGate.Forbidden(LegacyKeyOrJwtGate.MsgOtherCompany);
            companyId = CompanyKey(caller.CompanyId!.Value); // الشركة من التوكن
        }

        if (string.IsNullOrEmpty(companyId)) return BadRequest(new { message = "companyId مطلوب" });
        if (string.IsNullOrEmpty(request.CustomerName)) return BadRequest(new { message = "customerName مطلوب" });

        var subscriber = new IptvSubscriber
        {
            CompanyId = companyId,
            SubscriptionId = request.SubscriptionId,
            CustomerName = request.CustomerName,
            Phone = request.Phone,
            IptvUsername = request.IptvUsername,
            IptvPassword = request.IptvPassword,
            IptvCode = request.IptvCode,
            ActivationDate = request.ActivationDate,
            DurationMonths = request.DurationMonths,
            IsActive = request.IsActive,
            Location = request.Location,
            Notes = request.Notes,
        };

        await _unitOfWork.IptvSubscribers.AddAsync(subscriber);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { data = subscriber });
    }

    /// <summary>تعديل مشترك IPTV</summary>
    [HttpPut("{id}")]
    public async Task<IActionResult> Update(long id, [FromBody] UpdateIptvSubscriberRequest request)
    {
        var (caller, authError) = await AuthorizeIptvAsync();
        if (authError != null) return authError;

        var subscriber = await _unitOfWork.IptvSubscribers.GetByIdAsync(id);
        if (subscriber == null || !CanAccess(caller, subscriber.CompanyId))
            return NotFound(new { message = "المشترك غير موجود" });

        subscriber.SubscriptionId = request.SubscriptionId;
        subscriber.CustomerName = request.CustomerName;
        subscriber.Phone = request.Phone;
        subscriber.IptvUsername = request.IptvUsername;
        subscriber.IptvPassword = request.IptvPassword;
        subscriber.IptvCode = request.IptvCode;
        subscriber.ActivationDate = request.ActivationDate;
        subscriber.DurationMonths = request.DurationMonths;
        subscriber.IsActive = request.IsActive;
        subscriber.Location = request.Location;
        subscriber.Notes = request.Notes;
        subscriber.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.IptvSubscribers.Update(subscriber);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, data = subscriber });
    }

    /// <summary>حذف مشترك IPTV (حذف ناعم)</summary>
    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(long id)
    {
        var (caller, authError) = await AuthorizeIptvAsync();
        if (authError != null) return authError;

        var subscriber = await _unitOfWork.IptvSubscribers.GetByIdAsync(id);
        if (subscriber == null || !CanAccess(caller, subscriber.CompanyId))
            return NotFound(new { message = "المشترك غير موجود" });

        subscriber.IsDeleted = true;
        subscriber.DeletedAt = DateTime.UtcNow;
        _unitOfWork.IptvSubscribers.Update(subscriber);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم الحذف بنجاح" });
    }
}

public record CreateIptvSubscriberRequest(
    string CompanyId,
    string? SubscriptionId,
    string CustomerName,
    string? Phone,
    string? IptvUsername,
    string? IptvPassword,
    string? IptvCode,
    DateTime? ActivationDate,
    int DurationMonths = 1,
    bool IsActive = true,
    string? Location = null,
    string? Notes = null
);

public record UpdateIptvSubscriberRequest(
    string? SubscriptionId,
    string CustomerName,
    string? Phone,
    string? IptvUsername,
    string? IptvPassword,
    string? IptvCode,
    DateTime? ActivationDate,
    int DurationMonths = 1,
    bool IsActive = true,
    string? Location = null,
    string? Notes = null
);
