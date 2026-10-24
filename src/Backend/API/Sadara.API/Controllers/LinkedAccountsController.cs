using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Sadara.API.Authorization;
using Sadara.Application.Interfaces;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Data;

namespace Sadara.API.Controllers;

/// <summary>
/// طبقة API موحّدة لميزة «الحسابات المرتبطة المتعددة لكل موظف».
///
/// تدير حسابات FTTH المتعددة المربوطة بالموظّف (كيان <see cref="FtthAccount"/>) وتعرض — للقراءة فقط —
/// حسابات الساس المربوطة بنفس الموظّف (كيان <see cref="SasAccount"/>) ضمن قائمة موحّدة.
///
/// العزل (دفاع بالعمق فوق الفلتر المركزي المعطّل افتراضياً):
///  - <c>[Authorize]</c> + JWT حصراً (لا X-Api-Key) + صلاحية <c>linked_accounts</c> (النظام الثاني،
///    <c>failClosed:true</c> — تُرفَض عند فراغ صلاحيات V2 كبوّابة حسّاسة، بنمط <c>sas_agent</c>).
///  - SuperAdmin/سياق النظام (بلا CompanyId) => <c>Forbid</c> — ميزة موظّف شركة لا يملكها سياق النظام.
///  - كل وصول لحساب FTTH يُفرَض عليه: <c>CompanyId == tenant.CompanyId &amp;&amp; !IsDeleted</c>
///    + (مالكُه هو المستخدم الحالي، أو المستخدم أدمن شركة فأعلى يدير حسابات موظّف من نفس شركته).
///
/// ⚠️ أمن الأسرار: كلمة المرور تُشفَّر عبر <see cref="ISecretProtector"/> قبل الحفظ ولا تُعاد أبداً في
/// أي قائمة/استجابة عرض؛ تُفكّ في الذاكرة فقط لحظة تسجيل الدخول/التحقّق لنظام FTTH. نقطتا
/// <c>reveal</c>/<c>login</c> الحسّاستان محصورتان بأدمن الشركة (reveal) وتُسجَّل عملية الكشف للتدقيق
/// (بلا طباعة كلمة المرور). لا يُعاد <c>PasswordEncrypted</c> في أي حال.
///
/// ملاحظة توافق: المتحكّم الجديد لا يلمس المسارات القديمة في <c>FtthAccountingController</c>
/// (operators-linking / link-ftth-account / ftth-credentials) ولا الأعمدة القديمة على <c>User</c>
/// (<c>FtthUsername</c>/<c>FtthPasswordEncrypted</c>) — تبقى كما هي للتوافق.
/// </summary>
[ApiController]
[Route("api/linked-accounts")]
[Authorize]
[Tags("Linked Accounts")]
public class LinkedAccountsController : ControllerBase
{
    /// <summary>المضيف الافتراضي لنظام FTTH عند غياب ServerUrl.</summary>
    private const string DefaultFtthBaseUrl = "https://admin.ftth.iq";

    private readonly SadaraDbContext _db;
    private readonly ICurrentTenant _tenant;
    private readonly ISecretProtector _secretProtector;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IConfiguration _configuration;
    private readonly ILogger<LinkedAccountsController> _logger;

    public LinkedAccountsController(
        SadaraDbContext db,
        ICurrentTenant tenant,
        ISecretProtector secretProtector,
        IHttpClientFactory httpClientFactory,
        IConfiguration configuration,
        ILogger<LinkedAccountsController> logger)
    {
        _db = db;
        _tenant = tenant;
        _secretProtector = secretProtector;
        _httpClientFactory = httpClientFactory;
        _configuration = configuration;
        _logger = logger;
    }

    // ==================== أمان: قائمة سماح مضيفات FTTH (إغلاق SSRF) ====================

    /// <summary>
    /// يتحقّق أنّ عنوان خادم FTTH مسموح به لإغلاق SSRF:
    ///  - يُحلّل كـ Uri مطلق صحيح.
    ///  - المخطّط https حصراً (رفض http وأي مخطّط آخر).
    ///  - المضيف (Host وحده) ضمن قائمة السماح (Ftth:AllowedHosts، افتراضي admin.ftth.iq) — غير حسّاس لحالة الأحرف.
    ///  - بلا UserInfo (رفض "user:pass@host").
    /// قائمة السماح تُغني عن فحص نطاقات private/loopback لأن المضيف يجب أن يطابق المسموح؛ لا حلّ DNS.
    /// </summary>
    private bool IsAllowedFtthServerUrl(string? serverUrl)
    {
        if (string.IsNullOrWhiteSpace(serverUrl))
            return false;

        if (!Uri.TryCreate(serverUrl.Trim(), UriKind.Absolute, out var uri))
            return false;

        if (!string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
            return false;

        if (!string.IsNullOrEmpty(uri.UserInfo))
            return false;

        var allowedHosts = _configuration.GetSection("Ftth:AllowedHosts").Get<string[]>();
        if (allowedHosts == null || allowedHosts.Length == 0)
            allowedHosts = new[] { "admin.ftth.iq" };

        return allowedHosts.Any(h => string.Equals(h, uri.Host, StringComparison.OrdinalIgnoreCase));
    }

    // ==================== أمان: تحقّق أدنى من عنوان خادم الساس ====================

    /// <summary>
    /// تحقّق أدنى من صلاحية عنوان خادم الساس (ليس allowlist — خوادم الساس تختلف لكل مزوّد):
    ///  - يُحلّل كـ Uri مطلق صحيح.
    ///  - المخطّط http أو https حصراً (رفض أي مخطّط آخر مثل file/ftp/gopher).
    ///  - بلا UserInfo (رفض "user:pass@host").
    /// لا يُطبَّق هنا فحص قائمة سماح المضيفات الخاص بـ FTTH.
    /// </summary>
    private bool IsValidSasServerUrl(string? serverUrl)
    {
        if (string.IsNullOrWhiteSpace(serverUrl))
            return false;

        if (!Uri.TryCreate(serverUrl.Trim(), UriKind.Absolute, out var uri))
            return false;

        if (!string.Equals(uri.Scheme, Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase)
            && !string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
            return false;

        if (!string.IsNullOrEmpty(uri.UserInfo))
            return false;

        return true;
    }

    // ==================== الحرّاس (منسوخة من نمط SasAgentController) ====================

    /// <summary>معرّف المستخدم الحالي من التوكن.</summary>
    private Guid GetCurrentUserId()
    {
        var userIdClaim = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value
                       ?? User.FindFirst("sub")?.Value;
        if (!string.IsNullOrEmpty(userIdClaim) && Guid.TryParse(userIdClaim, out var userId))
            return userId;
        return Guid.Empty;
    }

    /// <summary>
    /// حارس النطاق: يتحقّق من وجود شركة ومستخدم صالحين من التوكن.
    /// SuperAdmin/سياق نظام (بلا CompanyId) => Forbid — ميزة موظّف شركة حصراً.
    /// </summary>
    private bool TryResolveScope(out Guid companyId, out Guid userId, out IActionResult? denied)
    {
        companyId = Guid.Empty;
        userId = Guid.Empty;
        denied = null;

        if (_tenant.CompanyId is not Guid cid || cid == Guid.Empty)
        {
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
    /// يقرأ الدور من التوكن (role_id أو ClaimTypes.Role) ويتحقّق أنّه CompanyAdmin فأعلى.
    /// نسخة مطابقة لنمط SasAgentController.
    /// </summary>
    private bool IsCompanyAdminOrAbove()
    {
        var roleClaim = User.FindFirst("role_id")?.Value
                     ?? User.FindFirst(System.Security.Claims.ClaimTypes.Role)?.Value
                     ?? User.FindFirst("role")?.Value;

        if (string.IsNullOrWhiteSpace(roleClaim))
            return false;

        if (int.TryParse(roleClaim, out var roleInt))
            return roleInt >= (int)UserRole.CompanyAdmin;

        return string.Equals(roleClaim, nameof(UserRole.CompanyAdmin), StringComparison.OrdinalIgnoreCase)
            || string.Equals(roleClaim, nameof(UserRole.SuperAdmin), StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// يحلّ الموظّف الهدف لعمليات القائمة/الإنشاء:
    ///  - فارغ أو == المستخدم الحالي => المستخدم الحالي (إدارة حساباته).
    ///  - موظّف آخر => يتطلب أدمن شركة فأعلى + أن يكون الموظّف الهدف ضمن نفس الشركة.
    /// </summary>
    private async Task<(bool ok, Guid targetUserId, IActionResult? denied)> ResolveTargetUserAsync(
        Guid requestedUserId, Guid companyId, Guid currentUserId, CancellationToken ct)
    {
        if (requestedUserId == Guid.Empty || requestedUserId == currentUserId)
            return (true, currentUserId, null);

        if (!IsCompanyAdminOrAbove())
            return (false, Guid.Empty, Forbid());

        var targetInCompany = await _db.Users.AnyAsync(
            u => u.Id == requestedUserId && u.CompanyId == companyId && !u.IsDeleted, ct);
        if (!targetInCompany)
            return (false, Guid.Empty, NotFound(new { success = false, message = "الموظف غير موجود ضمن شركتك" }));

        return (true, requestedUserId, null);
    }

    /// <summary>
    /// يجلب حساب FTTH بمطابقة صارمة: شركة التوكن + غير محذوف + (مالكه المستخدم الحالي أو المستخدم أدمن
    /// شركة فأعلى يدير حسابات شركته). نقطة العزل الوحيدة لأي وصول لحساب FTTH. يعيد null إن لم يوجد ضمن النطاق.
    /// </summary>
    private Task<FtthAccount?> GetAccessibleAccountAsync(Guid id, Guid companyId, Guid currentUserId, CancellationToken ct)
    {
        var isAdmin = IsCompanyAdminOrAbove();
        return _db.FtthAccounts.FirstOrDefaultAsync(
            x => x.Id == id
                 && x.CompanyId == companyId
                 && !x.IsDeleted
                 && (isAdmin || x.OwnerUserId == currentUserId),
            ct);
    }

    /// <summary>
    /// يجلب حساب ساس بمطابقة صارمة: شركة التوكن + غير محذوف + (مالكه المستخدم الحالي أو المستخدم أدمن
    /// شركة فأعلى يدير حسابات شركته). نقطة العزل الوحيدة لأي وصول لحساب ساس للتعديل/الحذف — على غرار
    /// <see cref="GetAccessibleAccountAsync"/> لكن على <c>_db.SasAccounts</c>. يعيد null إن لم يوجد ضمن النطاق.
    /// </summary>
    private Task<SasAccount?> GetAccessibleSasAccountAsync(Guid id, Guid companyId, Guid currentUserId, CancellationToken ct)
    {
        var isAdmin = IsCompanyAdminOrAbove();
        return _db.SasAccounts.FirstOrDefaultAsync(
            x => x.Id == id
                 && x.CompanyId == companyId
                 && !x.IsDeleted
                 && (isAdmin || x.OwnerUserId == currentUserId),
            ct);
    }

    /// <summary>يصفّر علم «الأساسي» عن بقية حسابات FTTH لنفس (الشركة+المالك) عدا حساباً اختيارياً. لا يحفظ.</summary>
    private async Task ClearPrimaryAsync(Guid companyId, Guid ownerUserId, Guid? exceptId, CancellationToken ct)
    {
        var others = await _db.FtthAccounts
            .Where(x => x.CompanyId == companyId
                        && x.OwnerUserId == ownerUserId
                        && x.IsPrimary
                        && !x.IsDeleted
                        && (exceptId == null || x.Id != exceptId))
            .ToListAsync(ct);

        foreach (var o in others)
        {
            o.IsPrimary = false;
            o.UpdatedAt = DateTime.UtcNow;
        }
    }

    // ==================== 1) القائمة الموحّدة ====================

    /// <summary>
    /// قائمة موحّدة لحسابات الموظّف: حسابات FTTH (قابلة للإدارة) + حسابات الساس (قراءة فقط عبر DbContext).
    /// بلا أي كلمة مرور. (linked_accounts.view) — إدارة حسابات موظّف آخر تتطلب أدمن شركة + نفس الشركة.
    /// </summary>
    [HttpGet]
    // لا نشترط صلاحية linked_accounts هنا: عرض حسابات المستخدم نفسه مسموح دائماً (بلا كلمة مرور)،
    // والعزل مضمون عبر ResolveTargetUserAsync (عرض حسابات موظّف آخر يتطلب أدمن شركة + نفس الشركة).
    // بهذا يعمل الدخول الصامت لـFTTH لأي موظف يملك حساباً مرتبطاً دون منح صلاحية يدوي.
    public async Task<IActionResult> GetLinkedAccounts([FromQuery] Guid? userId, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var currentUserId, out var denied))
            return denied!;

        var (ok, targetUserId, tdenied) = await ResolveTargetUserAsync(userId ?? Guid.Empty, companyId, currentUserId, ct);
        if (!ok) return tdenied!;

        try
        {
            // حسابات FTTH (العزل: شركة التوكن + مالك الهدف).
            var ftth = await _db.FtthAccounts
                .AsNoTracking()
                .Where(x => x.CompanyId == companyId && x.OwnerUserId == targetUserId && !x.IsDeleted)
                .OrderByDescending(x => x.IsPrimary)
                .ThenBy(x => x.Label)
                .Select(x => new LinkedAccountDto(
                    x.Id, "Ftth", x.Label, x.Username, x.ServerUrl, x.Role,
                    x.IsActive, x.IsPrimary, x.Status, x.LastVerifiedAt, x.LastLoginAt, true,
                    null, null, x.FtthMemberId))
                .ToListAsync(ct);

            // حسابات الساس (قراءة فقط — لا نُنادي وحدة الساس ولا نعدّلها). نوع الحساب يُحوَّل لنص في الذاكرة.
            var sasRaw = await _db.SasAccounts
                .AsNoTracking()
                .Where(x => x.CompanyId == companyId && x.OwnerUserId == targetUserId && !x.IsDeleted)
                .OrderBy(x => x.Label)
                .Select(x => new { x.Id, x.Label, x.Username, x.ServerUrl, x.AccountType, x.AmountMultiplier, x.IsActive, x.SyncStatus, x.LastSyncAt })
                .ToListAsync(ct);

            var sas = sasRaw.Select(x => new LinkedAccountDto(
                x.Id, "Sas", x.Label, x.Username, x.ServerUrl, x.AccountType.ToString(),
                x.IsActive, false, x.SyncStatus, x.LastSyncAt, null, true,
                (int)x.AccountType, x.AmountMultiplier)).ToList();

            var data = ftth.Concat(sas).ToList();
            return Ok(new { success = true, data, total = data.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب الحسابات المرتبطة للموظف");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== 2) إنشاء حساب FTTH ====================

    /// <summary>
    /// إنشاء حساب FTTH لموظّف — يشفّر كلمة المرور ويختم CompanyId من التوكن. (linked_accounts.create)
    /// إن كان الهدف موظّفاً آخر وجب أن يكون المنشئ أدمن شركة + الهدف من نفس الشركة.
    /// isPrimary=true يصفّر «الأساسي» عن بقية حسابات FTTH لنفس الموظّف. الحالة الأولية Unverified.
    /// </summary>
    [HttpPost("ftth")]
    [RequirePermission("linked_accounts", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> CreateFtth([FromBody] CreateFtthAccountRequest request, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var currentUserId, out var denied))
            return denied!;

        if (request == null || string.IsNullOrWhiteSpace(request.Username))
            return BadRequest(new { success = false, message = "اسم المستخدم مطلوب" });

        // إغلاق SSRF: إن أُرسل ServerUrl غير فارغ وجب أن يمرّ قائمة السماح. الفراغ => DefaultFtthBaseUrl المسموح.
        if (!string.IsNullOrWhiteSpace(request.ServerUrl) && !IsAllowedFtthServerUrl(request.ServerUrl))
            return BadRequest(new { success = false, message = "عنوان خادم FTTH غير مسموح" });

        var ownerId = request.OwnerUserId == Guid.Empty ? currentUserId : request.OwnerUserId;
        var (ok, targetUserId, tdenied) = await ResolveTargetUserAsync(ownerId, companyId, currentUserId, ct);
        if (!ok) return tdenied!;

        try
        {
            var account = new FtthAccount
            {
                Id = Guid.NewGuid(),
                CompanyId = companyId,          // ختم العزل من التوكن
                OwnerUserId = targetUserId,     // مالك الحساب (الحالي أو موظّف شركته للأدمن)
                Label = request.Label?.Trim() ?? string.Empty,
                Username = request.Username.Trim(),
                ServerUrl = string.IsNullOrWhiteSpace(request.ServerUrl) ? DefaultFtthBaseUrl : request.ServerUrl.Trim(),
                Role = string.IsNullOrWhiteSpace(request.Role) ? null : request.Role.Trim(),
                FtthMemberId = string.IsNullOrWhiteSpace(request.FtthMemberId) ? null : request.FtthMemberId.Trim(),
                PasswordEncrypted = _secretProtector.Protect(request.Password ?? string.Empty),
                IsActive = true,
                IsPrimary = request.IsPrimary ?? false,
                Status = "Unverified"
            };

            if (account.IsPrimary)
                await ClearPrimaryAsync(companyId, targetUserId, null, ct);

            await _db.FtthAccounts.AddAsync(account, ct);
            await _db.SaveChangesAsync(ct);

            // تدقيق أمني: من أنشأ أي حساب FTTH ولأي مالك — بلا كلمة مرور في السجل.
            _logger.LogWarning(
                "AUDIT إنشاء حساب FTTH: actorUserId={Actor} companyId={CompanyId} accountId={AccountId} ownerUserId={Owner} atUtc={AtUtc}",
                currentUserId, companyId, account.Id, account.OwnerUserId, DateTime.UtcNow);

            return Ok(new { success = true, data = ToDto(account), message = "تم ربط حساب FTTH بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إنشاء حساب FTTH");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== 3) تعديل حساب FTTH ====================

    /// <summary>
    /// تعديل label/username/isActive/isPrimary — وإعادة تشفير كلمة المرور فقط إن أُرسلت جديدة غير فارغة. (linked_accounts.edit)
    /// </summary>
    [HttpPut("ftth/{id}")]
    [RequirePermission("linked_accounts", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> UpdateFtth(Guid id, [FromBody] UpdateFtthAccountRequest request, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var currentUserId, out var denied))
            return denied!;

        try
        {
            var account = await GetAccessibleAccountAsync(id, companyId, currentUserId, ct);
            if (account == null)
                return NotFound(new { success = false, message = "حساب FTTH غير موجود" });

            // إغلاق SSRF: إن أُرسل ServerUrl غير فارغ وجب أن يمرّ قائمة السماح قبل تعيينه.
            if (!string.IsNullOrWhiteSpace(request.ServerUrl))
            {
                if (!IsAllowedFtthServerUrl(request.ServerUrl))
                    return BadRequest(new { success = false, message = "عنوان خادم FTTH غير مسموح" });
                account.ServerUrl = request.ServerUrl.Trim();
            }

            if (request.Label != null) account.Label = request.Label.Trim();
            if (!string.IsNullOrWhiteSpace(request.Username)) account.Username = request.Username.Trim();
            if (!string.IsNullOrWhiteSpace(request.FtthMemberId)) account.FtthMemberId = request.FtthMemberId.Trim();
            if (request.IsActive.HasValue) account.IsActive = request.IsActive.Value;

            // إعادة التشفير فقط عند إرسال كلمة مرور جديدة غير فارغة (نفس نمط SasAgentController).
            var passwordChanged = !string.IsNullOrEmpty(request.Password);
            if (passwordChanged)
                account.PasswordEncrypted = _secretProtector.Protect(request.Password!);

            if (request.IsPrimary == true)
            {
                account.IsPrimary = true;
                await ClearPrimaryAsync(companyId, account.OwnerUserId, account.Id, ct);
            }
            else if (request.IsPrimary == false)
            {
                account.IsPrimary = false;
            }

            account.UpdatedAt = DateTime.UtcNow;
            _db.FtthAccounts.Update(account);
            await _db.SaveChangesAsync(ct);

            // تدقيق أمني: من عدّل أي حساب FTTH وهل أُعيد تشفير كلمة المرور — بلا كلمة مرور في السجل.
            _logger.LogWarning(
                "AUDIT تعديل حساب FTTH: actorUserId={Actor} companyId={CompanyId} accountId={AccountId} ownerUserId={Owner} passwordChanged={PasswordChanged} atUtc={AtUtc}",
                currentUserId, companyId, account.Id, account.OwnerUserId, passwordChanged, DateTime.UtcNow);

            return Ok(new { success = true, data = ToDto(account), message = "تم تعديل حساب FTTH بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تعديل حساب FTTH");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== 4) حذف ناعم ====================

    /// <summary>حذف ناعم لحساب FTTH (IsDeleted=true). (linked_accounts.delete)</summary>
    [HttpDelete("ftth/{id}")]
    [RequirePermission("linked_accounts", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> DeleteFtth(Guid id, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var currentUserId, out var denied))
            return denied!;

        try
        {
            var account = await GetAccessibleAccountAsync(id, companyId, currentUserId, ct);
            if (account == null)
                return NotFound(new { success = false, message = "حساب FTTH غير موجود" });

            account.IsDeleted = true;
            account.DeletedAt = DateTime.UtcNow;
            account.IsActive = false;
            account.IsPrimary = false;
            _db.FtthAccounts.Update(account);
            await _db.SaveChangesAsync(ct);

            // تدقيق أمني: من حذف أي حساب FTTH (حذف ناعم) — بلا كلمة مرور في السجل.
            _logger.LogWarning(
                "AUDIT حذف حساب FTTH: actorUserId={Actor} companyId={CompanyId} accountId={AccountId} ownerUserId={Owner} atUtc={AtUtc}",
                currentUserId, companyId, account.Id, account.OwnerUserId, DateTime.UtcNow);

            return Ok(new { success = true, message = "تم حذف حساب FTTH بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حذف حساب FTTH");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== 5) التحقّق من صحة الاعتماد ====================

    /// <summary>
    /// التحقّق من صحة اعتماد الحساب: فكّ التشفير في الذاكرة + تسجيل دخول لنظام FTTH (بترويسات WAF) +
    /// تحديث LastVerifiedAt/Status ("Verified"/"Invalid"). يعيد نجاح/فشل فقط — لا توكن ولا سرّ. (linked_accounts.edit)
    /// </summary>
    [HttpPost("ftth/{id}/verify")]
    [RequirePermission("linked_accounts", "manage", PermissionSystem.Second, failClosed: true)]
    [EnableRateLimiting("credential-reveal")]
    public async Task<IActionResult> VerifyFtth(Guid id, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var currentUserId, out var denied))
            return denied!;

        var account = await GetAccessibleAccountAsync(id, companyId, currentUserId, ct);
        if (account == null)
            return NotFound(new { success = false, message = "حساب FTTH غير موجود" });

        try
        {
            var password = _secretProtector.Unprotect(account.PasswordEncrypted); // في الذاكرة فقط
            var result = await FtthLoginAsync(account.ServerUrl, account.Username, password, ct);

            account.Status = result.Ok ? "Verified" : "Invalid";
            if (result.Ok)
            {
                account.LastVerifiedAt = DateTime.UtcNow;
                // بعد دخول ناجح: اجلب بيانات العضو من FTTH وخزّن رقم العضو (المصدر الموحّد لمطابقة العمليات)
                // والدور/الاسم للعرض. لا يُرمى استثناء — فشل الجلب لا يُفشل التوثيق.
                var info = await FetchFtthMemberInfoAsync(account.ServerUrl, result.AccessToken!, account.Username, ct);
                if (!string.IsNullOrWhiteSpace(info.MemberId)) account.FtthMemberId = info.MemberId;
                if (!string.IsNullOrWhiteSpace(info.Role)) account.Role = info.Role;
            }
            account.UpdatedAt = DateTime.UtcNow;
            _db.FtthAccounts.Update(account);
            await _db.SaveChangesAsync(ct);

            return Ok(new
            {
                success = true,
                data = new
                {
                    verified = result.Ok,
                    status = account.Status,
                    lastVerifiedAt = account.LastVerifiedAt,
                    ftthMemberId = account.FtthMemberId,
                    role = account.Role
                },
                message = result.Ok
                    ? (account.FtthMemberId != null ? "تم التحقق وجلب رقم العضو بنجاح" : "تم التحقق (لم يُعثر على رقم عضو مطابق)")
                    : "فشل التحقق من بيانات الاعتماد"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في التحقق من حساب FTTH");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== 6) كشف كلمة المرور (أدمن فقط + تدقيق) ====================

    /// <summary>
    /// يعيد كلمة المرور الصريحة لمرّة العرض (IsCompanyAdminOrAbove فقط). (linked_accounts.edit + أدمن شركة)
    /// ⚠️ يُسجَّل تدقيق عبر ILogger (من طلب الكشف + معرّف الحساب + المالك + الوقت) دون طباعة كلمة المرور.
    /// </summary>
    [HttpPost("ftth/{id}/reveal")]
    [RequirePermission("linked_accounts", "manage", PermissionSystem.Second, failClosed: true)]
    [EnableRateLimiting("credential-reveal")]
    public async Task<IActionResult> RevealFtth(Guid id, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var currentUserId, out var denied))
            return denied!;
        if (!IsCompanyAdminOrAbove())
            return Forbid();

        var account = await GetAccessibleAccountAsync(id, companyId, currentUserId, ct);
        if (account == null)
            return NotFound(new { success = false, message = "حساب FTTH غير موجود" });

        try
        {
            var password = _secretProtector.Unprotect(account.PasswordEncrypted); // في الذاكرة فقط

            // تدقيق أمني: من كشف أي حساب ومتى — بلا كلمة المرور في السجل.
            _logger.LogWarning(
                "AUDIT كشف كلمة مرور حساب FTTH: requestedByUserId={RequestedBy} companyId={CompanyId} accountId={AccountId} ownerUserId={OwnerUserId} atUtc={AtUtc}",
                currentUserId, companyId, account.Id, account.OwnerUserId, DateTime.UtcNow);

            // تدقيق مُعمَّر في القاعدة: يُكتب أولاً ثم يُعاد السرّ — إن فشل الحفظ لا نكشف شيئاً.
            // CompanyId/RequestedByUserId مختومان من التوكن لا من العميل. بلا تخزين كلمة المرور.
            await _db.CredentialRevealAudits.AddAsync(new CredentialRevealAudit
            {
                Id = Guid.NewGuid(),
                CompanyId = companyId,
                RequestedByUserId = currentUserId,
                AccountId = account.Id,
                Provider = "Ftth",
                OwnerUserId = account.OwnerUserId,
                RevealedAtUtc = DateTime.UtcNow
            }, ct);
            await _db.SaveChangesAsync(ct);

            return Ok(new { success = true, data = new { password } });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في كشف كلمة مرور حساب FTTH accountId={AccountId}", account.Id);
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== 6ب) كشف كلمة مرور حساب الساس (أدمن فقط + تدقيق) ====================

    /// <summary>
    /// يعيد كلمة مرور حساب الساس الصريحة لمرّة العرض (IsCompanyAdminOrAbove فقط). (linked_accounts.edit + أدمن شركة)
    /// يقرأ جدول SasAccounts عبر DbContext بعزل صارم (شركة التوكن + غير محذوف + مالكه الحالي ما لم يكن أدمن)
    /// ويفكّ التشفير عبر نفس <see cref="ISecretProtector"/> المستخدم في وحدة الساس — في الذاكرة فقط.
    /// ⚠️ يُسجَّل تدقيق عبر ILogger (من طلب الكشف + الشركة + معرّف الحساب + المالك + الوقت) دون طباعة كلمة المرور.
    /// لا يلمس وحدة الساس (modules/sas-agent) ولا كيان SasAccount — قراءة فقط.
    /// </summary>
    [HttpPost("sas/{id}/reveal")]
    [RequirePermission("linked_accounts", "manage", PermissionSystem.Second, failClosed: true)]
    [EnableRateLimiting("credential-reveal")]
    public async Task<IActionResult> RevealSas(Guid id, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var currentUserId, out var denied))
            return denied!;
        if (!IsCompanyAdminOrAbove())
            return Forbid();

        // علَم إعداد يحصر كشف اعتماد الساس (OFF افتراضياً) — قرار المالك.
        // FTTH لا يخضع لهذا العلَم (اعتُمد سابقاً). المفتاح لا يُكتب true في appsettings؛ الافتراضي OFF هنا.
        if (!_configuration.GetValue<bool>("Sas:AllowCredentialReveal", false))
            return StatusCode(403, new { success = false, message = "كشف اعتماد الساس معطّل" });

        var isAdmin = IsCompanyAdminOrAbove();
        var account = await _db.SasAccounts.FirstOrDefaultAsync(
            x => x.Id == id
                 && x.CompanyId == companyId
                 && !x.IsDeleted
                 && (isAdmin || x.OwnerUserId == currentUserId),
            ct);
        if (account == null)
            return NotFound(new { success = false, message = "حساب الساس غير موجود" });

        try
        {
            var password = _secretProtector.Unprotect(account.PasswordEncrypted); // في الذاكرة فقط

            // تدقيق أمني: من كشف أي حساب ساس ومتى — بلا كلمة المرور في السجل.
            _logger.LogWarning(
                "AUDIT كشف كلمة مرور حساب الساس: requestedByUserId={RequestedBy} companyId={CompanyId} accountId={AccountId} ownerUserId={OwnerUserId} atUtc={AtUtc}",
                currentUserId, companyId, account.Id, account.OwnerUserId, DateTime.UtcNow);

            // تدقيق مُعمَّر في القاعدة: يُكتب أولاً ثم يُعاد السرّ — إن فشل الحفظ لا نكشف شيئاً.
            // CompanyId/RequestedByUserId مختومان من التوكن لا من العميل. بلا تخزين كلمة المرور.
            await _db.CredentialRevealAudits.AddAsync(new CredentialRevealAudit
            {
                Id = Guid.NewGuid(),
                CompanyId = companyId,
                RequestedByUserId = currentUserId,
                AccountId = account.Id,
                Provider = "Sas",
                OwnerUserId = account.OwnerUserId,
                RevealedAtUtc = DateTime.UtcNow
            }, ct);
            await _db.SaveChangesAsync(ct);

            return Ok(new { success = true, data = new { password } });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في كشف كلمة مرور حساب الساس accountId={AccountId}", account.Id);
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== 6ج) إدارة حسابات الساس (إنشاء/تعديل/حذف ناعم) ====================
    // كتابة على جدول SasAccounts عبر DbContext من متحكّم النواة — لإدارة حسابات الساس من تبويب
    // «الحسابات المرتبطة» (نموذج الأدمن، مثل FTTH). لا تلمس وحدة الساس (modules/sas-agent) ولا
    // SasAgentController ولا كيان SasAccount. لا أوركسترا مزامنة هنا (المزامنة نقطة منفصلة في وحدة الساس) —
    // يُكتفى بسجلّ الحساب نفسه. القيم الافتراضية مطابقة لـ SasAgentController.CreateAccount/UpdateAccount.
    // لا يُعاد أي سرّ (PasswordEncrypted) في أي استجابة. لا يخضع لعلَم Sas:AllowCredentialReveal (خاص بالكشف فقط).

    /// <summary>
    /// إنشاء حساب ساس لموظّف — يشفّر كلمة المرور ويختم CompanyId من التوكن. (linked_accounts.manage)
    /// إن كان الهدف موظّفاً آخر وجب أن يكون المنشئ أدمن شركة + الهدف من نفس الشركة (ResolveTargetUserAsync).
    /// القيم الافتراضية مطابقة لـ SasAgentController: AmountMultiplier=1000 عند غيابها/عدم موجبيتها،
    /// AccountType=SasManager عند غيابه، IsActive=true عند غيابه. لا تُعاد كلمة المرور.
    /// </summary>
    [HttpPost("sas")]
    [RequirePermission("linked_accounts", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> CreateSas([FromBody] CreateSasLinkedAccountRequest request, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var currentUserId, out var denied))
            return denied!;

        if (request == null
            || string.IsNullOrWhiteSpace(request.ServerUrl)
            || string.IsNullOrWhiteSpace(request.Username))
            return BadRequest(new { success = false, message = "عنوان الخادم واسم المستخدم مطلوبان" });

        // تحقّق أدنى من عنوان خادم الساس (ليس allowlist — خوادم الساس تختلف لكل مزوّد).
        if (!IsValidSasServerUrl(request.ServerUrl))
            return BadRequest(new { success = false, message = "عنوان خادم الساس غير صالح" });

        var ownerId = request.OwnerUserId == Guid.Empty ? currentUserId : request.OwnerUserId;
        var (ok, targetUserId, tdenied) = await ResolveTargetUserAsync(ownerId, companyId, currentUserId, ct);
        if (!ok) return tdenied!;

        try
        {
            var account = new SasAccount
            {
                Id = Guid.NewGuid(),
                CompanyId = companyId,          // ختم العزل من التوكن
                OwnerUserId = targetUserId,     // مالك الحساب (الحالي أو موظّف شركته للأدمن)
                Label = request.Label?.Trim() ?? string.Empty,
                ServerUrl = request.ServerUrl.Trim(),
                Username = request.Username.Trim(),
                PasswordEncrypted = _secretProtector.Protect(request.Password ?? string.Empty),
                AccountType = request.AccountType ?? SasAccountType.SasManager,
                IsActive = request.IsActive ?? true,
                // مُضاعِف القيم المالية (افتراضي 1000 لمزوّدي SAS4 الذين يُرجعون بالآلاف) — مطابق لـ SasAgentController.
                AmountMultiplier = (request.AmountMultiplier is > 0) ? request.AmountMultiplier.Value : 1000m
            };

            await _db.SasAccounts.AddAsync(account, ct);
            await _db.SaveChangesAsync(ct);

            // تدقيق أمني: من أنشأ أي حساب ساس ولأي مالك — بلا كلمة مرور في السجل.
            _logger.LogWarning(
                "AUDIT إنشاء حساب الساس: actorUserId={Actor} companyId={CompanyId} accountId={AccountId} ownerUserId={Owner} atUtc={AtUtc}",
                currentUserId, companyId, account.Id, account.OwnerUserId, DateTime.UtcNow);

            return Ok(new { success = true, data = ToSasDto(account), message = "تم ربط حساب الساس بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إنشاء حساب الساس");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تعديل label/serverUrl/username/isActive/accountType/amountMultiplier — وإعادة تشفير كلمة المرور فقط
    /// إن أُرسلت جديدة غير فارغة. عزل صارم عبر GetAccessibleSasAccountAsync. (linked_accounts.manage) لا تُعاد كلمة المرور.
    /// </summary>
    [HttpPut("sas/{id}")]
    [RequirePermission("linked_accounts", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> UpdateSas(Guid id, [FromBody] UpdateSasLinkedAccountRequest request, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var currentUserId, out var denied))
            return denied!;

        try
        {
            var account = await GetAccessibleSasAccountAsync(id, companyId, currentUserId, ct);
            if (account == null)
                return NotFound(new { success = false, message = "حساب الساس غير موجود" });

            if (request.Label != null) account.Label = request.Label.Trim();
            if (!string.IsNullOrWhiteSpace(request.ServerUrl))
            {
                // تحقّق أدنى من عنوان خادم الساس عند إرساله غير فارغ (ليس allowlist — خوادم الساس تختلف لكل مزوّد).
                if (!IsValidSasServerUrl(request.ServerUrl))
                    return BadRequest(new { success = false, message = "عنوان خادم الساس غير صالح" });
                account.ServerUrl = request.ServerUrl.Trim();
            }
            if (!string.IsNullOrWhiteSpace(request.Username)) account.Username = request.Username.Trim();
            if (request.AccountType.HasValue) account.AccountType = request.AccountType.Value;
            if (request.IsActive.HasValue) account.IsActive = request.IsActive.Value;
            if (request.AmountMultiplier is > 0) account.AmountMultiplier = request.AmountMultiplier.Value;

            // إعادة التشفير فقط عند إرسال كلمة مرور جديدة غير فارغة (نفس نمط SasAgentController).
            var passwordChanged = !string.IsNullOrEmpty(request.Password);
            if (passwordChanged)
                account.PasswordEncrypted = _secretProtector.Protect(request.Password!);

            account.UpdatedAt = DateTime.UtcNow;
            _db.SasAccounts.Update(account);
            await _db.SaveChangesAsync(ct);

            // تدقيق أمني: من عدّل أي حساب ساس وهل أُعيد تشفير كلمة المرور — بلا كلمة مرور في السجل.
            _logger.LogWarning(
                "AUDIT تعديل حساب الساس: actorUserId={Actor} companyId={CompanyId} accountId={AccountId} ownerUserId={Owner} passwordChanged={PasswordChanged} atUtc={AtUtc}",
                currentUserId, companyId, account.Id, account.OwnerUserId, passwordChanged, DateTime.UtcNow);

            return Ok(new { success = true, data = ToSasDto(account), message = "تم تعديل حساب الساس بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تعديل حساب الساس");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>حذف ناعم لحساب ساس (IsDeleted=true) عبر العزل الصارم. (linked_accounts.manage)</summary>
    [HttpDelete("sas/{id}")]
    [RequirePermission("linked_accounts", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> DeleteSas(Guid id, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var currentUserId, out var denied))
            return denied!;

        try
        {
            var account = await GetAccessibleSasAccountAsync(id, companyId, currentUserId, ct);
            if (account == null)
                return NotFound(new { success = false, message = "حساب الساس غير موجود" });

            account.IsDeleted = true;
            account.DeletedAt = DateTime.UtcNow;
            account.IsActive = false;
            _db.SasAccounts.Update(account);
            await _db.SaveChangesAsync(ct);

            // تدقيق أمني: من حذف أي حساب ساس (حذف ناعم) — بلا كلمة مرور في السجل.
            _logger.LogWarning(
                "AUDIT حذف حساب الساس: actorUserId={Actor} companyId={CompanyId} accountId={AccountId} ownerUserId={Owner} atUtc={AtUtc}",
                currentUserId, companyId, account.Id, account.OwnerUserId, DateTime.UtcNow);

            return Ok(new { success = true, message = "تم حذف حساب الساس بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حذف حساب الساس");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== 7) الدخول الخادمي (إعادة التوكن فقط) ====================

    /// <summary>
    /// دخول خادمي: فكّ التشفير في الذاكرة + تسجيل دخول لنظام FTTH (بترويسات WAF) + تحديث LastLoginAt.
    /// يعيد التوكن فقط (access_token + refresh_token إن توفّر) ولا يعيد كلمة المرور. (linked_accounts.view)
    /// </summary>
    [HttpPost("ftth/{id}/login")]
    // لا نشترط صلاحية linked_accounts: الدخول الخادمي لحساب المستخدم نفسه مسموح (العزل عبر
    // GetAccessibleAccountAsync: حساب الغير يتطلب أدمن شركة). لا يُعاد سرّ، محدود المعدّل، ومُدقّق.
    [EnableRateLimiting("credential-reveal")]
    public async Task<IActionResult> LoginFtth(Guid id, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var currentUserId, out var denied))
            return denied!;

        var account = await GetAccessibleAccountAsync(id, companyId, currentUserId, ct);
        if (account == null)
            return NotFound(new { success = false, message = "حساب FTTH غير موجود" });

        try
        {
            var password = _secretProtector.Unprotect(account.PasswordEncrypted); // في الذاكرة فقط
            var result = await FtthLoginAsync(account.ServerUrl, account.Username, password, ct);

            if (!result.Ok)
                return StatusCode(502, new { success = false, message = result.Error ?? "تعذّر تسجيل الدخول لنظام FTTH" });

            // دخول ناجح: نحدّث LastLoginAt ونعتبر الاعتماد صالحاً.
            account.LastLoginAt = DateTime.UtcNow;
            account.LastVerifiedAt = DateTime.UtcNow;
            account.Status = "Verified";
            account.UpdatedAt = DateTime.UtcNow;
            _db.FtthAccounts.Update(account);
            await _db.SaveChangesAsync(ct);

            // تدقيق أمني: من سجّل دخولاً خادمياً لأي حساب ومتى — بلا كلمة مرور ولا توكن في السجل.
            _logger.LogWarning(
                "AUDIT تسجيل دخول خادمي لحساب FTTH: requestedByUserId={RequestedBy} companyId={CompanyId} accountId={AccountId} ownerUserId={OwnerUserId} atUtc={AtUtc}",
                currentUserId, companyId, account.Id, account.OwnerUserId, DateTime.UtcNow);

            return Ok(new
            {
                success = true,
                data = new { accessToken = result.AccessToken, refreshToken = result.RefreshToken }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تسجيل الدخول لنظام FTTH");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== 8) ترحيل من البيانات القديمة (أدمن) ====================

    /// <summary>
    /// ترحيل idempotent لبيانات الموظفين القديمة إلى كيان FtthAccount — أدمن شركة فأعلى. (linked_accounts.edit + أدمن)
    /// لكل موظّف في نفس الشركة لديه FtthUsername غير فارغ ولا يملك بعد FtthAccount بنفس Username ⇒ ينشئ حساباً
    /// (Label="الحساب الأساسي"، IsPrimary إن لم يكن لديه حساب أساسي بعد، PasswordEncrypted = Protect(FtthPasswordEncrypted)).
    /// لا يحذف/يعدّل الأعمدة القديمة. يعيد عدد المنشأة/المتخطّاة.
    /// </summary>
    [HttpPost("backfill-from-legacy")]
    [RequirePermission("linked_accounts", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> BackfillFromLegacy(CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var currentUserId, out var denied))
            return denied!;
        if (!IsCompanyAdminOrAbove())
            return Forbid();

        try
        {
            // موظفو الشركة ذوو حساب FTTH قديم (العمود القديم) — قراءة فقط للأعمدة القديمة.
            var legacyUsers = await _db.Users
                .AsNoTracking()
                .Where(u => u.CompanyId == companyId
                            && !u.IsDeleted
                            && u.FtthUsername != null
                            && u.FtthUsername != "")
                .Select(u => new { u.Id, u.FtthUsername, u.FtthPasswordEncrypted })
                .ToListAsync(ct);

            int created = 0, skipped = 0;

            foreach (var u in legacyUsers)
            {
                var username = u.FtthUsername!.Trim();

                // idempotency: لا نُكرّر إن وُجد حساب بنفس (الشركة+المالك+اسم المستخدم).
                var exists = await _db.FtthAccounts.AnyAsync(
                    a => a.CompanyId == companyId
                         && a.OwnerUserId == u.Id
                         && a.Username == username
                         && !a.IsDeleted, ct);
                if (exists) { skipped++; continue; }

                // حافظ على ثابت «أساسي واحد»: نجعله أساسياً فقط إن لم يكن للموظّف حساب أساسي بعد.
                var hasPrimary = await _db.FtthAccounts.AnyAsync(
                    a => a.CompanyId == companyId
                         && a.OwnerUserId == u.Id
                         && a.IsPrimary
                         && !a.IsDeleted, ct);

                var account = new FtthAccount
                {
                    Id = Guid.NewGuid(),
                    CompanyId = companyId,
                    OwnerUserId = u.Id,
                    Label = "الحساب الأساسي",
                    Username = username,
                    ServerUrl = DefaultFtthBaseUrl,
                    // القيمة المخزّنة في العمود القديم تُستخدم فعلياً ككلمة مرور صريحة ⇒ نشفّرها كما هي.
                    PasswordEncrypted = _secretProtector.Protect(u.FtthPasswordEncrypted ?? string.Empty),
                    IsActive = true,
                    IsPrimary = !hasPrimary,
                    Status = "Unverified"
                };

                await _db.FtthAccounts.AddAsync(account, ct);
                created++;
            }

            await _db.SaveChangesAsync(ct);

            // تدقيق أمني: من شغّل الترحيل الجماعي ونتيجته — عملية حسّاسة (أدمن) تنشئ حسابات باعتماد.
            _logger.LogWarning(
                "AUDIT ترحيل حسابات FTTH القديمة: operatorUserId={OperatorUserId} companyId={CompanyId} created={Created} skipped={Skipped}",
                currentUserId, companyId, created, skipped);

            return Ok(new
            {
                success = true,
                data = new { created, skipped },
                message = $"تم ترحيل {created} حساباً وتخطّي {skipped}"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في ترحيل حسابات FTTH القديمة");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== مساعدات ====================

    /// <summary>يبني DTO حساب FTTH من الكيان — بلا أي كلمة مرور.</summary>
    private static LinkedAccountDto ToDto(FtthAccount a)
        => new(a.Id, "Ftth", a.Label, a.Username, a.ServerUrl, a.Role,
               a.IsActive, a.IsPrimary, a.Status, a.LastVerifiedAt, a.LastLoginAt, true,
               null, null, a.FtthMemberId);

    /// <summary>يبني DTO حساب ساس موحّد من الكيان — بلا أي كلمة مرور (مطابق لتمثيل الساس في GetLinkedAccounts).</summary>
    private static LinkedAccountDto ToSasDto(SasAccount a)
        => new(a.Id, "Sas", a.Label, a.Username, a.ServerUrl, a.AccountType.ToString(),
               a.IsActive, false, a.SyncStatus, a.LastSyncAt, null, true,
               (int)a.AccountType, a.AmountMultiplier);

    /// <summary>
    /// تسجيل دخول خادمي إلى نظام FTTH (admin.ftth.iq) بنفس ترويسات WAF المطلوبة في CompanyFtthSettingsController.
    /// يعيد (نجاح، access_token، refresh_token، رسالة خطأ). لا يُسجَّل أي سرّ هنا.
    /// </summary>
    private async Task<(bool Ok, string? AccessToken, string? RefreshToken, string? Error)> FtthLoginAsync(
        string serverUrl, string username, string password, CancellationToken ct)
    {
        var baseUrl = string.IsNullOrWhiteSpace(serverUrl) ? DefaultFtthBaseUrl : serverUrl.TrimEnd('/');

        // دفاع بالعمق (إغلاق SSRF): لا نُجري أي نداء شبكة إن لم يمرّ العنوان قائمة السماح.
        if (!IsAllowedFtthServerUrl(baseUrl))
            return (false, null, null, "عنوان خادم FTTH غير مسموح");

        try
        {
            // تعطيل إعادة التوجيه التلقائية لمنع التفاف SSRF عبر 3xx نحو عناوين داخلية.
            using var handler = new HttpClientHandler { AllowAutoRedirect = false };
            using var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(20) };

            // FTTH WAF يتطلب هذه الترويسات — بدونها يرفض الطلب.
            client.DefaultRequestHeaders.Add("Origin", "https://admin.ftth.iq");
            client.DefaultRequestHeaders.Add("Referer", "https://admin.ftth.iq/");
            client.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)");
            client.DefaultRequestHeaders.Add("x-client-app", "53d57a7f-3f89-4e9d-873b-3d071bc6dd9f");
            client.DefaultRequestHeaders.Add("x-user-role", "0");

            var content = new FormUrlEncodedContent(new[]
            {
                new KeyValuePair<string, string>("username", username),
                new KeyValuePair<string, string>("password", password),
                new KeyValuePair<string, string>("grant_type", "password"),
                new KeyValuePair<string, string>("scope", "openid profile"),
            });

            var response = await client.PostAsync($"{baseUrl}/api/auth/Contractor/token", content, ct);
            if (!response.IsSuccessStatusCode)
                return (false, null, null, $"فشل الاتصال بنظام FTTH: {(int)response.StatusCode}");

            var json = await response.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            string? access = root.TryGetProperty("access_token", out var at) && at.ValueKind == JsonValueKind.String
                ? at.GetString() : null;
            string? refresh = root.TryGetProperty("refresh_token", out var rt) && rt.ValueKind == JsonValueKind.String
                ? rt.GetString() : null;

            if (string.IsNullOrEmpty(access))
                return (false, null, null, "لم يُعِد خادم FTTH رمز وصول صالحاً");

            return (true, access, refresh, null);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            // لا نسجّل الاعتماد — رسالة الاستثناء فقط.
            _logger.LogWarning(ex, "تعذّر الاتصال بنظام FTTH أثناء تسجيل الدخول/التحقق");
            return (false, null, null, "تعذّر الاتصال بنظام FTTH");
        }
    }

    /// <summary>
    /// بعد دخول FTTH ناجح: يجلب أعضاء الفريق (/api/teams/members) بالتوكن، ويطابق العضو
    /// الذي اسم مستخدمه = اسم مستخدم الحساب، فيعيد (رقم العضو الرقمي، الدور، الاسم المعروض).
    /// رقم العضو يُقبل **رقمياً بحتاً** فقط (id/memberId/accountId/self.id). لا يرمي استثناءً —
    /// يعيد null عند أي فشل كي لا يُفشل التوثيق. إن طابق الاسم بلا رقم، يسجّل مفاتيح الكائن للتشخيص.
    /// </summary>
    private async Task<(string? MemberId, string? Role, string? DisplayName)> FetchFtthMemberInfoAsync(
        string serverUrl, string accessToken, string username, CancellationToken ct)
    {
        var baseUrl = string.IsNullOrWhiteSpace(serverUrl) ? DefaultFtthBaseUrl : serverUrl.TrimEnd('/');
        if (!IsAllowedFtthServerUrl(baseUrl)) return (null, null, null); // دفاع SSRF
        try
        {
            using var handler = new HttpClientHandler { AllowAutoRedirect = false };
            using var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(20) };
            client.DefaultRequestHeaders.Add("Origin", "https://admin.ftth.iq");
            client.DefaultRequestHeaders.Add("Referer", "https://admin.ftth.iq/");
            client.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)");
            client.DefaultRequestHeaders.Authorization =
                new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", accessToken);

            var response = await client.GetAsync($"{baseUrl}/api/teams/members", ct);
            if (!response.IsSuccessStatusCode) return (null, null, null);

            var json = await response.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(json);
            if (!doc.RootElement.TryGetProperty("items", out var items) || items.ValueKind != JsonValueKind.Array)
                return (null, null, null);

            var want = username.Trim().ToLowerInvariant();
            int memberCount = 0;
            JsonElement? matched = null;
            foreach (var m in items.EnumerateArray())
            {
                if (m.ValueKind != JsonValueKind.Object) continue;
                memberCount++;
                var u = GetJsonString(m, "username");
                if (u?.Trim().ToLowerInvariant() == want) matched = m;
            }
            // المعرّف = حقل id العضو في /api/teams/members (فريد لكل عامل، عادةً GUID).
            // ليس AccountId في JWT (ذاك معرّف الشريك المشترك بين كل عمّال الحساب).
            string? memberId = null;
            string? role = null;
            string? display = null;
            if (matched != null)
            {
                var mm = matched.Value;
                memberId = GetJsonString(mm, "id");
                if (memberId == null && mm.TryGetProperty("id", out var idEl) && idEl.ValueKind == JsonValueKind.Number)
                    memberId = idEl.GetRawText();
                if (mm.TryGetProperty("role", out var r) && r.ValueKind == JsonValueKind.Object)
                    role = GetJsonString(r, "displayValue");
                var nm = $"{GetJsonString(mm, "firstName") ?? ""} {GetJsonString(mm, "lastName") ?? ""}".Trim();
                display = string.IsNullOrEmpty(nm) ? null : nm;
            }

            _logger.LogInformation("توثيق FTTH: الحساب={Want} عدد الأعضاء={Count} معرّف_العضو={Id}",
                want, memberCount, memberId ?? "(null)");
            return (memberId, role, display);
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "تعذّر جلب أعضاء فريق FTTH أثناء التوثيق");
            return (null, null, null);
        }
    }

    /// <summary>يقرأ خاصية نصّية من كائن JSON (أو null).</summary>
    private static string? GetJsonString(JsonElement obj, string name)
        => obj.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
}

// ============ DTOs (لا تحوي أي كلمة مرور) ============

/// <summary>عنصر موحّد في قائمة حسابات الموظّف (FTTH/Sas) — بلا أي سرّ. hasSecret يدل على وجود كلمة مرور محفوظة.</summary>
public record LinkedAccountDto(
    Guid Id,
    string Provider,
    string Label,
    string Username,
    string? ServerUrl,
    string? Role,
    bool IsActive,
    bool IsPrimary,
    string? Status,
    DateTime? LastVerifiedAt,
    DateTime? LastLoginAt,
    bool HasSecret,
    int? AccountType = null,
    decimal? AmountMultiplier = null,
    string? FtthMemberId = null);

/// <summary>طلب إنشاء حساب FTTH لموظّف. كلمة المرور تُشفَّر فور الاستقبال ولا تُعاد.</summary>
public record CreateFtthAccountRequest(
    Guid OwnerUserId,
    string Label,
    string Username,
    string Password,
    string? ServerUrl = null,
    string? Role = null,
    bool? IsPrimary = null,
    string? FtthMemberId = null);

/// <summary>طلب تعديل حساب FTTH. كلمة المرور اختيارية: تُعاد كتابتها فقط عند إرسال قيمة غير فارغة.</summary>
public record UpdateFtthAccountRequest(
    string? Label = null,
    string? Username = null,
    string? Password = null,
    bool? IsActive = null,
    bool? IsPrimary = null,
    string? ServerUrl = null,
    string? FtthMemberId = null);

/// <summary>طلب إنشاء حساب ساس لموظّف. كلمة المرور تُشفَّر فور الاستقبال ولا تُعاد.</summary>
public record CreateSasLinkedAccountRequest(
    Guid OwnerUserId,
    string Label,
    string ServerUrl,
    string Username,
    string Password,
    SasAccountType? AccountType = null,
    decimal? AmountMultiplier = null,
    bool? IsActive = null);

/// <summary>طلب تعديل حساب ساس — كل الحقول اختيارية؛ Password فقط عند التغيير.</summary>
public record UpdateSasLinkedAccountRequest(
    string? Label = null,
    string? ServerUrl = null,
    string? Username = null,
    string? Password = null,
    SasAccountType? AccountType = null,
    decimal? AmountMultiplier = null,
    bool? IsActive = null);
