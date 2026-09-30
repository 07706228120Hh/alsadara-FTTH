using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.API.Authorization;
using Sadara.Application.Interfaces;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Data;
using Sadara.Infrastructure.Services.Sas;

namespace Sadara.API.Controllers;

/// <summary>
/// بوّابة «وكيل SAS» — تدير حسابات الساس المربوطة بالموظّف وتمرّر النداءات لخدمة الساس الداخلية.
///
/// العزل الثلاثي (شركة + مالك + صلاحية):
///  - كل نقطة محميّة بـ [Authorize] + صلاحية <c>sas_agent</c> (النظام الثاني).
///  - كل وصول لحساب ساس يُفرَض عليه صراحةً: <c>CompanyId == tenant.CompanyId &amp;&amp; OwnerUserId == currentUserId &amp;&amp; !IsDeleted</c>
///    (دفاع بالعمق فوق فلتر المستأجر المركزي المعطّل افتراضياً).
///  - SuperAdmin (بلا شركة) مرفوض: هذه ميزة موظّف شركة لا يملكها سياق النظام (منع تسريب/التباس).
///
/// ⚠️ أمن الأسرار: كلمة المرور تُشفَّر عبر <see cref="ISecretProtector"/> قبل الحفظ، ولا تُعاد أبداً
/// في أي DTO/استجابة/سجل؛ تُفكّ في الذاكرة فقط لحظة التمرير لخدمة الساس.
/// لا يُقبل مفتاح X-Api-Key هنا — الاعتماد على JWT فقط.
/// </summary>
[ApiController]
[Route("api/sas-agent")]
[Authorize]
[RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
[Tags("SAS Agent")]
public class SasAgentController : ControllerBase
{
    private readonly SadaraDbContext _db;
    private readonly ICurrentTenant _tenant;
    private readonly ISecretProtector _secretProtector;
    private readonly ISasServiceClient _sasClient;
    private readonly ILogger<SasAgentController> _logger;

    public SasAgentController(
        SadaraDbContext db,
        ICurrentTenant tenant,
        ISecretProtector secretProtector,
        ISasServiceClient sasClient,
        ILogger<SasAgentController> logger)
    {
        _db = db;
        _tenant = tenant;
        _secretProtector = secretProtector;
        _sasClient = sasClient;
        _logger = logger;
    }

    /// <summary>معرّف المستخدم الحالي من التوكن (بنفس نمط باقي المتحكمات).</summary>
    private Guid GetCurrentUserId()
    {
        var userIdClaim = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value
                       ?? User.FindFirst("sub")?.Value;
        if (!string.IsNullOrEmpty(userIdClaim) && Guid.TryParse(userIdClaim, out var userId))
            return userId;
        return Guid.Empty;
    }

    /// <summary>
    /// حارس النطاق المركزي: يتحقّق من وجود شركة ومستخدم صالحين.
    /// يعيد companyId + userId عند النجاح، أو نتيجة رفض (Forbid) عند الفشل.
    /// SuperAdmin/سياق نظام (بلا CompanyId) => Forbid — ميزة موظّف شركة حصراً.
    /// </summary>
    private bool TryResolveScope(out Guid companyId, out Guid userId, out IActionResult? denied)
    {
        companyId = Guid.Empty;
        userId = Guid.Empty;
        denied = null;

        if (_tenant.CompanyId is not Guid cid || cid == Guid.Empty)
        {
            // منع SuperAdmin/سياق النظام من الوصول لبيانات موظّفي الشركات (صفر التباس/تسريب).
            denied = Forbid();
            return false;
        }

        var uid = GetCurrentUserId();
        if (uid == Guid.Empty)
        {
            denied = Forbid();
            return false;
        }

        companyId = cid;
        userId = uid;
        return true;
    }

    /// <summary>
    /// يجلب حساب ساس بمطابقة صارمة (شركة + مالك + غير محذوف). يعيد null إن لم يوجد ضمن النطاق.
    /// يُستخدم كنقطة العزل الوحيدة لأي وصول لحساب.
    /// </summary>
    private Task<SasAccount?> GetOwnedAccountAsync(Guid id, Guid companyId, Guid userId, CancellationToken ct)
        => _db.SasAccounts
            .FirstOrDefaultAsync(
                x => x.Id == id
                     && x.CompanyId == companyId
                     && x.OwnerUserId == userId
                     && !x.IsDeleted,
                ct);

    // ==================== إدارة الحسابات (DB) ====================

    /// <summary>جلب حسابات الساس للمستخدم الحالي فقط — بلا كلمات مرور.</summary>
    [HttpGet("accounts")]
    public async Task<IActionResult> GetAccounts(CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied))
            return denied!;

        try
        {
            var accounts = await _db.SasAccounts
                .Where(x => x.CompanyId == companyId && x.OwnerUserId == userId && !x.IsDeleted)
                .OrderBy(x => x.Label)
                .Select(x => new SasAccountDto(
                    x.Id,
                    x.Label,
                    x.ServerUrl,
                    x.Username,
                    x.AccountType,
                    x.IsActive,
                    x.LastSyncAt))
                .ToListAsync(ct);

            return Ok(new { success = true, data = accounts, total = accounts.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب حسابات الساس");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>ربط حساب ساس جديد — يشفّر كلمة المرور ويختم الشركة والمالك.</summary>
    [HttpPost("accounts")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> CreateAccount([FromBody] CreateSasAccountRequest request, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied))
            return denied!;

        if (string.IsNullOrWhiteSpace(request.ServerUrl) || string.IsNullOrWhiteSpace(request.Username))
            return BadRequest(new { success = false, message = "عنوان الخادم واسم المستخدم مطلوبان" });

        try
        {
            var account = new SasAccount
            {
                Id = Guid.NewGuid(),
                CompanyId = companyId,          // ختم العزل: شركة المستخدم الحالي
                OwnerUserId = userId,           // ختم العزل: مالك الحساب
                Label = request.Label?.Trim() ?? string.Empty,
                ServerUrl = request.ServerUrl.Trim(),
                Username = request.Username.Trim(),
                PasswordEncrypted = _secretProtector.Protect(request.Password ?? string.Empty),
                AccountType = request.AccountType,
                IsActive = request.IsActive ?? true
            };

            await _db.SasAccounts.AddAsync(account, ct);
            await _db.SaveChangesAsync(ct);

            // نعيد DTO بلا كلمة مرور.
            var dto = new SasAccountDto(
                account.Id, account.Label, account.ServerUrl, account.Username,
                account.AccountType, account.IsActive, account.LastSyncAt);

            return Ok(new { success = true, data = dto, message = "تم ربط حساب الساس بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إنشاء حساب الساس");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>تعديل حساب ساس — يعيد التشفير فقط إن أُرسلت كلمة مرور جديدة.</summary>
    [HttpPut("accounts/{id}")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> UpdateAccount(Guid id, [FromBody] UpdateSasAccountRequest request, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied))
            return denied!;

        try
        {
            var account = await GetOwnedAccountAsync(id, companyId, userId, ct);
            if (account == null)
                return NotFound(new { success = false, message = "حساب الساس غير موجود" });

            if (request.Label != null) account.Label = request.Label.Trim();
            if (!string.IsNullOrWhiteSpace(request.ServerUrl)) account.ServerUrl = request.ServerUrl.Trim();
            if (!string.IsNullOrWhiteSpace(request.Username)) account.Username = request.Username.Trim();
            if (request.AccountType.HasValue) account.AccountType = request.AccountType.Value;
            if (request.IsActive.HasValue) account.IsActive = request.IsActive.Value;

            // إعادة التشفير فقط عند إرسال كلمة مرور جديدة غير فارغة.
            if (!string.IsNullOrEmpty(request.Password))
                account.PasswordEncrypted = _secretProtector.Protect(request.Password);

            account.UpdatedAt = DateTime.UtcNow;
            _db.SasAccounts.Update(account);
            await _db.SaveChangesAsync(ct);

            return Ok(new { success = true, message = "تم تعديل حساب الساس بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تعديل حساب الساس");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>حذف حساب ساس (حذف ناعم) بعد المطابقة الصارمة.</summary>
    [HttpDelete("accounts/{id}")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> DeleteAccount(Guid id, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied))
            return denied!;

        try
        {
            var account = await GetOwnedAccountAsync(id, companyId, userId, ct);
            if (account == null)
                return NotFound(new { success = false, message = "حساب الساس غير موجود" });

            account.IsDeleted = true;
            account.DeletedAt = DateTime.UtcNow;
            account.IsActive = false;
            _db.SasAccounts.Update(account);
            await _db.SaveChangesAsync(ct);

            return Ok(new { success = true, message = "تم حذف حساب الساس بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حذف حساب الساس");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== نقاط التمرير لخدمة الساس ====================

    /// <summary>تسجيل دخول صامت لنظام الساس باعتماد الحساب (يُفكّ التشفير داخلياً فقط).</summary>
    [HttpPost("accounts/{id}/login")]
    public async Task<IActionResult> Login(Guid id, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied))
            return denied!;

        var account = await GetOwnedAccountAsync(id, companyId, userId, ct);
        if (account == null)
            return NotFound(new { success = false, message = "حساب الساس غير موجود" });

        try
        {
            var password = _secretProtector.Unprotect(account.PasswordEncrypted); // في الذاكرة فقط
            var result = await _sasClient.LoginAsync(account.ServerUrl, account.Username, password, ct);

            if (!result.Success)
                return StatusCode(502, new { success = false, message = result.Message ?? "تعذّر تسجيل الدخول لنظام الساس" });

            return Ok(new { success = true, sessionHandle = result.SessionHandle, message = result.Message });
        }
        catch (SasServiceUnavailableException ex)
        {
            _logger.LogWarning(ex, "خدمة الساس غير متاحة أثناء تسجيل الدخول");
            return StatusCode(503, new { success = false, message = "خدمة الساس غير متاحة حالياً" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تسجيل الدخول لنظام الساس");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>جلب لوحة الوكيل من خدمة الساس.</summary>
    [HttpGet("accounts/{id}/dashboard")]
    public Task<IActionResult> GetDashboard(Guid id, CancellationToken ct)
        => PassThroughAsync(id, (acc, pwd, token) =>
            _sasClient.GetDashboardAsync(acc.ServerUrl, acc.Username, pwd, token), null, ct);

    /// <summary>جلب مشتركي الوكيل من خدمة الساس.</summary>
    [HttpGet("accounts/{id}/subscribers")]
    public Task<IActionResult> GetSubscribers(Guid id, CancellationToken ct)
        => PassThroughAsync(id, (acc, pwd, token) =>
            _sasClient.GetSubscribersAsync(acc.ServerUrl, acc.Username, pwd, CollectQuery(), token), null, ct);

    /// <summary>جلب تقرير الوكيل (التصريح/البلنك) من خدمة الساس.</summary>
    [HttpGet("accounts/{id}/report")]
    public Task<IActionResult> GetReport(Guid id, CancellationToken ct)
        => PassThroughAsync(id, (acc, pwd, token) =>
            _sasClient.GetReportAsync(acc.ServerUrl, acc.Username, pwd, CollectQuery(), token), null, ct);

    /// <summary>
    /// نمط تمرير موحّد: يحصر النطاق، يجلب الحساب بالمطابقة الصارمة، يفكّ التشفير في الذاكرة،
    /// ينادي خدمة الساس، ويعيد JSON خاماً — مع ترجمة تعذّر الخدمة إلى 503.
    /// </summary>
    private async Task<IActionResult> PassThroughAsync(
        Guid id,
        Func<SasAccount, string, CancellationToken, Task<string>> call,
        object? _,
        CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied))
            return denied!;

        var account = await GetOwnedAccountAsync(id, companyId, userId, ct);
        if (account == null)
            return NotFound(new { success = false, message = "حساب الساس غير موجود" });

        try
        {
            var password = _secretProtector.Unprotect(account.PasswordEncrypted); // في الذاكرة فقط
            var raw = await call(account, password, ct);
            return Content(raw, "application/json");
        }
        catch (SasServiceUnavailableException ex)
        {
            _logger.LogWarning(ex, "خدمة الساس غير متاحة أثناء التمرير");
            return StatusCode(503, new { success = false, message = "خدمة الساس غير متاحة حالياً" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في التمرير لخدمة الساس");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// وسائط الاستعلام المسموح تمريرها لخدمة الساس (قائمة سماح صارمة، غير حسّاسة لحالة الأحرف).
    /// أي مفتاح خارج هذه القائمة يُتجاهَل.
    /// </summary>
    private static readonly HashSet<string> AllowedQueryKeys = new(StringComparer.OrdinalIgnoreCase)
    {
        "search", "page", "pageSize", "from", "to", "status", "profile"
    };

    /// <summary>الحد الأقصى لطول قيمة أي وسيط استعلام يُمرَّر لخدمة الساس.</summary>
    private const int MaxQueryValueLength = 200;

    /// <summary>
    /// يجمع وسائط الاستعلام المسموح بها فقط لتمريرها لخدمة الساس (بلا أسرار)،
    /// مع تجاهل أي مفتاح خارج قائمة السماح وقصّ القيم الطويلة.
    /// </summary>
    private Dictionary<string, string?> CollectQuery()
    {
        var q = new Dictionary<string, string?>();
        foreach (var kv in Request.Query)
        {
            if (!AllowedQueryKeys.Contains(kv.Key))
                continue;

            var value = kv.Value.ToString();
            if (value.Length > MaxQueryValueLength)
                value = value[..MaxQueryValueLength];

            q[kv.Key] = value;
        }
        return q;
    }
}

// ==================== DTOs ====================

/// <summary>DTO عرض حساب ساس — ⚠️ بلا كلمة مرور (مشفّرة أو صريحة) إطلاقاً.</summary>
public record SasAccountDto(
    Guid Id,
    string Label,
    string ServerUrl,
    string Username,
    SasAccountType AccountType,
    bool IsActive,
    DateTime? LastSyncAt);

/// <summary>طلب ربط حساب ساس جديد.</summary>
public record CreateSasAccountRequest(
    string? Label,
    string ServerUrl,
    string Username,
    string? Password,
    SasAccountType AccountType,
    bool? IsActive);

/// <summary>طلب تعديل حساب ساس — كل الحقول اختيارية؛ Password فقط عند التغيير.</summary>
public record UpdateSasAccountRequest(
    string? Label,
    string? ServerUrl,
    string? Username,
    string? Password,
    SasAccountType? AccountType,
    bool? IsActive);
