using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.API.Authorization;
using Sadara.API.Constants;
using Sadara.Application.Interfaces;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;
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
    private readonly IUnitOfWork _unitOfWork;
    private readonly Sadara.API.Services.ISubscriptionAccountingService _accounting;

    public SasAgentController(
        SadaraDbContext db,
        ICurrentTenant tenant,
        ISecretProtector secretProtector,
        ISasServiceClient sasClient,
        ILogger<SasAgentController> logger,
        IUnitOfWork unitOfWork,
        Sadara.API.Services.ISubscriptionAccountingService accounting)
    {
        _db = db;
        _tenant = tenant;
        _secretProtector = secretProtector;
        _sasClient = sasClient;
        _logger = logger;
        _unitOfWork = unitOfWork;
        _accounting = accounting;
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
                    x.LastSyncAt,
                    x.AmountMultiplier))
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
                IsActive = request.IsActive ?? true,
                // مُضاعِف القيم المالية (افتراضي 1000 لمزوّدي SAS4 الذين يُرجعون بالآلاف).
                AmountMultiplier = (request.AmountMultiplier is > 0) ? request.AmountMultiplier.Value : 1000m
            };

            await _db.SasAccounts.AddAsync(account, ct);
            await _db.SaveChangesAsync(ct);

            // نعيد DTO بلا كلمة مرور.
            var dto = new SasAccountDto(
                account.Id, account.Label, account.ServerUrl, account.Username,
                account.AccountType, account.IsActive, account.LastSyncAt, account.AmountMultiplier);

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
            if (request.AmountMultiplier is > 0) account.AmountMultiplier = request.AmountMultiplier.Value;

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

    // ==================== إدارة الوكلاء (للأدمن — company-scoped، role-gated) ====================
    // على عكس بقية النقاط (owner-scoped)، هذه النقطة تخصّ أدمن الشركة: يرى كل وكلاء شركته.
    // العزل هنا: شركة (CompanyId من التوكن) + دور (CompanyAdmin فأعلى) — لا فلترة بالمالك.
    //  - TryResolveScope للحصول على CompanyId (يرفض بلا شركة، ويرفض SuperAdmin/سياق النظام لأنها company-scoped).
    //  - + فحص الدور: يجب أن يكون CompanyAdmin (role_id ≥ 20) فأعلى؛ غير الأدمن => Forbid.
    // لا يُعاد أي سرّ (لا PasswordEncrypted). الصلاحية manage + failClosed:true.

    /// <summary>
    /// يقرأ الدور من التوكن (role_id أو ClaimTypes.Role) ويتحقّق أنّه CompanyAdmin فأعلى.
    /// القيمة قد تكون رقم الدور (CompanyAdmin=20, SuperAdmin=99) أو اسمه ("CompanyAdmin"/"SuperAdmin").
    /// ملاحظة: SuperAdmin بلا شركة يُرفض في <see cref="TryResolveScope"/> لأنّ النقطة company-scoped.
    /// </summary>
    private bool IsCompanyAdminOrAbove()
    {
        var roleClaim = User.FindFirst("role_id")?.Value
                     ?? User.FindFirst(System.Security.Claims.ClaimTypes.Role)?.Value
                     ?? User.FindFirst("role")?.Value;

        if (string.IsNullOrWhiteSpace(roleClaim))
            return false;

        // رقم الدور: CompanyAdmin=20 فأعلى.
        if (int.TryParse(roleClaim, out var roleInt))
            return roleInt >= (int)UserRole.CompanyAdmin;

        // اسم الدور.
        return string.Equals(roleClaim, nameof(UserRole.CompanyAdmin), StringComparison.OrdinalIgnoreCase)
            || string.Equals(roleClaim, nameof(UserRole.SuperAdmin), StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// إدارة الوكلاء (للأدمن) — قائمة كل وكلاء الشركة مع حساباتهم ومقاطعتهم — قراءة (manage, failClosed).
    ///
    /// العزل + الصلاحية:
    ///  - TryResolveScope: يرفض بلا شركة (SuperAdmin/سياق النظام => Forbid) — النقطة company-scoped.
    ///  - IsCompanyAdminOrAbove: يجب أن يكون CompanyAdmin فأعلى، وإلا Forbid.
    ///
    /// التجميع:
    ///  1) كل <c>SasAccount</c> حيث <c>CompanyId == tenant.CompanyId &amp;&amp; !IsDeleted</c> (كل الشركة، لا owner فقط).
    ///  2) أسماء الملّاك من جدول <c>Users</c> (Id → FullName/Username) لمعرّفات الملّاك المميّزة فقط.
    ///  3) <c>GetAgentsSummaryAsync(companyId, accountIds)</c> لكل معرّفات الحسابات (المقاطعة/الحكم).
    ///  4) دمج: قائمة لكل وكيل = {userId, fullName, username, accounts:[...], totals:{...}} — بلا أي سرّ.
    /// </summary>
    [HttpGet("admin/agents")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> GetAdminAgents(CancellationToken ct)
    {
        // 1) النطاق: شركة صالحة (يرفض SuperAdmin/بلا شركة).
        if (!TryResolveScope(out var companyId, out _, out var denied))
            return denied!;

        // 2) الدور: CompanyAdmin فأعلى فقط.
        if (!IsCompanyAdminOrAbove())
            return Forbid();

        try
        {
            // 3) كل حسابات ساس ضمن الشركة (لا فلترة بالمالك) — بلا كلمات مرور.
            var accounts = await _db.SasAccounts
                .Where(x => x.CompanyId == companyId && !x.IsDeleted)
                .OrderBy(x => x.Label)
                .Select(x => new
                {
                    x.Id,
                    x.OwnerUserId,
                    x.Label,
                    x.ServerUrl,
                    x.IsActive,
                    x.LastSyncAt
                })
                .ToListAsync(ct);

            if (accounts.Count == 0)
                return Ok(new { success = true, data = Array.Empty<SasAgentAdminAgentDto>(), total = 0 });

            // 4) أسماء الملّاك من جدول Users (معرّفات مميّزة فقط) ضمن الشركة نفسها (دفاع بالعمق).
            var ownerIds = accounts.Select(a => a.OwnerUserId).Distinct().ToList();
            var owners = await _db.Users
                .Where(u => ownerIds.Contains(u.Id))
                .Select(u => new { u.Id, u.FullName, u.Username })
                .ToDictionaryAsync(u => u.Id, ct);

            // 5) المقاطعة/الحكم لكل الحسابات دفعةً واحدة عبر خدمة Python.
            var accountIds = accounts.Select(a => a.Id.ToString()).ToList();
            var reconByAccount = new Dictionary<string, SasAgentAdminReconciliationDto>(StringComparer.Ordinal);
            try
            {
                var raw = await _sasClient.GetAgentsSummaryAsync(companyId.ToString(), accountIds, ct);
                reconByAccount = ParseAgentsSummary(raw);
            }
            catch (SasServiceUnavailableException ex)
            {
                // تدهور رشيق: نُكمل بلا مقاطعة (reconciliation=null) بدل إسقاط الصفحة كلها.
                _logger.LogWarning(ex, "خدمة الساس غير متاحة أثناء جلب ملخّص مقاطعة الوكلاء — يُعرَض بلا مقاطعة");
            }

            // 6) الدمج: تجميع الحسابات حسب المالك ثم بناء DTO لكل وكيل.
            var agents = accounts
                .GroupBy(a => a.OwnerUserId)
                .Select(g =>
                {
                    owners.TryGetValue(g.Key, out var owner);

                    var accountDtos = g.Select(a =>
                    {
                        reconByAccount.TryGetValue(a.Id.ToString(), out var recon);
                        return new SasAgentAdminAccountDto(
                            a.Id,
                            a.Label,
                            a.ServerUrl,
                            a.IsActive,
                            recon);
                    }).ToList();

                    var declaredTotal = accountDtos.Sum(a => a.Reconciliation?.DeclaredTotal ?? 0);
                    var actualTotal = accountDtos.Sum(a => a.Reconciliation?.ActualTotal ?? 0);

                    return new SasAgentAdminAgentDto(
                        g.Key,
                        owner?.FullName ?? string.Empty,
                        owner?.Username,
                        accountDtos,
                        new SasAgentAdminTotalsDto(accountDtos.Count, declaredTotal, actualTotal));
                })
                .OrderBy(a => a.FullName)
                .ToList();

            return Ok(new { success = true, data = agents, total = agents.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب إدارة الوكلاء للأدمن");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// يحلّل JSON ملخّص المقاطعة من خدمة Python (<c>{items:[{account_id, ...}]}</c>) إلى قاموس بـ account_id.
    /// أي عنصر بلا account_id أو غير صالح يُتجاهَل بأمان (لا يُسقط الباقي).
    /// </summary>
    private static Dictionary<string, SasAgentAdminReconciliationDto> ParseAgentsSummary(string raw)
    {
        var map = new Dictionary<string, SasAgentAdminReconciliationDto>(StringComparer.Ordinal);
        if (string.IsNullOrWhiteSpace(raw))
            return map;

        using var doc = System.Text.Json.JsonDocument.Parse(raw);
        if (doc.RootElement.ValueKind != System.Text.Json.JsonValueKind.Object
            || !doc.RootElement.TryGetProperty("items", out var items)
            || items.ValueKind != System.Text.Json.JsonValueKind.Array)
            return map;

        foreach (var item in items.EnumerateArray())
        {
            if (item.ValueKind != System.Text.Json.JsonValueKind.Object)
                continue;

            var accountId = GetStringProp(item, "account_id");
            if (string.IsNullOrWhiteSpace(accountId))
                continue;

            map[accountId] = new SasAgentAdminReconciliationDto(
                GetIntProp(item, "declared_total"),
                GetIntProp(item, "declared_active"),
                GetIntProp(item, "actual_total"),
                GetIntProp(item, "actual_active"),
                GetIntProp(item, "diff"),
                GetStringProp(item, "verdict"),
                GetStringProp(item, "last_sync"));
        }

        return map;
    }

    /// <summary>يقرأ خاصيّة نصّية بأمان من عنصر JSON (يقبل string، ويحوّل الرقم/المنطقي لنصّ)؛ null إن غابت.</summary>
    private static string? GetStringProp(System.Text.Json.JsonElement obj, string name)
    {
        if (!obj.TryGetProperty(name, out var el))
            return null;
        return el.ValueKind switch
        {
            System.Text.Json.JsonValueKind.String => el.GetString(),
            System.Text.Json.JsonValueKind.Number => el.GetRawText(),
            System.Text.Json.JsonValueKind.True => "true",
            System.Text.Json.JsonValueKind.False => "false",
            _ => null
        };
    }

    /// <summary>يقرأ خاصيّة عددية صحيحة بأمان (يقبل الرقم أو نصّاً رقمياً)؛ 0 إن غابت/غير صالحة.</summary>
    private static int GetIntProp(System.Text.Json.JsonElement obj, string name)
    {
        if (!obj.TryGetProperty(name, out var el))
            return 0;
        if (el.ValueKind == System.Text.Json.JsonValueKind.Number && el.TryGetInt32(out var n))
            return n;
        if (el.ValueKind == System.Text.Json.JsonValueKind.String
            && int.TryParse(el.GetString(), out var s))
            return s;
        return 0;
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

    /// <summary>جلب باقات/بروفايلات الساس المتاحة (تبويب الباقات) — قراءة (view).</summary>
    [HttpGet("accounts/{id}/packages")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetPackages(Guid id, CancellationToken ct)
        => PassThroughAsync(id, (acc, pwd, token) =>
            _sasClient.GetPackagesAsync(acc.ServerUrl, acc.Username, pwd, token), null, ct);

    /// <summary>
    /// جلب موظفي شركة الحساب الصالحين للتوجيه (نوع التحصيل «فني») — قراءة (view).
    ///
    /// العزل: <see cref="GetOwnedAccountAsync"/> (الحساب مملوك: شركة + مالك + غير محذوف) ثم
    /// فلترة الموظفين بشركة الحساب نفسها (<c>account.CompanyId</c>) حصراً — لا بشركة التوكن مباشرةً
    /// (دفاع بالعمق: القائمة مربوطة بالحساب المملوك لا بالسياق). يُعاد الموظفون النشطون غير المحذوفين
    /// من غير المواطنين فقط. استُرشد بمنطق <c>GET /api/service-requests/task-staff</c> لكن معزولاً بشركة الحساب.
    ///
    /// الرد: <c>{ success, data:[{ id, name, phone }] }</c> مرتّب بالاسم. بلا أسرار.
    /// </summary>
    [HttpGet("accounts/{id}/technicians")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> GetTechnicians(Guid id, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied))
            return denied!;

        var account = await GetOwnedAccountAsync(id, companyId, userId, ct);
        if (account == null)
            return NotFound(new { success = false, message = "حساب الساس غير موجود" });

        try
        {
            // موظفو شركة الحساب (العزل من الحساب المملوك) النشطون غير المحذوفين — بلا مواطنين.
            var list = await _db.Users
                .AsNoTracking()
                .Where(u => u.CompanyId == account.CompanyId
                            && u.IsActive
                            && !u.IsDeleted
                            && u.Role != UserRole.Citizen)
                .OrderBy(u => u.FullName)
                .Select(u => new
                {
                    id = u.Id,
                    name = u.FullName,
                    phone = u.PhoneNumber
                })
                .ToListAsync(ct);

            return Ok(new { success = true, data = list });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب موظفي التوجيه لحساب الساس");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== تسعير الباقات (المرحلة 1 — نظام الأرباح) ====================
    // معزولة بالعزل الثلاثي عبر GetOwnedAccountAsync (شركة + مالك + غير محذوف).
    // CompanyId/SasAccountId مختومة من الحساب المملوك خادمياً — لا من العميل. بلا أسرار في الردود.

    /// <summary>
    /// قائمة أسعار باقات الحساب (كلفة/سعر بيع/ربح) — قراءة (view).
    ///
    /// التدفّق:
    ///  1) <see cref="GetOwnedAccountAsync"/> للعزل الثلاثي.
    ///  2) جلب باقات SAS4 عبر <c>GetPackagesAsync</c> (يُفكّ التشفير في الذاكرة فقط) ودمجها مع صفوف
    ///     <c>SasPackagePrice</c> المخزّنة (CompanyId + SasAccountId): باقة غير مسعّرة ⇒ كلفة/سعر/ربح = 0.
    ///  3) تدهور رشيق: إن تعذّرت SAS4 تُعاد الصفوف المخزّنة فقط.
    /// الربح = <c>SellingPrice − Cost</c> (محسوب). بلا أسرار.
    /// </summary>
    [HttpGet("accounts/{id}/package-prices")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> GetPackagePrices(Guid id, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied))
            return denied!;

        var account = await GetOwnedAccountAsync(id, companyId, userId, ct);
        if (account == null)
            return NotFound(new { success = false, message = "حساب الساس غير موجود" });

        try
        {
            // 1) الصفوف المخزّنة لهذا الحساب ضمن الشركة (المصدر الموثوق للتسعير).
            var stored = await _db.SasPackagePrices
                .Where(x => x.CompanyId == account.CompanyId
                            && x.SasAccountId == account.Id
                            && !x.IsDeleted)
                .ToListAsync(ct);

            var storedByProfile = stored
                .GroupBy(x => x.ProfileId, StringComparer.Ordinal)
                .ToDictionary(g => g.Key, g => g.First(), StringComparer.Ordinal);

            // 2) محاولة دمج باقات SAS4 (تدهور رشيق عند تعذّرها).
            var sasProfiles = new List<(string ProfileId, string ProfileName)>();
            try
            {
                var password = _secretProtector.Unprotect(account.PasswordEncrypted); // في الذاكرة فقط
                var raw = await _sasClient.GetPackagesAsync(account.ServerUrl, account.Username, password, ct);
                sasProfiles = ParseSasProfiles(raw);
            }
            catch (SasServiceUnavailableException ex)
            {
                _logger.LogWarning(ex, "خدمة الساس غير متاحة أثناء جلب باقات التسعير — تُعاد الصفوف المخزّنة فقط");
            }

            // 3) الدمج: اتحاد باقات SAS4 والمخزّنة بمفتاح ProfileId (بلا تكرار).
            var merged = new List<SasPricingPackageDto>();
            var seen = new HashSet<string>(StringComparer.Ordinal);

            foreach (var p in sasProfiles)
            {
                if (string.IsNullOrWhiteSpace(p.ProfileId) || !seen.Add(p.ProfileId))
                    continue;

                storedByProfile.TryGetValue(p.ProfileId, out var row);
                var name = !string.IsNullOrWhiteSpace(row?.ProfileName) ? row!.ProfileName : p.ProfileName;
                merged.Add(BuildPricingDto(p.ProfileId, name ?? string.Empty, row));
            }

            // صفوف مخزّنة لباقات لم تعُدها SAS4 (أو تعذّرت الخدمة) — تُدرَج أيضاً.
            foreach (var row in stored)
            {
                if (!seen.Add(row.ProfileId))
                    continue;
                merged.Add(BuildPricingDto(row.ProfileId, row.ProfileName, row));
            }

            var data = merged.OrderBy(x => x.ProfileName, StringComparer.OrdinalIgnoreCase).ToList();
            return Ok(new { success = true, data, total = data.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب أسعار باقات الساس");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// حفظ أسعار باقات الحساب (upsert) — كتابة (manage). CompanyId/SasAccountId مختومة من الحساب خادمياً.
    /// الجسم: <c>{items:[{profileId, profileName, cost, sellingPrice, isActive}]}</c>. يعيد عدد الصفوف المحدَّثة/المضافة.
    /// </summary>
    [HttpPut("accounts/{id}/package-prices")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> UpsertPackagePrices(
        Guid id,
        [FromBody] SasPricingUpsertRequest request,
        CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied))
            return denied!;

        if (request?.Items == null || request.Items.Count == 0)
            return BadRequest(new { success = false, message = "قائمة الأسعار مطلوبة" });

        var account = await GetOwnedAccountAsync(id, companyId, userId, ct);
        if (account == null)
            return NotFound(new { success = false, message = "حساب الساس غير موجود" });

        try
        {
            // الصفوف القائمة لهذا الحساب (للـ upsert عبر ProfileId).
            var existing = await _db.SasPackagePrices
                .Where(x => x.CompanyId == account.CompanyId
                            && x.SasAccountId == account.Id
                            && !x.IsDeleted)
                .ToListAsync(ct);

            var byProfile = existing
                .GroupBy(x => x.ProfileId, StringComparer.Ordinal)
                .ToDictionary(g => g.Key, g => g.First(), StringComparer.Ordinal);

            var affected = 0;
            var now = DateTime.UtcNow;

            foreach (var item in request.Items)
            {
                var profileId = item.ProfileId?.Trim();
                if (string.IsNullOrWhiteSpace(profileId))
                    continue; // تجاهل العناصر بلا معرّف باقة

                var cost = Math.Max(0, item.Cost);
                var selling = Math.Max(0, item.SellingPrice);
                var profileName = item.ProfileName?.Trim() ?? string.Empty;
                var isActive = item.IsActive ?? true;

                if (byProfile.TryGetValue(profileId, out var row))
                {
                    row.ProfileName = profileName;
                    row.Cost = cost;
                    row.SellingPrice = selling;
                    row.IsActive = isActive;
                    row.UpdatedAt = now;
                    _db.SasPackagePrices.Update(row);
                }
                else
                {
                    var created = new SasPackagePrice
                    {
                        Id = Guid.NewGuid(),
                        CompanyId = account.CompanyId,   // ختم العزل من الحساب المملوك
                        SasAccountId = account.Id,       // ختم العزل من الحساب المملوك
                        ProfileId = profileId,
                        ProfileName = profileName,
                        Cost = cost,
                        SellingPrice = selling,
                        IsActive = isActive
                    };
                    await _db.SasPackagePrices.AddAsync(created, ct);
                    byProfile[profileId] = created; // منع إضافة مكرّرة إن تكرّر المعرّف في الطلب
                }

                affected++;
            }

            await _db.SaveChangesAsync(ct);
            return Ok(new { success = true, count = affected, message = "تم حفظ الأسعار بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حفظ أسعار باقات الساس");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== مستكشف الساس (أداة مسؤول/مطوّر) ====================
    // فكّ تشفير حمولات SAS4 الملتقَطة من اللوحة لاكتشاف عقد الـAPI الحقيقي. محصور بالمسؤول (CompanyAdmin فأعلى).
    // فكّ محلي بالمفتاح الثابت (بلا اعتماد/نداء SAS). لا يُسجَّل المحتوى.

    /// <summary>فكّ دفعة حمولات ساس مشفّرة (مستكشف الساس) — كتابة (manage) + مسؤول فقط.</summary>
    [HttpPost("explorer/decrypt")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> ExplorerDecrypt([FromBody] SasExplorerDecryptRequest request, CancellationToken ct)
    {
        if (!TryResolveScope(out _, out _, out var denied))
            return denied!;
        if (!IsCompanyAdminOrAbove())
            return Forbid();

        if (request?.Items == null || request.Items.Count == 0)
            return Ok(new { success = true, results = Array.Empty<object>(), count = 0 });

        // سقف معقول للدفعة (حماية).
        var items = request.Items.Take(2000).ToList();

        try
        {
            var raw = await _sasClient.DecryptPayloadsAsync(items, ct);
            // نُعيد JSON خدمة Python كما هو (results[]) ضمن غلاف success.
            return Content(
                $"{{\"success\":true,\"data\":{raw}}}",
                "application/json");
        }
        catch (SasServiceUnavailableException ex)
        {
            _logger.LogWarning(ex, "تعذّر فكّ تشفير حمولات المستكشف");
            return StatusCode(503, new { success = false, message = "خدمة الساس غير متاحة" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في فكّ تشفير حمولات المستكشف");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== المناطق (SasRegion) — بيانات رئيسية على مستوى الشركة ====================
    // معزولة بالشركة (CompanyId من التوكن). أجور الصيانة لكل منطقة تُطبَّق تلقائياً على مشتركيها عند التفعيل/التجديد.
    // ملاحظة: المناطق على مستوى الشركة لا الحساب (يشترك بها كل حسابات موظفي الشركة) — بلا ربط SasAccountId.

    /// <summary>قائمة مناطق الشركة مع عدد المشتركين المرتبطين بكل منطقة — قراءة (view).</summary>
    [HttpGet("regions")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> GetRegions(CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out _, out var denied))
            return denied!;

        try
        {
            var regions = await _db.SasRegions
                .AsNoTracking()
                .Where(x => x.CompanyId == companyId && !x.IsDeleted)
                .OrderBy(x => x.Name)
                .ToListAsync(ct);

            // عدّ المشتركين المرتبطين لكل منطقة (ضمن الشركة) في استعلام واحد.
            var counts = await _db.SasSubscriberProfiles
                .AsNoTracking()
                .Where(p => p.CompanyId == companyId && p.RegionId != null && !p.IsDeleted)
                .GroupBy(p => p.RegionId!.Value)
                .Select(g => new { RegionId = g.Key, Count = g.Count() })
                .ToDictionaryAsync(x => x.RegionId, x => x.Count, ct);

            var data = regions.Select(r => new SasRegionDto(
                r.Id, r.Name, r.Code, r.Governorate, r.City,
                r.MaintenanceFee, r.IsActive, r.Notes,
                counts.TryGetValue(r.Id, out var c) ? c : 0)).ToList();

            return Ok(new { success = true, data, total = data.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب مناطق الساس");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>إنشاء منطقة جديدة للشركة — كتابة (manage). CompanyId مختوم خادمياً. الاسم فريد ضمن الشركة.</summary>
    [HttpPost("regions")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> CreateRegion([FromBody] SasRegionUpsertRequest request, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out _, out var denied))
            return denied!;

        var name = Trim(request?.Name);
        if (name == null)
            return BadRequest(new { success = false, message = "اسم المنطقة مطلوب" });

        try
        {
            // تفرّد الاسم ضمن الشركة (دفاع فوق الفهرس الفريد).
            var exists = await _db.SasRegions.AnyAsync(
                x => x.CompanyId == companyId && x.Name == name && !x.IsDeleted, ct);
            if (exists)
                return Conflict(new { success = false, message = "اسم المنطقة مستخدم مسبقاً" });

            var region = new SasRegion
            {
                Id = Guid.NewGuid(),
                CompanyId = companyId,                        // ختم العزل من التوكن
                Name = name,
                Code = Trim(request!.Code),
                Governorate = Trim(request.Governorate),
                City = Trim(request.City),
                MaintenanceFee = Math.Max(0, request.MaintenanceFee),
                IsActive = request.IsActive ?? true,
                Notes = Trim(request.Notes)
            };
            await _db.SasRegions.AddAsync(region, ct);
            await _db.SaveChangesAsync(ct);

            return Ok(new { success = true, data = ToRegionDto(region, 0), message = "تم إنشاء المنطقة بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إنشاء منطقة الساس");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>تعديل منطقة — كتابة (manage). العزل: المنطقة ضمن شركة التوكن حصراً.</summary>
    [HttpPut("regions/{rid}")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> UpdateRegion(Guid rid, [FromBody] SasRegionUpsertRequest request, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out _, out var denied))
            return denied!;

        var name = Trim(request?.Name);
        if (name == null)
            return BadRequest(new { success = false, message = "اسم المنطقة مطلوب" });

        try
        {
            var region = await _db.SasRegions.FirstOrDefaultAsync(
                x => x.Id == rid && x.CompanyId == companyId && !x.IsDeleted, ct);
            if (region == null)
                return NotFound(new { success = false, message = "المنطقة غير موجودة" });

            // تفرّد الاسم ضمن الشركة (باستثناء الصفّ نفسه).
            var clash = await _db.SasRegions.AnyAsync(
                x => x.CompanyId == companyId && x.Name == name && x.Id != rid && !x.IsDeleted, ct);
            if (clash)
                return Conflict(new { success = false, message = "اسم المنطقة مستخدم مسبقاً" });

            region.Name = name;
            region.Code = Trim(request!.Code);
            region.Governorate = Trim(request.Governorate);
            region.City = Trim(request.City);
            region.MaintenanceFee = Math.Max(0, request.MaintenanceFee);
            region.IsActive = request.IsActive ?? region.IsActive;
            region.Notes = Trim(request.Notes);
            region.UpdatedAt = DateTime.UtcNow;
            _db.SasRegions.Update(region);
            await _db.SaveChangesAsync(ct);

            var count = await _db.SasSubscriberProfiles.CountAsync(
                p => p.CompanyId == companyId && p.RegionId == rid && !p.IsDeleted, ct);
            return Ok(new { success = true, data = ToRegionDto(region, count), message = "تم تحديث المنطقة بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تعديل منطقة الساس");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>حذف منطقة (ناعم) — كتابة (manage). يُرفَض إن كانت مرتبطة بمشتركين (لتفادي يُتم الربط).</summary>
    [HttpDelete("regions/{rid}")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> DeleteRegion(Guid rid, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out _, out var denied))
            return denied!;

        try
        {
            var region = await _db.SasRegions.FirstOrDefaultAsync(
                x => x.Id == rid && x.CompanyId == companyId && !x.IsDeleted, ct);
            if (region == null)
                return NotFound(new { success = false, message = "المنطقة غير موجودة" });

            var linked = await _db.SasSubscriberProfiles.CountAsync(
                p => p.CompanyId == companyId && p.RegionId == rid && !p.IsDeleted, ct);
            if (linked > 0)
                return Conflict(new { success = false, message = $"لا يمكن حذف المنطقة: مرتبطة بـ{linked} مشترك — أعِد ربطهم أولاً" });

            region.IsDeleted = true;
            region.DeletedAt = DateTime.UtcNow;
            _db.SasRegions.Update(region);
            await _db.SaveChangesAsync(ct);
            return Ok(new { success = true, message = "تم حذف المنطقة" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حذف منطقة الساس");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>يبني DTO منطقة من الكيان مع عدد المشتركين.</summary>
    private static SasRegionDto ToRegionDto(SasRegion r, int subscribersCount)
        => new(r.Id, r.Name, r.Code, r.Governorate, r.City, r.MaintenanceFee, r.IsActive, r.Notes, subscribersCount);

    /// <summary>اسم منطقة ضمن الشركة (عرضي) أو null. يستخدم في بناء بروفايل المشترك.</summary>
    private async Task<string?> ResolveRegionNameAsync(Guid companyId, Guid? regionId, CancellationToken ct)
    {
        if (!regionId.HasValue || regionId.Value == Guid.Empty)
            return null;
        return await _db.SasRegions
            .AsNoTracking()
            .Where(r => r.Id == regionId.Value && r.CompanyId == companyId && !r.IsDeleted)
            .Select(r => r.Name)
            .FirstOrDefaultAsync(ct);
    }

    /// <summary>
    /// أجور صيانة المنطقة المرتبطة بمشترك ساس (افتراضي تلقائي) — 0 إن لا منطقة/غير مفعّلة.
    /// المفتاح: (CompanyId + account.Id + uid) → RegionId → SasRegion.MaintenanceFee.
    /// </summary>
    private async Task<decimal> ResolveRegionMaintenanceFeeAsync(SasAccount account, string uid, CancellationToken ct)
    {
        var regionId = await _db.SasSubscriberProfiles
            .AsNoTracking()
            .Where(p => p.CompanyId == account.CompanyId
                        && p.SasAccountId == account.Id
                        && p.SubscriberUid == uid
                        && !p.IsDeleted)
            .Select(p => p.RegionId)
            .FirstOrDefaultAsync(ct);

        if (!regionId.HasValue || regionId.Value == Guid.Empty)
            return 0m;

        var fee = await _db.SasRegions
            .AsNoTracking()
            .Where(r => r.Id == regionId.Value
                        && r.CompanyId == account.CompanyId
                        && r.IsActive
                        && !r.IsDeleted)
            .Select(r => (decimal?)r.MaintenanceFee)
            .FirstOrDefaultAsync(ct);

        return Math.Max(0m, fee ?? 0m);
    }

    // ==================== تقرير الأرباح (SAS) — تجميع من الدفتر الموحّد ====================
    // معزول بالشركة (CompanyId من التوكن). يجمع سجلات الساس (Source=Sas) ضمن فترة، ويُفصّل حسب المنطقة والباقة.
    // المعادلات: الكلفة = Σ BasePrice؛ الربح = Σ(MaintenanceFee − ManualDiscount)؛ المحصّل = Σ(BasePrice + MaintenanceFee − ManualDiscount).
    // ملاحظة: MaintenanceFee يضمّ ربح الباقة (بيع−كلفة) + أجور صيانة المنطقة ⇒ كلاهما هامش للشركة.

    /// <summary>تقرير أرباح الساس للشركة ضمن فترة — إجمالي + تفصيل حسب المنطقة والباقة — قراءة (view).</summary>
    [HttpGet("reports/profits")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> GetProfitsReport(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out _, out var denied))
            return denied!;

        try
        {
            // 1) سجلات الساس للشركة ضمن الفترة (على ActivationDate؛ fallback لتاريخ الإنشاء إن غابت).
            var query = _unitOfWork.SubscriptionLogs.AsQueryable()
                .Where(l => l.CompanyId == companyId
                            && l.Source == SubscriptionLogSource.Sas);

            if (from.HasValue)
            {
                var f = DateTime.SpecifyKind(from.Value, DateTimeKind.Utc);
                query = query.Where(l => (l.ActivationDate ?? l.CreatedAt) >= f);
            }
            if (to.HasValue)
            {
                var t = DateTime.SpecifyKind(to.Value, DateTimeKind.Utc);
                query = query.Where(l => (l.ActivationDate ?? l.CreatedAt) <= t);
            }

            var logs = await query
                .Select(l => new
                {
                    l.SasAccountId,
                    l.SubscriberUid,
                    l.PlanName,
                    BasePrice = l.BasePrice ?? 0m,
                    MaintenanceFee = l.MaintenanceFee ?? 0m,
                    ManualDiscount = l.ManualDiscount ?? 0m
                })
                .ToListAsync(ct);

            // 2) خريطة (SasAccountId:uid) → RegionId للشركة، وخريطة RegionId → اسم المنطقة.
            var profiles = await _db.SasSubscriberProfiles
                .AsNoTracking()
                .Where(p => p.CompanyId == companyId && p.RegionId != null && !p.IsDeleted)
                .Select(p => new { p.SasAccountId, p.SubscriberUid, p.RegionId })
                .ToListAsync(ct);

            var regionByKey = profiles.ToDictionary(
                p => $"{p.SasAccountId:N}:{p.SubscriberUid}",
                p => p.RegionId!.Value);

            var regionNames = await _db.SasRegions
                .AsNoTracking()
                .Where(r => r.CompanyId == companyId && !r.IsDeleted)
                .ToDictionaryAsync(r => r.Id, r => r.Name, ct);

            // 3) التجميع في الذاكرة (أحجام الساس لكل شركة معتدلة).
            decimal totalCost = 0, totalProfit = 0, totalRevenue = 0;
            var byRegion = new Dictionary<string, (decimal cost, decimal profit, decimal revenue, int count)>();
            var byPackage = new Dictionary<string, (decimal cost, decimal profit, decimal revenue, int count)>();

            foreach (var l in logs)
            {
                var cost = l.BasePrice;
                var profit = l.MaintenanceFee - l.ManualDiscount;
                var revenue = cost + profit;
                totalCost += cost; totalProfit += profit; totalRevenue += revenue;

                var key = $"{l.SasAccountId:N}:{l.SubscriberUid}";
                var regionName = regionByKey.TryGetValue(key, out var rid) && regionNames.TryGetValue(rid, out var rn)
                    ? rn : "بلا منطقة";
                var rAgg = byRegion.TryGetValue(regionName, out var rv) ? rv : default;
                byRegion[regionName] = (rAgg.cost + cost, rAgg.profit + profit, rAgg.revenue + revenue, rAgg.count + 1);

                var pkg = string.IsNullOrWhiteSpace(l.PlanName) ? "غير محدّدة" : l.PlanName!;
                var pAgg = byPackage.TryGetValue(pkg, out var pv) ? pv : default;
                byPackage[pkg] = (pAgg.cost + cost, pAgg.profit + profit, pAgg.revenue + revenue, pAgg.count + 1);
            }

            var regionsBreakdown = byRegion
                .Select(kv => new SasProfitRow(kv.Key, kv.Value.count, kv.Value.cost, kv.Value.profit, kv.Value.revenue))
                .OrderByDescending(x => x.Profit).ToList();
            var packagesBreakdown = byPackage
                .Select(kv => new SasProfitRow(kv.Key, kv.Value.count, kv.Value.cost, kv.Value.profit, kv.Value.revenue))
                .OrderByDescending(x => x.Profit).ToList();

            return Ok(new
            {
                success = true,
                totals = new SasProfitRow("الإجمالي", logs.Count, totalCost, totalProfit, totalRevenue),
                byRegion = regionsBreakdown,
                byPackage = packagesBreakdown
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تقرير أرباح الساس");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== بيانات المواطن الموسّعة (المرحلة 1) ====================
    // معزولة بالعزل الثلاثي عبر GetOwnedAccountAsync. المفتاح (CompanyId + account.Id + uid) من الحساب خادمياً.

    /// <summary>
    /// جلب بيانات المواطن الموسّعة لمشترك ساس (أو كائن فارغ إن لم تُحفظ بعد) — قراءة (view).
    /// المفتاح: (CompanyId + account.Id + uid) — مختوم من الحساب المملوك خادمياً.
    /// </summary>
    [HttpGet("accounts/{id}/users/{uid}/profile")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> GetSubscriberProfile(Guid id, string uid, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied))
            return denied!;

        var safeUid = Trim(uid);
        if (safeUid == null)
            return BadRequest(new { success = false, message = "معرّف المشترك مطلوب" });

        var account = await GetOwnedAccountAsync(id, companyId, userId, ct);
        if (account == null)
            return NotFound(new { success = false, message = "حساب الساس غير موجود" });

        try
        {
            var profile = await _db.SasSubscriberProfiles
                .FirstOrDefaultAsync(
                    x => x.CompanyId == account.CompanyId
                         && x.SasAccountId == account.Id
                         && x.SubscriberUid == safeUid
                         && !x.IsDeleted,
                    ct);

            var regionName = await ResolveRegionNameAsync(account.CompanyId, profile?.RegionId, ct);
            return Ok(new { success = true, data = BuildProfileDto(safeUid, profile, regionName) });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب بيانات المواطن الموسّعة");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// حفظ/تحديث بيانات المواطن الموسّعة لمشترك ساس (upsert) — كتابة (manage).
    /// المفتاح: (CompanyId + account.Id + uid) — مختوم من الحساب المملوك خادمياً. يعيد المحفوظ.
    /// </summary>
    [HttpPut("accounts/{id}/users/{uid}/profile")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> UpsertSubscriberProfile(
        Guid id,
        string uid,
        [FromBody] SasProfileUpsertRequest request,
        CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied))
            return denied!;

        var safeUid = Trim(uid);
        if (safeUid == null)
            return BadRequest(new { success = false, message = "معرّف المشترك مطلوب" });

        if (request == null)
            return BadRequest(new { success = false, message = "بيانات المواطن مطلوبة" });

        var account = await GetOwnedAccountAsync(id, companyId, userId, ct);
        if (account == null)
            return NotFound(new { success = false, message = "حساب الساس غير موجود" });

        try
        {
            var profile = await _db.SasSubscriberProfiles
                .FirstOrDefaultAsync(
                    x => x.CompanyId == account.CompanyId
                         && x.SasAccountId == account.Id
                         && x.SubscriberUid == safeUid
                         && !x.IsDeleted,
                    ct);

            var isNew = profile == null;
            if (profile == null)
            {
                profile = new SasSubscriberProfile
                {
                    Id = Guid.NewGuid(),
                    CompanyId = account.CompanyId,   // ختم العزل من الحساب المملوك
                    SasAccountId = account.Id,       // ختم العزل من الحساب المملوك
                    SubscriberUid = safeUid
                };
            }

            // المنطقة: تحقّق من ملكية الشركة (دفاع بالعمق — لا نثق بمعرّف العميل) قبل الربط.
            string? regionName = null;
            if (request.RegionId.HasValue && request.RegionId.Value != Guid.Empty)
            {
                var region = await _db.SasRegions.FirstOrDefaultAsync(
                    r => r.Id == request.RegionId.Value
                         && r.CompanyId == account.CompanyId
                         && !r.IsDeleted,
                    ct);
                if (region == null)
                    return BadRequest(new { success = false, message = "المنطقة غير موجودة ضمن الشركة" });
                profile.RegionId = region.Id;
                regionName = region.Name;
            }
            else
            {
                profile.RegionId = null; // إلغاء الربط عند إرسال null/فارغ
            }

            // اسم المستخدم (عرضي) + الحقول الموسّعة.
            profile.SubscriberUsername = Trim(request.SubscriberUsername) ?? profile.SubscriberUsername;
            profile.NationalId = Trim(request.NationalId);
            profile.FullNameQuad = Trim(request.FullNameQuad);
            profile.BirthDate = request.BirthDate;
            profile.Gender = Trim(request.Gender);
            profile.AltPhone = Trim(request.AltPhone);
            profile.WhatsappNumber = Trim(request.WhatsappNumber);
            profile.Email = Trim(request.Email);
            profile.AddressDetail = Trim(request.AddressDetail);
            profile.Latitude = request.Latitude;
            profile.Longitude = request.Longitude;
            profile.PropertyType = Trim(request.PropertyType);
            profile.Landmark = Trim(request.Landmark);

            if (isNew)
            {
                await _db.SasSubscriberProfiles.AddAsync(profile, ct);
            }
            else
            {
                profile.UpdatedAt = DateTime.UtcNow;
                _db.SasSubscriberProfiles.Update(profile);
            }

            await _db.SaveChangesAsync(ct);
            return Ok(new { success = true, data = BuildProfileDto(safeUid, profile, regionName), message = "تم حفظ بيانات المواطن بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حفظ بيانات المواطن الموسّعة");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== دفتر ذمم المواطنين (المرحلة 3 — التسجيل الآجل) ====================
    // معزولة بالعزل الثلاثي عبر GetOwnedAccountAsync (شركة + مالك + غير محذوف).
    // الذمة تُقيَّد على المشترك بمفتاح (SasAccountId:SubscriberUid) تحت «ذمم المواطنين 1180».
    // بلا أسرار في الردود. CompanyId/SasAccountId مختومة من الحساب خادمياً — لا من العميل.

    /// <summary>
    /// كشف حساب ذمّة المشترك/المواطن (الآجل) — قراءة (view).
    ///
    /// يجمع:
    ///  - الشحنات: سجلّات الساس الآجلة (<c>SubscriptionLogs</c> حيث SasAccountId+SubscriberUid و CollectionType='citizen').
    ///  - التسديدات: <c>SasCitizenPayments</c> لنفس المفتاح.
    ///  - الرصيد المستحق: رصيد الحساب الفرعي لذمّة المشترك تحت 1180 (أصول: مدين−دائن)، أو Σشحنات − Σتسديدات كبديل.
    ///
    /// الرد: <c>{ charges:[...], payments:[...], balance }</c>. بلا أسرار.
    /// </summary>
    [HttpGet("accounts/{id}/users/{uid}/statement")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> GetCitizenStatement(Guid id, string uid, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied))
            return denied!;

        var safeUid = Trim(uid);
        if (safeUid == null)
            return BadRequest(new { success = false, message = "معرّف المشترك مطلوب" });

        var account = await GetOwnedAccountAsync(id, companyId, userId, ct);
        if (account == null)
            return NotFound(new { success = false, message = "حساب الساس غير موجود" });

        try
        {
            // 1) الشحنات الآجلة لهذا المشترك ضمن هذا الحساب (دفاع بالعمق فوق المفتاح الثلاثي).
            var charges = await _unitOfWork.SubscriptionLogs.AsQueryable()
                .Where(l => l.SasAccountId == account.Id
                            && l.Source == SubscriptionLogSource.Sas
                            && l.CompanyId == account.CompanyId
                            && l.SubscriberUid == safeUid
                            && l.CollectionType == "citizen")
                .OrderBy(l => l.CreatedAt)
                .Select(l => new
                {
                    l.Id,
                    l.CreatedAt,
                    l.PlanName,
                    l.OperationType,
                    l.BasePrice,
                    l.PlanPrice,
                    l.Currency,
                    l.JournalEntryId
                })
                .ToListAsync(ct);

            // 2) التسديدات لنفس المشترك ضمن هذا الحساب.
            var payments = await _db.SasCitizenPayments
                .Where(p => p.CompanyId == account.CompanyId
                            && p.SasAccountId == account.Id
                            && p.SubscriberUid == safeUid
                            && !p.IsDeleted)
                .OrderBy(p => p.CreatedAt)
                .Select(p => new
                {
                    p.Id,
                    p.CreatedAt,
                    p.Amount,
                    p.Method,
                    p.Note,
                    p.JournalEntryId
                })
                .ToListAsync(ct);

            // 3) الرصيد المستحق: من رصيد الحساب الفرعي لذمّة المشترك (أدقّ)، وإلا Σشحنات − Σتسديدات.
            var balance = await GetCitizenBalanceAsync(account, safeUid, charges.Sum(c => c.PlanPrice ?? 0), payments.Sum(p => p.Amount), ct);

            var chargeDtos = charges.Select(c => new
            {
                id = c.Id,
                createdAt = c.CreatedAt,
                type = "charge",
                planName = c.PlanName,
                operationType = c.OperationType,
                amount = c.PlanPrice ?? 0,
                currency = c.Currency ?? "IQD",
                journalEntryId = c.JournalEntryId
            }).ToList();

            var paymentDtos = payments.Select(p => new
            {
                id = p.Id,
                createdAt = p.CreatedAt,
                type = "payment",
                amount = p.Amount,
                method = p.Method,
                note = p.Note,
                journalEntryId = p.JournalEntryId
            }).ToList();

            return Ok(new
            {
                success = true,
                data = new
                {
                    subscriberUid = safeUid,
                    charges = chargeDtos,
                    payments = paymentDtos,
                    balance
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب كشف حساب ذمّة المشترك");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تسديد ذمّة مشترك (الآجل) — كتابة (manage). الجسم: <c>{amount, method('cash'|'master'), note?}</c>.
    ///
    /// القيد (Posted فوراً، متوازن): مدين حساب التحصيل (نقد صندوق المشغّل 1110x / إلكتروني 1170)
    /// + دائن ذمّة المشترك (1180x بمفتاح SasAccountId:SubscriberUid). تُسجَّل الحركة في <c>SasCitizenPayments</c>.
    ///
    /// العزل: companyId/userId/accountId مختومة من الحساب خادمياً. يعيد الرصيد الجديد ومعرّف القيد. بلا أسرار.
    /// </summary>
    [HttpPost("accounts/{id}/users/{uid}/payment")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> AddCitizenPayment(
        Guid id,
        string uid,
        [FromBody] SasCitizenPaymentRequest request,
        CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied))
            return denied!;

        var safeUid = Trim(uid);
        if (safeUid == null)
            return BadRequest(new { success = false, message = "معرّف المشترك مطلوب" });

        if (request == null || request.Amount <= 0)
            return BadRequest(new { success = false, message = "مبلغ التسديد يجب أن يكون موجباً" });

        // وسيلة التسديد: نقد (صندوق المشغّل 1110x) أو إلكتروني (1170).
        var method = string.IsNullOrWhiteSpace(request.Method) ? "cash" : request.Method.Trim().ToLowerInvariant();
        if (method is not ("cash" or "master"))
            return BadRequest(new { success = false, message = "وسيلة تسديد غير مدعومة (المتاح: cash | master)" });

        var account = await GetOwnedAccountAsync(id, companyId, userId, ct);
        if (account == null)
            return NotFound(new { success = false, message = "حساب الساس غير موجود" });

        try
        {
            var amount = request.Amount;
            var note = Trim(request.Note);

            // اسم المشترك (للوصف) من بيانات المواطن المحفوظة إن وُجدت.
            var subscriberName = await _db.SasSubscriberProfiles
                .Where(x => x.CompanyId == account.CompanyId
                            && x.SasAccountId == account.Id
                            && x.SubscriberUid == safeUid
                            && !x.IsDeleted)
                .Select(x => x.SubscriberUsername)
                .FirstOrDefaultAsync(ct) ?? safeUid;

            // 1) ضمان وجود الحساب الأب 1180 ثم ذمّة المشترك الفرعية (نفس مفتاح الشحن).
            await ServiceRequestAccountingHelper.EnsureFixedParentAccount(
                _unitOfWork, AccountCodes.CitizenReceivables, "ذمم المشتركين (الآجل)", AccountType.Assets, account.CompanyId);

            var citizenPersonId = Sadara.API.Services.SubscriptionAccountingService.DeterministicGuid(CitizenKey(account.Id, safeUid));
            var citizenAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(
                _unitOfWork, AccountCodes.CitizenReceivables, citizenPersonId, subscriberName, account.CompanyId);
            await _unitOfWork.SaveChangesAsync(ct);

            // 2) حساب التحصيل (المدين): صندوق المشغّل (نقد) أو صندوق الدفع الإلكتروني.
            Account debitAccount;
            if (method == "cash")
            {
                var operatorName = await _unitOfWork.Users.AsQueryable()
                    .Where(u => u.Id == userId).Select(u => u.FullName).FirstOrDefaultAsync(ct) ?? "مشغل";
                debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(
                    _unitOfWork, AccountCodes.Cash, userId, $"صندوق {operatorName}", account.CompanyId);
                await _unitOfWork.SaveChangesAsync(ct);
            }
            else // master
            {
                debitAccount = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.ElectronicPayment, account.CompanyId)
                    ?? throw new Exception("حساب صندوق الدفع الإلكتروني 1170 غير موجود");
            }

            // 3) القيد: مدين التحصيل / دائن ذمّة المشترك — بالمبلغ.
            var payment = new SasCitizenPayment
            {
                Id = Guid.NewGuid(),
                CompanyId = account.CompanyId,
                SasAccountId = account.Id,
                SubscriberUid = safeUid,
                Amount = amount,
                Method = method,
                Note = note
            };
            await _db.SasCitizenPayments.AddAsync(payment, ct);
            await _db.SaveChangesAsync(ct);

            var lines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>
            {
                (debitAccount.Id, amount, 0, $"{debitAccount.Name} - تسديد ذمّة {subscriberName}"),
                (citizenAccount.Id, 0, amount, $"تسديد ذمّة - {subscriberName}")
            };

            Guid? journalEntryId = null;
            try
            {
                journalEntryId = await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
                    _unitOfWork, account.CompanyId, userId,
                    $"تسديد ذمّة مشترك - {subscriberName}",
                    JournalReferenceType.SasCitizenPayment, payment.Id.ToString(), lines);
                await _unitOfWork.SaveChangesAsync(ct);

                payment.JournalEntryId = journalEntryId;
                _db.SasCitizenPayments.Update(payment);
                await _db.SaveChangesAsync(ct);
            }
            catch (Exception exAcc)
            {
                _logger.LogWarning(exAcc, "فشل إنشاء قيد تسديد ذمّة المشترك {PaymentId} — الحركة حُفظت بدونه", payment.Id);
            }

            // 4) الرصيد الجديد بعد التسديد.
            var newBalance = await GetCitizenBalanceAsync(account, safeUid, null, null, ct);

            return Ok(new
            {
                success = true,
                paymentId = payment.Id,
                journalEntryId,
                balance = newBalance,
                message = "تم تسجيل التسديد بنجاح"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تسجيل تسديد ذمّة المشترك");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// قائمة المدينين (المشتركون ذوو رصيد ذمّة > 0) لهذا الحساب — قراءة (view).
    ///
    /// يجمّع الشحنات والتسديدات لكل مشترك (CollectionType='citizen') ويحسب الرصيد = Σشحنات − Σتسديدات،
    /// ثم يرشّح الموجب فقط. اسم المشترك من بيانات المواطن إن وُجد، وإلا اسم المستخدم من السجل، وإلا الـ uid.
    ///
    /// الرد: <c>[{subscriberUid, name, balance}]</c>. العزل: الحساب مملوك + الشركة. بلا أسرار.
    /// </summary>
    [HttpGet("accounts/{id}/debtors")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> GetCitizenDebtors(Guid id, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied))
            return denied!;

        var account = await GetOwnedAccountAsync(id, companyId, userId, ct);
        if (account == null)
            return NotFound(new { success = false, message = "حساب الساس غير موجود" });

        try
        {
            // 1) إجمالي الشحنات الآجلة لكل مشترك.
            var chargeSums = await _unitOfWork.SubscriptionLogs.AsQueryable()
                .Where(l => l.SasAccountId == account.Id
                            && l.Source == SubscriptionLogSource.Sas
                            && l.CompanyId == account.CompanyId
                            && l.CollectionType == "citizen"
                            && l.SubscriberUid != null)
                .GroupBy(l => l.SubscriberUid!)
                .Select(g => new { Uid = g.Key, Total = g.Sum(x => x.PlanPrice ?? 0) })
                .ToListAsync(ct);

            if (chargeSums.Count == 0)
                return Ok(new { success = true, data = Array.Empty<object>(), total = 0 });

            // 2) إجمالي التسديدات لكل مشترك.
            var paymentSums = await _db.SasCitizenPayments
                .Where(p => p.CompanyId == account.CompanyId
                            && p.SasAccountId == account.Id
                            && !p.IsDeleted)
                .GroupBy(p => p.SubscriberUid)
                .Select(g => new { Uid = g.Key, Total = g.Sum(x => x.Amount) })
                .ToListAsync(ct);

            var paidByUid = paymentSums.ToDictionary(x => x.Uid, x => x.Total, StringComparer.Ordinal);

            // 3) الرصيد = شحنات − تسديدات؛ المدينون فقط (> 0).
            var debtorUids = chargeSums
                .Select(c => new
                {
                    c.Uid,
                    Balance = c.Total - (paidByUid.TryGetValue(c.Uid, out var paid) ? paid : 0)
                })
                .Where(x => x.Balance > 0)
                .ToList();

            if (debtorUids.Count == 0)
                return Ok(new { success = true, data = Array.Empty<object>(), total = 0 });

            var uids = debtorUids.Select(d => d.Uid).ToList();

            // 4) أسماء المشتركين من بيانات المواطن المحفوظة (إن وُجدت).
            var names = await _db.SasSubscriberProfiles
                .Where(x => x.CompanyId == account.CompanyId
                            && x.SasAccountId == account.Id
                            && !x.IsDeleted
                            && uids.Contains(x.SubscriberUid))
                .Select(x => new { x.SubscriberUid, x.SubscriberUsername, x.FullNameQuad })
                .ToListAsync(ct);
            var nameByUid = names.ToDictionary(
                n => n.SubscriberUid,
                n => !string.IsNullOrWhiteSpace(n.FullNameQuad) ? n.FullNameQuad! : (n.SubscriberUsername ?? string.Empty),
                StringComparer.Ordinal);

            var data = debtorUids
                .OrderByDescending(d => d.Balance)
                .Select(d => new
                {
                    subscriberUid = d.Uid,
                    name = nameByUid.TryGetValue(d.Uid, out var nm) && !string.IsNullOrWhiteSpace(nm) ? nm : d.Uid,
                    balance = d.Balance
                })
                .ToList();

            return Ok(new { success = true, data, total = data.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب قائمة مدينين الذمم");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// يحسب رصيد ذمّة مشترك: من رصيد حسابه الفرعي تحت 1180 (أدقّ، أصول: مدين−دائن)، وإلا Σشحنات − Σتسديدات.
    /// عند تمرير <paramref name="chargesTotal"/>/<paramref name="paymentsTotal"/> (محسوبَين مسبقاً) يُستخدمان كبديل بلا استعلام إضافي.
    /// </summary>
    private async Task<decimal> GetCitizenBalanceAsync(
        SasAccount account, string uid, decimal? chargesTotal, decimal? paymentsTotal, CancellationToken ct)
    {
        // المسار الأدقّ: رصيد الحساب الفرعي لذمّة المشترك (Description=personId المشتق حتمياً من المفتاح).
        var citizenPersonId = Sadara.API.Services.SubscriptionAccountingService
            .DeterministicGuid(CitizenKey(account.Id, uid)).ToString();
        var parent = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.CitizenReceivables, account.CompanyId);
        if (parent != null)
        {
            var sub = await _unitOfWork.Accounts.AsQueryable()
                .Where(a => a.ParentAccountId == parent.Id
                            && a.CompanyId == account.CompanyId
                            && a.Description == citizenPersonId
                            && a.IsActive)
                .Select(a => (decimal?)a.CurrentBalance)
                .FirstOrDefaultAsync(ct);
            if (sub.HasValue)
                return sub.Value;
        }

        // البديل: Σشحنات − Σتسديدات (يُحسب إن لم يُمرَّر مسبقاً).
        var charges = chargesTotal ?? await _unitOfWork.SubscriptionLogs.AsQueryable()
            .Where(l => l.SasAccountId == account.Id
                        && l.Source == SubscriptionLogSource.Sas
                        && l.CompanyId == account.CompanyId
                        && l.SubscriberUid == uid
                        && l.CollectionType == "citizen")
            .SumAsync(l => l.PlanPrice ?? 0, ct);

        var payments = paymentsTotal ?? await _db.SasCitizenPayments
            .Where(p => p.CompanyId == account.CompanyId
                        && p.SasAccountId == account.Id
                        && p.SubscriberUid == uid
                        && !p.IsDeleted)
            .SumAsync(p => p.Amount, ct);

        return charges - payments;
    }

    // ---------- مساعدات التسعير وبيانات المواطن ----------

    /// <summary>يبني DTO تسعير باقة واحدة من الصفّ المخزّن (إن وُجد)؛ باقة غير مسعّرة ⇒ أصفار. الربح محسوب.</summary>
    private static SasPricingPackageDto BuildPricingDto(string profileId, string profileName, SasPackagePrice? row)
    {
        var cost = row?.Cost ?? 0;
        var selling = row?.SellingPrice ?? 0;
        return new SasPricingPackageDto(
            profileId,
            profileName,
            cost,
            selling,
            selling - cost,            // الربح = سعر البيع − الكلفة (محسوب)
            row?.IsActive ?? true);
    }

    /// <summary>يبني DTO بيانات المواطن الموسّعة من الكيان (أو كائن فارغ بالـ uid فقط إن لم يُحفظ بعد).
    /// <paramref name="regionName"/> اسم المنطقة المرتبطة (عرضي) إن وُجدت.</summary>
    private static SasProfileDto BuildProfileDto(string uid, SasSubscriberProfile? p, string? regionName = null)
        => new(
            uid,
            p?.SubscriberUsername,
            p?.NationalId,
            p?.FullNameQuad,
            p?.BirthDate,
            p?.Gender,
            p?.AltPhone,
            p?.WhatsappNumber,
            p?.Email,
            p?.RegionId,
            regionName,
            p?.AddressDetail,
            p?.Latitude,
            p?.Longitude,
            p?.PropertyType,
            p?.Landmark);

    /// <summary>
    /// يحلّل باقات SAS4 الخام (<c>GetPackagesAsync</c>) إلى قائمة (profileId, profileName).
    /// يقبل مصفوفة جذرية أو تحت <c>data</c>/<c>packages</c>/<c>profiles</c>؛ ويقرأ المعرّف/الاسم بمفاتيح شائعة.
    /// أي عنصر بلا معرّف يُتجاهَل بأمان (لا يُسقط الباقي).
    /// </summary>
    private static List<(string ProfileId, string ProfileName)> ParseSasProfiles(string raw)
    {
        var list = new List<(string, string)>();
        if (string.IsNullOrWhiteSpace(raw))
            return list;

        try
        {
            using var doc = System.Text.Json.JsonDocument.Parse(raw);
            var root = doc.RootElement;

            // ابحث عن أول مصفوفة باقات — جذرياً أو تحت data/packages/profiles/items، حتى لو كانت
            // مغلّفة مرّتين (مثل {status, data:{data:[...]}} أو {success, data:{status, data:[...]}}).
            System.Text.Json.JsonElement arr = default;
            var found = FindProfilesArray(root, 0, out arr);
            if (!found)
                return list;

            foreach (var item in arr.EnumerateArray())
            {
                if (item.ValueKind != System.Text.Json.JsonValueKind.Object)
                    continue;

                var pid = ReadString(item, "id")
                       ?? ReadString(item, "profile_id")
                       ?? ReadString(item, "profileId")
                       ?? ReadNumberAsString(item, "id");
                if (string.IsNullOrWhiteSpace(pid))
                    continue;

                var name = ReadString(item, "name")
                        ?? ReadString(item, "profile_name")
                        ?? ReadString(item, "profileName")
                        ?? string.Empty;

                list.Add((pid, name));
            }
        }
        catch
        {
            // تحليل فاشل ⇒ قائمة فارغة (الصفوف المخزّنة تغطّي العرض).
        }

        return list;
    }

    /// <summary>
    /// يبحث تعاوديّاً عن أوّل مصفوفة باقات (جذرية أو تحت data/packages/profiles/items)، حتى لو
    /// كانت مغلّفة عبر عدّة مستويات (مثل {status, data:{data:[...]}}). عمق محدود (≤3) لتفادي الدوران.
    /// </summary>
    private static bool FindProfilesArray(System.Text.Json.JsonElement node, int depth,
        out System.Text.Json.JsonElement arr)
    {
        arr = default;
        if (depth > 3) return false;
        if (node.ValueKind == System.Text.Json.JsonValueKind.Array)
        {
            arr = node;
            return true;
        }
        if (node.ValueKind != System.Text.Json.JsonValueKind.Object)
            return false;
        // أولاً: مفاتيح الحاويات الشائعة (مصفوفة مباشرة أو مغلّفة أعمق).
        foreach (var key in new[] { "data", "packages", "profiles", "items", "result", "results" })
        {
            if (node.TryGetProperty(key, out var el))
            {
                if (el.ValueKind == System.Text.Json.JsonValueKind.Array) { arr = el; return true; }
                if (el.ValueKind == System.Text.Json.JsonValueKind.Object &&
                    FindProfilesArray(el, depth + 1, out arr))
                    return true;
            }
        }
        return false;
    }

    /// <summary>يقرأ قيمة عددية كنصّ من خاصيّة JSON (لمعرّفات رقمية)؛ null إن غابت/غير رقمية.</summary>
    private static string? ReadNumberAsString(System.Text.Json.JsonElement obj, string name)
    {
        if (obj.ValueKind != System.Text.Json.JsonValueKind.Object || !obj.TryGetProperty(name, out var el))
            return null;
        return el.ValueKind == System.Text.Json.JsonValueKind.Number ? el.GetRawText() : null;
    }

    /// <summary>جلب ملخّص/تفاصيل المالية للوكيل (تبويب المالية) — قراءة (view).</summary>
    [HttpGet("accounts/{id}/finance")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetFinance(Guid id, CancellationToken ct)
        => PassThroughAsync(id, (acc, pwd, token) =>
            _sasClient.GetFinanceAsync(acc.ServerUrl, acc.Username, pwd, token), null, ct);

    /// <summary>جلب حالة صحّة الاتصال/الحساب مع نظام الساس (تبويب الصحّة) — قراءة (view).</summary>
    [HttpGet("accounts/{id}/health")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetHealth(Guid id, CancellationToken ct)
        => PassThroughAsync(id, (acc, pwd, token) =>
            _sasClient.GetHealthAsync(acc.ServerUrl, acc.Username, pwd, token), null, ct);

    /// <summary>
    /// جلب مرشّحي التجديد (المنتهون/الأوشك على الانتهاء) — قراءة (view).
    /// <c>days</c> نافذة الأيام (افتراضي 7)، <c>query</c> نص بحث اختياري.
    /// </summary>
    [HttpGet("accounts/{id}/renewal/candidates")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetRenewalCandidates(
        Guid id,
        [FromQuery] int days = 7,
        [FromQuery] string? query = null,
        CancellationToken ct = default)
    {
        // قصّ آمن للوسائط: أيام ضمن مدى معقول، وبحث محدود الطول.
        var safeDays = Math.Clamp(days, 0, 365);
        var safeQuery = string.IsNullOrWhiteSpace(query)
            ? null
            : (query.Length > MaxQueryValueLength ? query[..MaxQueryValueLength] : query);

        return PassThroughAsync(id, (acc, pwd, token) =>
            _sasClient.GetRenewalCandidatesAsync(acc.ServerUrl, acc.Username, pwd, safeDays, safeQuery, token), null, ct);
    }

    /// <summary>
    /// تجديد جماعي لمشتركين محدّدين — عملية كتابية (manage + failClosed).
    /// يمرّ عبر <see cref="GetOwnedAccountAsync"/> للعزل الصارم؛ يُفكّ التشفير في الذاكرة فقط.
    /// يدعم <c>dryRun</c> للمعاينة دون تنفيذ فعلي.
    /// </summary>
    [HttpPost("accounts/{id}/renewal/bulk")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> BulkRenew(Guid id, [FromBody] BulkRenewRequest request, CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied))
            return denied!;

        if (request == null || request.SubscriberIds == null || request.SubscriberIds.Count == 0)
            return BadRequest(new { success = false, message = "قائمة المشتركين مطلوبة" });

        if (request.Months <= 0 || request.Months > 60)
            return BadRequest(new { success = false, message = "عدد الأشهر غير صالح" });

        // حدّ أعلى معقول لحجم الدفعة (حماية من الإساءة).
        if (request.SubscriberIds.Count > 1000)
            return BadRequest(new { success = false, message = "حجم الدفعة يتجاوز الحد المسموح" });

        // تصفية معرّفات فارغة/مكرّرة قبل التمرير.
        var subscriberIds = request.SubscriberIds
            .Where(s => !string.IsNullOrWhiteSpace(s))
            .Select(s => s.Trim())
            .Distinct(StringComparer.Ordinal)
            .ToList();

        if (subscriberIds.Count == 0)
            return BadRequest(new { success = false, message = "قائمة المشتركين مطلوبة" });

        var account = await GetOwnedAccountAsync(id, companyId, userId, ct);
        if (account == null)
            return NotFound(new { success = false, message = "حساب الساس غير موجود" });

        try
        {
            var password = _secretProtector.Unprotect(account.PasswordEncrypted); // في الذاكرة فقط
            var raw = await _sasClient.BulkRenewAsync(
                account.ServerUrl,
                account.Username,
                password,
                subscriberIds,
                request.Months,
                string.IsNullOrWhiteSpace(request.ProfileId) ? null : request.ProfileId.Trim(),
                request.DryRun ?? false,
                ct);

            return Content(raw, "application/json");
        }
        catch (SasServiceUnavailableException ex)
        {
            _logger.LogWarning(ex, "خدمة الساس غير متاحة أثناء التجديد الجماعي");
            return StatusCode(503, new { success = false, message = "خدمة الساس غير متاحة حالياً" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في التجديد الجماعي عبر خدمة الساس");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== العقد الموحّد الكامل: عمليات الساس account-scoped ====================
    // كل النقاط أدناه تحت /api/sas-agent/accounts/{id}/... وتمرّ عبر GetOwnedAccountAsync للعزل الثلاثي.
    // القراءات: RequirePermission("sas_agent","view",...,failClosed:true).
    // الكتابات: RequirePermission("sas_agent","manage",...,failClosed:true).
    // فكّ التشفير في الذاكرة فقط داخل PassThroughAsync/PassThroughWriteAsync؛ لا سرّ يُعاد أو يُسجَّل.

    // ---------- المشتركون: قراءات (view) ----------

    /// <summary>تفاصيل مشترك محدّد من خدمة الساس — قراءة (view).</summary>
    [HttpGet("accounts/{id}/users/{uid}/detail")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetUserDetail(Guid id, string uid, CancellationToken ct)
        => PassThroughAsync(id, (acc, pwd, token) =>
            _sasClient.GetUserDetailAsync(acc.ServerUrl, acc.Username, pwd, uid, token), null, ct);

    /// <summary>نظرة عامة على مشترك محدّد من خدمة الساس — قراءة (view).</summary>
    [HttpGet("accounts/{id}/users/{uid}/overview")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetUserOverview(Guid id, string uid, CancellationToken ct)
        => PassThroughAsync(id, (acc, pwd, token) =>
            _sasClient.GetUserOverviewAsync(acc.ServerUrl, acc.Username, pwd, uid, token), null, ct);

    /// <summary>سجل/تاريخ مشترك محدّد من خدمة الساس — قراءة (view).</summary>
    [HttpGet("accounts/{id}/users/{uid}/history")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetUserHistory(Guid id, string uid, CancellationToken ct)
        => PassThroughAsync(id, (acc, pwd, token) =>
            _sasClient.GetUserHistoryAsync(acc.ServerUrl, acc.Username, pwd, uid, token), null, ct);

    /// <summary>بيانات تمديد/إضافة رصيد لمشترك — قراءة (view).</summary>
    [HttpGet("accounts/{id}/users/{uid}/extend-data")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetUserExtendData(Guid id, string uid, CancellationToken ct)
        => PassThroughAsync(id, (acc, pwd, token) =>
            _sasClient.GetUserExtendDataAsync(acc.ServerUrl, acc.Username, pwd, uid, token), null, ct);

    // ---------- المشتركون: كتابات (manage) ----------

    /// <summary>تنفيذ إجراء على مشترك — كتابة (manage).</summary>
    [HttpPost("accounts/{id}/users/{uid}/action")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> UserAction(Guid id, string uid, [FromBody] SasActionRequest request, CancellationToken ct)
    {
        if (request == null || string.IsNullOrWhiteSpace(request.Action))
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "الإجراء مطلوب" }));

        return PassThroughWriteAsync(id, (acc, pwd, token) =>
            _sasClient.UserActionAsync(acc.ServerUrl, acc.Username, pwd, uid, request.Action.Trim(), request.Params, token), ct);
    }

    /// <summary>
    /// تفعيل/تجديد/تغيير باقة مشترك ساس مع قيد محاسبي (محاسبة موحّدة مع FTTH) — كتابة (manage).
    ///
    /// التدفّق (كله خادمي، لا ثقة بالعميل في السعر أو الهوية):
    ///  1) <see cref="GetOwnedAccountAsync"/> للعزل الثلاثي (شركة + مالك + غير محذوف) → يُفكّ التشفير في الذاكرة فقط.
    ///  2) idempotency: رفض إن وُجد <c>SubscriptionLog</c> سابق بنفس <c>FtthTransactionId</c> لنفس الشركة (منع قيد مزدوج).
    ///  3) جلب السعر خادمياً من <c>user/activationData/{uid}</c> (n_required_amount/vat/manager_balance) — لا من العميل.
    ///  4) تنفيذ الإجراء على SAS4 عبر <see cref="ISasServiceClient.UserActionAsync"/>؛ فشل الساس → خطأ بلا قيد.
    ///  5) عند النجاح: إنشاء <c>SubscriptionLog{Source=Sas,…}</c> ثم <c>SubscriptionAccountingService.RecordAsync(…)</c>
    ///     (القيد لا يُسقط السجل عند فشله — يُسجَّل تحذير ويُعاد بلا journalEntryId).
    ///  6) إعادة إيصال للطباعة بالواجهة لاحقاً.
    ///
    /// العزل: companyId/userId/accountId مختومة من <c>account</c> خادمياً (لا من العميل).
    /// </summary>
    [HttpPost("accounts/{id}/users/{uid}/activate-billed")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> ActivateBilled(
        Guid id,
        string uid,
        [FromBody] SasActivateBilledRequest request,
        CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied))
            return denied!;

        if (string.IsNullOrWhiteSpace(uid))
            return BadRequest(new { success = false, message = "معرّف المشترك مطلوب" });

        if (request == null || string.IsNullOrWhiteSpace(request.Action))
            return BadRequest(new { success = false, message = "الإجراء مطلوب" });

        // قائمة سماح صارمة للإجراءات المالية المدعومة.
        var action = request.Action.Trim();
        if (action is not ("activate" or "extend" or "changeProfile"))
            return BadRequest(new { success = false, message = "إجراء غير مدعوم (المتاح: activate | extend | changeProfile)" });

        // قائمة سماح لنوع التحصيل (مطابق لمنطق المحاسبة الموحّد). «citizen» = آجل على ذمة المشترك (دفتر الذمم).
        var collectionType = string.IsNullOrWhiteSpace(request.CollectionType) ? "cash" : request.CollectionType.Trim().ToLowerInvariant();
        if (collectionType is not ("cash" or "credit" or "agent" or "citizen" or "technician"))
            return BadRequest(new { success = false, message = "نوع تحصيل غير مدعوم (المتاح: cash | credit | agent | citizen | technician)" });

        if (collectionType == "agent" && (!request.LinkedAgentId.HasValue || request.LinkedAgentId.Value == Guid.Empty))
            return BadRequest(new { success = false, message = "يجب تحديد الوكيل عند اختيار نوع التحصيل 'وكيل'" });

        if (collectionType == "technician" && (!request.LinkedTechnicianId.HasValue || request.LinkedTechnicianId.Value == Guid.Empty))
            return BadRequest(new { success = false, message = "يجب تحديد الفني عند اختيار نوع التحصيل 'فني'" });

        // تحقّق المدة للإجراءات التي تتطلّبها.
        var months = request.Months;
        if (action is "activate" or "extend")
        {
            if (!months.HasValue || months.Value <= 0 || months.Value > 60)
                return BadRequest(new { success = false, message = "عدد الأشهر غير صالح (1..60)" });
        }

        if (action == "changeProfile" && string.IsNullOrWhiteSpace(request.ProfileId))
            return BadRequest(new { success = false, message = "معرّف الباقة مطلوب لتغيير الباقة" });

        // 1) العزل الصارم + فكّ التشفير في الذاكرة فقط.
        var account = await GetOwnedAccountAsync(id, companyId, userId, ct);
        if (account == null)
            return NotFound(new { success = false, message = "حساب الساس غير موجود" });

        try
        {
            var password = _secretProtector.Unprotect(account.PasswordEncrypted); // في الذاكرة فقط

            // قلب المنطق مُستخرَج في ActivateBilledCoreAsync (قابل لإعادة الاستخدام من التجديد الجماعي).
            var core = await ActivateBilledCoreAsync(account, uid, request, companyId, userId, password, ct);

            // ترجمة نتيجة القلب إلى IActionResult بنفس السلوك/الرد السابق تماماً.
            if (core.Conflict)
                return Conflict(new { success = false, message = core.Message, transactionId = core.TransactionId });

            if (!core.Ok)
                return StatusCode(core.StatusCode, new { success = false, message = core.Message });

            return Ok(new
            {
                success = true,
                logId = core.LogId,
                journalEntryId = core.JournalEntryId,
                receipt = core.Receipt
            });
        }
        catch (SasServiceUnavailableException ex)
        {
            _logger.LogWarning(ex, "خدمة الساس غير متاحة أثناء التفعيل المحاسبي");
            return StatusCode(503, new { success = false, message = "خدمة الساس غير متاحة حالياً" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في التفعيل المحاسبي عبر خدمة الساس");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// قلب منطق التفعيل/التجديد/تغيير الباقة المفوتر — مُستخرَج ليُعاد استخدامه من النقطة الفردية
    /// (<see cref="ActivateBilled"/>) والتجديد الجماعي (<see cref="BulkRenewalBilled"/>) معاً بنفس السلوك.
    ///
    /// افتراضات المدخلات (مضمونة من المستدعي): العزل محسوم عبر <paramref name="account"/> المملوك،
    /// وفكّ التشفير تمّ وأُعطيت <paramref name="pwd"/>. التحقّقات الأولية (الإجراء/المدة/نوع التحصيل)
    /// يفرضها المستدعي الفردي؛ التجديد الجماعي يمرّر طلباً مُنسّقاً مسبقاً.
    ///
    /// التدفّق:
    ///  1) idempotency: رفض إن وُجد <c>SubscriptionLog</c> سابق بنفس <c>FtthTransactionId</c> لنفس الشركة.
    ///  2) جلب السعر خادمياً من <c>user/activationData/{uid}</c> (لا من العميل) — تعذّره لا يُجهض (سعر 0).
    ///  3) تنفيذ الإجراء على SAS4؛ فشله (SasServiceUnavailable) ⇒ نتيجة بـ StatusCode=502 بلا قيد.
    ///  4) عند النجاح: <c>SubscriptionLog{Source=Sas}</c> + <c>SubscriptionAccountingService.RecordAsync</c>
    ///     (القيد لا يُسقط السجل عند فشله).
    ///  5) إرجاع <see cref="SasBilledResult"/> يحمل logId/journalEntryId/receipt للطباعة/الواتساب.
    ///
    /// ⚠️ لا يلتقط <c>SasServiceUnavailableException</c> الصادر من <c>SasGetAsync</c> كلياً (يُترك لمنطق السعر)،
    /// لكنه يلتقطه حول <c>UserActionAsync</c> ليعيد 502. أي استثناء آخر يُترك ليُعالجه المستدعي
    /// (الفردي يترجمه إلى 503/500؛ الجماعي يلتقطه لكل مشترك على حدة لضمان النجاح الجزئي).
    /// </summary>
    private async Task<SasBilledResult> ActivateBilledCoreAsync(
        SasAccount account,
        string uid,
        SasActivateBilledRequest req,
        Guid companyId,
        Guid userId,
        string pwd,
        CancellationToken ct)
    {
        var action = req.Action.Trim();
        var collectionType = string.IsNullOrWhiteSpace(req.CollectionType)
            ? "cash"
            : req.CollectionType.Trim().ToLowerInvariant();
        var months = req.Months;
        // أجور الصيانة: إن أرسل العميل قيمة صراحةً تُحترم كتجاوز؛ وإلا تُجلب تلقائياً من منطقة المشترك (مبلغ ثابت لكل منطقة).
        var requestedFee = req.MaintenanceFee;
        var regionFee = requestedFee.HasValue ? 0m : await ResolveRegionMaintenanceFeeAsync(account, uid, ct);
        var baseServiceFee = Math.Max(0, requestedFee ?? regionFee);
        var maintenanceFee = baseServiceFee;
        var manualDiscount = Math.Max(0, req.ManualDiscount ?? 0);

        // 1) idempotency: معرّف عملية فريد — من الطلب إن أُرسل (وصالح) وإلا نولّده خادمياً.
        var transactionId = NormalizeTransactionId(req.TransactionId);

        var alreadyLogged = await _unitOfWork.SubscriptionLogs.AsQueryable()
            .AnyAsync(l => l.FtthTransactionId == transactionId && l.CompanyId == companyId, ct);
        if (alreadyLogged)
            return SasBilledResult.AsConflict(transactionId, "العملية مُنفّذة مسبقاً (معرّف عملية مكرّر)");

        var safePhone = Trim(req.Phone);
        var note = Trim(req.Note);

        // 1.ب) حارس عزل مالي (قبل أي أثر على SAS4): عند التحصيل «فني»/«وكيل» يجب أن يكون
        //      الطرف المدين ضمن شركة الحساب — وإلا رفض صريح. المحرّك المحاسبي المشترك يجلب
        //      الفني/الوكيل بـ GetByIdAsync بلا فلتر شركة، فنفرض العزل هنا لمنع إسناد ذمّة
        //      لفني/وكيل شركة أخرى أو إنشاء سجلّ/حركة يتيمة بمعرّف غير صالح.
        if (collectionType == "technician")
        {
            var techOk = req.LinkedTechnicianId.HasValue && req.LinkedTechnicianId.Value != Guid.Empty &&
                await _db.Users.AsNoTracking().AnyAsync(
                    u => u.Id == req.LinkedTechnicianId.Value && u.CompanyId == account.CompanyId && !u.IsDeleted, ct);
            if (!techOk)
                return SasBilledResult.AsFailure(400, "الفني المحدّد غير موجود في شركتك", transactionId);
        }
        else if (collectionType == "agent")
        {
            var agentOk = req.LinkedAgentId.HasValue && req.LinkedAgentId.Value != Guid.Empty &&
                await _db.Agents.AsNoTracking().AnyAsync(
                    a => a.Id == req.LinkedAgentId.Value && a.CompanyId == account.CompanyId && !a.IsDeleted, ct);
            if (!agentOk)
                return SasBilledResult.AsFailure(400, "الوكيل المحدّد غير موجود في شركتك", transactionId);
        }

        // 2) جلب السعر خادمياً من activationData (لا نثق بالعميل في السعر).
        //    للـ extend قد لا يعيد سعراً — نستخدم activationData نفسه؛ إن غاب يبقى 0 (منطق بديل في المحاسبة).
        decimal basePrice = 0;
        string? planName = null;
        string? activationProfileId = null; // profileId مستنتَج من activationData (للبحث في جدول التسعير).
        try
        {
            var activationRaw = await _sasClient.SasGetAsync(
                account.ServerUrl, account.Username, pwd, $"user/activationData/{uid}", ct);
            (basePrice, planName, activationProfileId) = ParseActivationData(activationRaw);
            // تطبيع السعر من وحدة SAS4 (قد تكون بالآلاف) إلى الدينار الحقيقي عبر مُضاعِف
            // الحساب (افتراضي 1000). يُطبَّق هنا عند المنبع فتتّسق كل الطبقات (السجل + القيد
            // المحاسبي + العرض) مع محاسبة FTTH بالدينار الكامل. القيم اليدوية (الصيانة/الخصم)
            // والتسعير اليدوي (SasPackagePrice) بالدينار الحقيقي أصلاً فلا تُضرب.
            basePrice *= account.AmountMultiplier;
        }
        catch (SasServiceUnavailableException)
        {
            // إذا تعذّر جلب السعر لا نُجهض كلياً: نُكمل بسعر 0 (يُسجَّل تحذير) لأن الإجراء قد ينجح دون سعر معروف.
            _logger.LogWarning("تعذّر جلب activationData للمشترك {Uid} — سيُستخدم سعر 0", uid);
        }

        // 2.ب) تسعير الباقة (نظام الأرباح): إن وُجد صفّ SasPackagePrice فعّال لهذه الباقة ضمن هذا الحساب،
        //     فهو مصدر الحقيقة للتسعير (يَجُبّ activationData): BasePrice=الكلفة (رصيد الصفحة)،
        //     MaintenanceFee=الربح(سعر البيع−الكلفة)+أجور الطلب (إيراد). تدهور رشيق: غياب الصفّ ⇒ سلوك activationData الحالي.
        var pricingProfileId = ResolvePricingProfileId(req.ProfileId, activationProfileId);
        if (!string.IsNullOrWhiteSpace(pricingProfileId))
        {
            var price = await _db.SasPackagePrices
                .AsNoTracking()
                .FirstOrDefaultAsync(
                    x => x.CompanyId == account.CompanyId
                         && x.SasAccountId == account.Id
                         && x.ProfileId == pricingProfileId
                         && x.IsActive
                         && !x.IsDeleted,
                    ct);

            if (price != null && price.SellingPrice > 0)
            {
                // basePrice يبقى = الأساسي المخصوم فعلاً من الساس (activationData) — لا يُدخَل يدوياً.
                // الربح = سعر البيع − الأساسي؛ المحصّل من المشترك = سعر البيع + أجور الصيانة.
                var margin = Math.Max(0, price.SellingPrice - basePrice);
                maintenanceFee = margin + baseServiceFee;                      // الربح + أجور الصيانة (طلب أو منطقة)
                if (string.IsNullOrWhiteSpace(planName))
                    planName = price.ProfileName;                             // اسم الباقة من التسعير إن لم يُعرف
            }
        }

        // 3) تنفيذ الإجراء على SAS4 (مالي: money_collected=true + transaction_id للـ idempotency على طرف الساس).
        var sasParams = BuildActionParams(action, months, req.ProfileId, transactionId);
        string actionRaw;
        try
        {
            actionRaw = await _sasClient.UserActionAsync(
                account.ServerUrl, account.Username, pwd, uid, action, sasParams, ct);
        }
        catch (SasServiceUnavailableException ex)
        {
            // فشل SAS4/الخدمة → نُعيد نتيجة 502 بلا أي قيد محاسبي.
            _logger.LogWarning(ex, "فشل تنفيذ إجراء الساس {Action} للمشترك {Uid} — لا قيد", action, uid);
            return SasBilledResult.AsFailure(502, "تعذّر تنفيذ العملية على نظام الساس", transactionId);
        }

        // 4) عند النجاح: إنشاء SubscriptionLog(Source=Sas) ثم القيد المحاسبي الموحّد.
        var opType = action == "activate" ? "purchase" : "renewal";
        // نفس معادلة RecordAsync حرفياً (CompanyDiscount=0): netFromCompany = basePrice (إن >0)
        // أو PlanPrice وإلا؛ هنا PlanPrice=basePrice ليتطابق الطرفان. companyDiscountProfit=0.
        var netFromCompany = basePrice; // CompanyDiscount=0
        var collectedAmount = netFromCompany + maintenanceFee - manualDiscount; // ما يدفعه العميل

        // اسم المشغّل الحالي (المتصل) لحقل ActivatedBy — استعلام واحد AsNoTracking؛ null عند التعذّر.
        var activatedByName = await _db.Users
            .AsNoTracking()
            .Where(u => u.Id == userId)
            .Select(u => u.FullName)
            .FirstOrDefaultAsync(ct);

        // اسم الفني المرتبط (عند التحصيل «فني») — من نفس شركة الحساب (دفاع بالعمق)؛ null عند التعذّر.
        var isTechnician = collectionType == "technician";
        var linkedTechnicianId = isTechnician ? req.LinkedTechnicianId : null;
        string? technicianName = null;
        if (isTechnician && linkedTechnicianId.HasValue && linkedTechnicianId.Value != Guid.Empty)
        {
            technicianName = await _db.Users
                .AsNoTracking()
                .Where(u => u.Id == linkedTechnicianId.Value && u.CompanyId == account.CompanyId)
                .Select(u => u.FullName)
                .FirstOrDefaultAsync(ct);
        }

        var log = new SubscriptionLog
        {
            Source = SubscriptionLogSource.Sas,
            SasAccountId = account.Id,
            SubscriberUid = uid,
            SubscriberUsername = Trim(req.SubscriberUsername) ?? ParseUsername(actionRaw),
            PlanName = planName ?? Trim(req.ProfileId),
            OperationType = opType,
            CollectionType = collectionType,
            BasePrice = basePrice,
            CompanyDiscount = 0,
            MaintenanceFee = maintenanceFee,
            ManualDiscount = manualDiscount,
            SystemDiscountEnabled = req.SystemDiscountEnabled,
            // PlanPrice = basePrice ليستخدمه فرع البديل في RecordAsync عند basePrice=0 بنفس النتيجة.
            PlanPrice = basePrice,
            PhoneNumber = safePhone,
            CommitmentPeriod = months,
            Currency = "IQD",
            CompanyId = account.CompanyId,
            UserId = account.OwnerUserId,
            FtthTransactionId = transactionId,
            SessionId = transactionId,
            LinkedAgentId = collectionType == "agent" ? req.LinkedAgentId : null,
            // التوجيه «فني»: ربط الفني + اسمه (لعرضه في سجل الحركات وتقارير الإسناد).
            LinkedTechnicianId = linkedTechnicianId,
            TechnicianName = technicianName,
            // اسم المشغّل المنفّذ للعملية (المتصل) — لعرض عمود «نفّذ بواسطة».
            ActivatedBy = activatedByName,
            ActivationDate = DateTime.UtcNow,
            SubscriptionNotes = note,
            // الإجراء الخام (activate|extend|changeProfile) مخزَّن حرفياً لعرضه في سجل الحركات بلا migration.
            ReconciliationNotes = action
        };

        await _unitOfWork.SubscriptionLogs.AddAsync(log, ct);
        await _unitOfWork.SaveChangesAsync(ct);

        // القيد المحاسبي — لا يُسقط السجل عند الفشل (try/catch كما FTTH).
        Guid? journalEntryId = null;
        try
        {
            var input = new Sadara.API.Services.SubscriptionAccountingInput
            {
                BasePrice = basePrice,
                CompanyDiscount = 0,
                ManualDiscount = manualDiscount,
                MaintenanceFee = maintenanceFee,
                // PlanPrice = basePrice (فرع البديل في RecordAsync عند basePrice=0) — يُنتج نفس collectedAmount.
                PlanPrice = basePrice,
                SystemDiscountEnabled = req.SystemDiscountEnabled,
                CollectionType = collectionType,
                LinkedAgentId = collectionType == "agent" ? req.LinkedAgentId : null,
                // التوجيه «فني»: يمرَّر LinkedTechnicianId ليعالجه المحرّك المحاسبي (مدين 1140 + TechnicianTransaction).
                LinkedTechnicianId = linkedTechnicianId,
                // الذمة تُقيَّد على المشترك نفسه بمفتاح (SasAccountId:SubscriberUid) عند collectionType=citizen.
                CitizenKey = collectionType == "citizen" ? CitizenKey(account.Id, uid) : null,
                PlanName = log.PlanName,
                CustomerName = log.SubscriberUsername,
                OperationType = opType,
                EntryDate = log.ActivationDate
            };

            journalEntryId = await _accounting.RecordAsync(log, input, account.CompanyId, account.OwnerUserId, ct);
            if (journalEntryId.HasValue)
            {
                log.JournalEntryId = journalEntryId;
                _unitOfWork.SubscriptionLogs.Update(log);
                await _unitOfWork.SaveChangesAsync(ct);
            }
        }
        catch (Exception exAcc)
        {
            _logger.LogWarning(exAcc, "فشل إنشاء القيد المحاسبي لسجل الساس {LogId} — السجل حُفظ بدونه", log.Id);
        }

        var receipt = new
        {
            operationType = action switch
            {
                "activate" => "تم تفعيل اشتراك",
                "extend" => "تم تجديد الاشتراك",
                "changeProfile" => "تم تغيير الباقة",
                _ => "عملية اشتراك"
            },
            subscriberUsername = log.SubscriberUsername,
            planName = log.PlanName,
            months,
            basePrice,
            maintenanceFee,
            manualDiscount,
            collectedAmount,
            currency = "IQD",
            collectionType,
            transactionId,
            activatedByUserId = account.OwnerUserId
        };

        return SasBilledResult.AsSuccess(log.Id, journalEntryId, receipt, transactionId);
    }

    /// <summary>الحد الأقصى المعقول لحجم دفعة التجديد الجماعي المفوتر (حماية من الإساءة/الحمل).</summary>
    private const int MaxBulkBilledBatch = 300;

    /// <summary>
    /// تجديد/تفعيل جماعي مفوتر — نفس خطّ <see cref="ActivateBilled"/> لكل مشترك (قيد موحّد Source=Sas) — كتابة (manage).
    ///
    /// العزل: <see cref="GetOwnedAccountAsync"/> مرّة واحدة (شركة + مالك + غير محذوف) + فكّ التشفير مرّة واحدة.
    /// لكل uid: <see cref="ActivateBilledCoreAsync"/> بمعرّف عملية فريد مولّد خادمياً (idempotency مستقلّ لكل مشترك).
    /// نجاح جزئي: فشل مشترك (استثناء/502) لا يوقف الباقي؛ تُجمَع النتائج.
    ///
    /// ⚠️ لا أسرار في الرد؛ companyId/userId/accountId مختومة من الحساب خادمياً (لا من العميل).
    /// </summary>
    [HttpPost("accounts/{id}/renewal/bulk-billed")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> BulkRenewalBilled(
        Guid id,
        [FromBody] SasBulkBilledRequest request,
        CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied))
            return denied!;

        if (request == null || request.SubscriberIds == null || request.SubscriberIds.Count == 0)
            return BadRequest(new { success = false, message = "قائمة المشتركين مطلوبة" });

        // قائمة سماح صارمة للإجراء (التجديد الجماعي يدعم التفعيل/التمديد فقط — لا تغيير باقة جماعي هنا).
        var action = string.IsNullOrWhiteSpace(request.Action) ? "extend" : request.Action.Trim();
        if (action is not ("activate" or "extend"))
            return BadRequest(new { success = false, message = "إجراء غير مدعوم للتجديد الجماعي (المتاح: activate | extend)" });

        // قائمة سماح لنوع التحصيل (مطابق لمنطق المحاسبة الموحّد). «citizen» = آجل على ذمة المشترك (دفتر الذمم).
        var collectionType = string.IsNullOrWhiteSpace(request.CollectionType)
            ? "cash"
            : request.CollectionType.Trim().ToLowerInvariant();
        if (collectionType is not ("cash" or "credit" or "agent" or "citizen" or "technician"))
            return BadRequest(new { success = false, message = "نوع تحصيل غير مدعوم (المتاح: cash | credit | agent | citizen | technician)" });

        if (collectionType == "agent" && (!request.LinkedAgentId.HasValue || request.LinkedAgentId.Value == Guid.Empty))
            return BadRequest(new { success = false, message = "يجب تحديد الوكيل عند اختيار نوع التحصيل 'وكيل'" });

        if (collectionType == "technician" && (!request.LinkedTechnicianId.HasValue || request.LinkedTechnicianId.Value == Guid.Empty))
            return BadRequest(new { success = false, message = "يجب تحديد الفني عند اختيار نوع التحصيل 'فني'" });

        // تحقّق المدة (مطلوبة للتفعيل/التمديد).
        var months = request.Months;
        if (!months.HasValue || months.Value <= 0 || months.Value > 60)
            return BadRequest(new { success = false, message = "عدد الأشهر غير صالح (1..60)" });

        // تنظيف المعرّفات: تفريغ الفارغ + قصّ + إزالة التكرار.
        var subscriberIds = request.SubscriberIds
            .Where(s => !string.IsNullOrWhiteSpace(s))
            .Select(s => s.Trim())
            .Distinct(StringComparer.Ordinal)
            .ToList();

        if (subscriberIds.Count == 0)
            return BadRequest(new { success = false, message = "قائمة المشتركين مطلوبة" });

        if (subscriberIds.Count > MaxBulkBilledBatch)
            return BadRequest(new { success = false, message = $"حجم الدفعة يتجاوز الحد المسموح ({MaxBulkBilledBatch})" });

        // العزل الصارم + فكّ التشفير مرّة واحدة في الذاكرة فقط.
        var account = await GetOwnedAccountAsync(id, companyId, userId, ct);
        if (account == null)
            return NotFound(new { success = false, message = "حساب الساس غير موجود" });

        string password;
        try
        {
            password = _secretProtector.Unprotect(account.PasswordEncrypted); // في الذاكرة فقط
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "تعذّر فكّ تشفير اعتماد الحساب للتجديد الجماعي المفوتر");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }

        var results = new List<object>(subscriberIds.Count);
        var succeeded = 0;
        var failed = 0;

        foreach (var uid in subscriberIds)
        {
            // معرّف عملية فريد لكل مشترك (idempotency مستقلّ) — لا يُعتمد على العميل.
            var perReq = new SasActivateBilledRequest(
                Action: action,
                Months: months,
                ProfileId: string.IsNullOrWhiteSpace(request.ProfileId) ? null : request.ProfileId.Trim(),
                CollectionType: collectionType,
                MaintenanceFee: request.MaintenanceFee,
                ManualDiscount: request.ManualDiscount,
                SystemDiscountEnabled: request.SystemDiscountEnabled,
                LinkedAgentId: collectionType == "agent" ? request.LinkedAgentId : null,
                LinkedTechnicianId: collectionType == "technician" ? request.LinkedTechnicianId : null,
                Phone: null,
                SubscriberUsername: null,
                TransactionId: Guid.NewGuid().ToString("N"),
                Note: null);

            try
            {
                var core = await ActivateBilledCoreAsync(account, uid, perReq, companyId, userId, password, ct);

                if (core.Ok)
                {
                    succeeded++;
                    results.Add(new
                    {
                        uid,
                        ok = true,
                        message = (string?)null,
                        logId = core.LogId,
                        journalEntryId = core.JournalEntryId,
                        receipt = core.Receipt
                    });
                }
                else
                {
                    // فشل منطقي (502 من الساس أو تكرار idempotency) — لا يوقف الباقي.
                    failed++;
                    results.Add(new
                    {
                        uid,
                        ok = false,
                        message = core.Message ?? "فشل تنفيذ العملية",
                        logId = (long?)null,
                        journalEntryId = (Guid?)null,
                        receipt = (object?)null
                    });
                }
            }
            catch (SasServiceUnavailableException ex)
            {
                // خدمة الساس غير متاحة لهذا المشترك — نُكمل الباقي (نجاح جزئي).
                _logger.LogWarning(ex, "خدمة الساس غير متاحة أثناء التجديد الجماعي للمشترك {Uid}", uid);
                failed++;
                results.Add(new
                {
                    uid,
                    ok = false,
                    message = "خدمة الساس غير متاحة حالياً",
                    logId = (long?)null,
                    journalEntryId = (Guid?)null,
                    receipt = (object?)null
                });
            }
            catch (Exception ex)
            {
                // خطأ غير متوقّع لهذا المشترك — نعزله ونُكمل الباقي.
                _logger.LogError(ex, "خطأ غير متوقّع أثناء التجديد الجماعي للمشترك {Uid}", uid);
                failed++;
                results.Add(new
                {
                    uid,
                    ok = false,
                    message = "خطأ داخلي",
                    logId = (long?)null,
                    journalEntryId = (Guid?)null,
                    receipt = (object?)null
                });
            }
        }

        return Ok(new
        {
            success = true,
            total = subscriberIds.Count,
            succeeded,
            failed,
            results
        });
    }

    /// <summary>الحد الأقصى لعدد سجلات الحركات المُعادة في صفحة واحدة.</summary>
    private const int MaxTransactionsPageSize = 200;

    /// <summary>
    /// سجل حركات حساب ساس — قراءة من الدفتر الموحّد (<c>SubscriptionLogs</c>) بلا جدول جديد — قراءة (view).
    ///
    /// العزل: <see cref="GetOwnedAccountAsync"/> (الحساب مملوك) ثم فلترة <c>SasAccountId == account.Id</c>
    /// و<c>Source == Sas</c> و<c>CompanyId == account.CompanyId</c> (دفاع بالعمق). ترتيب تنازلي بـ CreatedAt، صفحات.
    ///
    /// «action»: مخزَّن حرفياً في <c>ReconciliationNotes</c> لحظة الإنشاء (activate|extend|changeProfile)؛
    /// إن غاب (سجلّات قديمة) يُشتق من <c>OperationType</c> (purchase⇒activate، وإلا extend).
    ///
    /// ⚠️ بلا أسرار: لا كلمة مرور ولا اعتماد؛ حقول محاسبية/عرض فقط.
    /// </summary>
    [HttpGet("accounts/{id}/transactions")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> GetTransactions(
        Guid id,
        [FromQuery] int limit = 50,
        [FromQuery] int offset = 0,
        CancellationToken ct = default)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied))
            return denied!;

        // قصّ آمن للصفحات.
        var safeLimit = Math.Clamp(limit, 1, MaxTransactionsPageSize);
        var safeOffset = Math.Max(0, offset);

        var account = await GetOwnedAccountAsync(id, companyId, userId, ct);
        if (account == null)
            return NotFound(new { success = false, message = "حساب الساس غير موجود" });

        try
        {
            // الاستعلام الأساس: سجلات الساس لهذا الحساب ضمن الشركة (دفاع بالعمق فوق SasAccountId).
            var baseQuery = _unitOfWork.SubscriptionLogs.AsQueryable()
                .Where(l => l.SasAccountId == account.Id
                            && l.Source == SubscriptionLogSource.Sas
                            && l.CompanyId == account.CompanyId);

            var total = await baseQuery.CountAsync(ct);

            var rows = await baseQuery
                .OrderByDescending(l => l.CreatedAt)
                .Skip(safeOffset)
                .Take(safeLimit)
                .Select(l => new
                {
                    l.Id,
                    l.CreatedAt,
                    l.ReconciliationNotes,
                    l.OperationType,
                    l.SubscriberUid,
                    l.SubscriberUsername,
                    l.PlanName,
                    l.BasePrice,
                    l.PlanPrice,
                    l.Currency,
                    l.CollectionType,
                    l.PaymentStatus,
                    l.JournalEntryId,
                    l.ActivatedBy,
                    l.TechnicianName,
                    l.LinkedAgentId
                })
                .ToListAsync(ct);

            // أسماء الوكلاء المرتبطين (إن وُجدوا) دفعةً واحدة ضمن شركة الحساب (دفاع بالعمق).
            var agentIds = rows
                .Where(r => r.LinkedAgentId.HasValue && r.LinkedAgentId.Value != Guid.Empty)
                .Select(r => r.LinkedAgentId!.Value)
                .Distinct()
                .ToList();
            var agentNames = agentIds.Count == 0
                ? new Dictionary<Guid, string>()
                : await _db.Agents
                    .AsNoTracking()
                    .Where(a => agentIds.Contains(a.Id) && a.CompanyId == account.CompanyId)
                    .ToDictionaryAsync(a => a.Id, a => a.Name, ct);

            var data = rows.Select(l => new
            {
                id = l.Id,
                createdAt = l.CreatedAt,
                // «action» الصريح من ReconciliationNotes، وإلا يُشتق من OperationType.
                action = !string.IsNullOrWhiteSpace(l.ReconciliationNotes)
                    ? l.ReconciliationNotes
                    : (string.Equals(l.OperationType, "purchase", StringComparison.OrdinalIgnoreCase) ? "activate" : "extend"),
                subscriberUid = l.SubscriberUid,
                subscriberUsername = l.SubscriberUsername,
                planName = l.PlanName,
                basePrice = l.BasePrice,
                collectedAmount = l.PlanPrice,
                currency = l.Currency ?? "IQD",
                collectionType = l.CollectionType,
                status = l.PaymentStatus,
                journalEntryId = l.JournalEntryId,
                // أعمدة الإسناد: المشغّل المنفّذ + اسم الفني (عند «فني») + اسم الوكيل (عند «وكيل»).
                activatedBy = l.ActivatedBy,
                technicianName = l.TechnicianName,
                agentName = (l.LinkedAgentId.HasValue && agentNames.TryGetValue(l.LinkedAgentId.Value, out var an)) ? an : null
            }).ToList();

            return Ok(new { success = true, total, data });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب سجل حركات حساب الساس");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// وسم سجل اشتراك ساس بأن رسالة واتساب أُرسلت فعلاً — كتابة (manage).
    ///
    /// العزل: <see cref="GetOwnedAccountAsync"/> (الحساب مملوك: شركة + مالك + غير محذوف) ثم مطابقة صارمة للسجل
    /// (<c>Source == Sas</c> و<c>SasAccountId == account.Id</c> و<c>CompanyId == account.CompanyId</c> — دفاع بالعمق).
    ///
    /// idempotent: إن كان <c>IsWhatsAppSent</c> مضبوطاً مسبقاً يعيد success دون كتابة أو خطأ.
    /// </summary>
    [HttpPost("accounts/{id}/subscription-logs/{logId}/whatsapp-sent")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public async Task<IActionResult> MarkSubscriptionLogWhatsAppSent(
        Guid id,
        long logId,
        CancellationToken ct = default)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied))
            return denied!;

        var account = await GetOwnedAccountAsync(id, companyId, userId, ct);
        if (account == null)
            return NotFound(new { success = false, message = "حساب الساس غير موجود" });

        try
        {
            // مطابقة صارمة: سجل ساس لهذا الحساب ضمن الشركة (دفاع بالعمق فوق المفتاح).
            var log = await _unitOfWork.SubscriptionLogs.AsQueryable()
                .FirstOrDefaultAsync(
                    l => l.Id == logId
                         && l.Source == SubscriptionLogSource.Sas
                         && l.SasAccountId == account.Id
                         && l.CompanyId == account.CompanyId,
                    ct);

            if (log == null)
                return NotFound(new { success = false, message = "السجل غير موجود" });

            // idempotent: إن كان مضبوطاً مسبقاً نعيد النجاح دون كتابة.
            if (!log.IsWhatsAppSent)
            {
                log.IsWhatsAppSent = true;
                _unitOfWork.SubscriptionLogs.Update(log);
                await _unitOfWork.SaveChangesAsync(ct);
            }

            return Ok(new { success = true });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في وسم سجل اشتراك الساس بإرسال واتساب");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>تنفيذ إجراء جماعي على مشتركين — كتابة (manage).</summary>
    [HttpPost("accounts/{id}/users/bulk-action")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> UsersBulkAction(Guid id, [FromBody] SasBulkActionRequest request, CancellationToken ct)
    {
        if (request == null || string.IsNullOrWhiteSpace(request.Action))
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "الإجراء مطلوب" }));

        if (request.Uids == null || request.Uids.Count == 0)
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "قائمة المشتركين مطلوبة" }));

        if (request.Uids.Count > 1000)
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "حجم الدفعة يتجاوز الحد المسموح" }));

        var uids = request.Uids
            .Where(s => !string.IsNullOrWhiteSpace(s))
            .Select(s => s.Trim())
            .Distinct(StringComparer.Ordinal)
            .ToList();

        if (uids.Count == 0)
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "قائمة المشتركين مطلوبة" }));

        return PassThroughWriteAsync(id, (acc, pwd, token) =>
            _sasClient.UsersBulkActionAsync(acc.ServerUrl, acc.Username, pwd, uids, request.Action.Trim(), request.Params, token), ct);
    }

    /// <summary>إنشاء مشترك جديد — كتابة (manage).</summary>
    [HttpPost("accounts/{id}/users/create")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> CreateUser(Guid id, [FromBody] SasPayloadRequest request, CancellationToken ct)
    {
        if (request?.Payload == null)
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "بيانات المشترك مطلوبة" }));

        return PassThroughWriteAsync(id, (acc, pwd, token) =>
            _sasClient.CreateUserAsync(acc.ServerUrl, acc.Username, pwd, request.Payload.Value, token), ct);
    }

    /// <summary>تعديل مشترك — كتابة (manage).</summary>
    [HttpPut("accounts/{id}/users/{uid}")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> UpdateUser(Guid id, string uid, [FromBody] SasPayloadRequest request, CancellationToken ct)
    {
        if (request?.Payload == null)
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "بيانات التعديل مطلوبة" }));

        return PassThroughWriteAsync(id, (acc, pwd, token) =>
            _sasClient.UpdateUserAsync(acc.ServerUrl, acc.Username, pwd, uid, request.Payload.Value, token), ct);
    }

    /// <summary>حذف مشترك — كتابة (manage).</summary>
    [HttpDelete("accounts/{id}/users/{uid}")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> DeleteUser(Guid id, string uid, CancellationToken ct)
        => PassThroughWriteAsync(id, (acc, pwd, token) =>
            _sasClient.DeleteUserAsync(acc.ServerUrl, acc.Username, pwd, uid, token), ct);

    /// <summary>بيانات استرداد رصيد/داتا لمشترك (تحضير) — كتابة (manage).</summary>
    [HttpPost("accounts/{id}/users/{uid}/refund-data")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetUserRefundData(Guid id, string uid, CancellationToken ct)
        => PassThroughWriteAsync(id, (acc, pwd, token) =>
            _sasClient.GetUserRefundDataAsync(acc.ServerUrl, acc.Username, pwd, uid, token), ct);

    /// <summary>تنفيذ استرداد لمشترك — كتابة (manage).</summary>
    [HttpPost("accounts/{id}/users/{uid}/refund")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> RefundUser(Guid id, string uid, CancellationToken ct)
        => PassThroughWriteAsync(id, (acc, pwd, token) =>
            _sasClient.RefundUserAsync(acc.ServerUrl, acc.Username, pwd, uid, token), ct);

    // ---------- المتصلون: قراءة (view) ----------

    /// <summary>قائمة المتصلين حالياً من خدمة الساس — قراءة (view).</summary>
    [HttpGet("accounts/{id}/online")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetOnline(Guid id, CancellationToken ct)
        => PassThroughAsync(id, (acc, pwd, token) =>
            _sasClient.GetOnlineAsync(acc.ServerUrl, acc.Username, pwd, token), null, ct);

    // ---------- الوكلاء/المدراء ----------

    /// <summary>قائمة الوكلاء/المدراء من خدمة الساس — قراءة (view).</summary>
    [HttpGet("accounts/{id}/managers")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetManagers(Guid id, CancellationToken ct)
        => PassThroughAsync(id, (acc, pwd, token) =>
            _sasClient.GetManagersAsync(acc.ServerUrl, acc.Username, pwd, token), null, ct);

    /// <summary>تنفيذ إجراء على وكيل/مدير — كتابة (manage).</summary>
    [HttpPost("accounts/{id}/managers/{mid}/action")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> ManagerAction(Guid id, string mid, [FromBody] SasActionRequest request, CancellationToken ct)
    {
        if (request == null || string.IsNullOrWhiteSpace(request.Action))
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "الإجراء مطلوب" }));

        return PassThroughWriteAsync(id, (acc, pwd, token) =>
            _sasClient.ManagerActionAsync(acc.ServerUrl, acc.Username, pwd, mid, request.Action.Trim(), request.Params, token), ct);
    }

    /// <summary>حذف وكيل/مدير — كتابة (manage).</summary>
    [HttpDelete("accounts/{id}/managers/{mid}")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> DeleteManager(Guid id, string mid, CancellationToken ct)
        => PassThroughWriteAsync(id, (acc, pwd, token) =>
            _sasClient.DeleteManagerAsync(acc.ServerUrl, acc.Username, pwd, mid, token), ct);

    // ---------- البروكسي العام لـ SAS ----------

    /// <summary>بروكسي عام GET لأي مسار ساس (path في الاستعلام) — قراءة (view).</summary>
    [HttpGet("accounts/{id}/sas/get")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> SasGet(Guid id, [FromQuery] string path, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(path))
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "المسار مطلوب" }));

        var safePath = path.Length > MaxSasPathLength ? path[..MaxSasPathLength] : path;
        return PassThroughAsync(id, (acc, pwd, token) =>
            _sasClient.SasGetAsync(acc.ServerUrl, acc.Username, pwd, safePath.Trim(), token), null, ct);
    }

    /// <summary>بروكسي عام POST لأي مسار ساس — كتابة (manage).</summary>
    [HttpPost("accounts/{id}/sas/post")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> SasPost(Guid id, [FromBody] SasProxyPostRequest request, CancellationToken ct)
    {
        if (request == null || string.IsNullOrWhiteSpace(request.Path))
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "المسار مطلوب" }));

        var safePath = request.Path.Length > MaxSasPathLength ? request.Path[..MaxSasPathLength] : request.Path;
        return PassThroughWriteAsync(id, (acc, pwd, token) =>
            _sasClient.SasPostAsync(acc.ServerUrl, acc.Username, pwd, safePath.Trim(), request.Payload, token), ct);
    }

    /// <summary>الحد الأقصى لطول مسار البروكسي العام الممرَّر لخدمة الساس.</summary>
    private const int MaxSasPathLength = 512;

    // ==================== البلنك/التصريح + المزامنة المحلية + المقاطعة + اختبار الاتصال ====================
    // كل النقاط أدناه account-scoped، تمرّ عبر GetOwnedAccountAsync للعزل الثلاثي (شركة + مالك + غير محذوف).
    // accountId المُمرَّر للخدمة = account.Id (الحساب المملوك، لا من إدخال المستخدم).
    // companyId = account.CompanyId، ownerUserId = account.OwnerUserId — لعزل التخزين المحلي بـ account_id.
    // النقاط التي تحتاج ساس (test/sync/reconciliation) تفكّ التشفير في الذاكرة فقط؛ نقاط التخزين المحلي
    // (subscribers-local/reports) لا تفكّ التشفير ولا تمرّر اعتماداً إطلاقاً. كلها failClosed:true.

    /// <summary>
    /// اختبار اتصال الحساب بنظام الساس — قراءة (view). يفكّ التشفير في الذاكرة فقط ويمرّره للخدمة.
    /// يعيد <c>{ok, message, subscribers_count?}</c> خاماً. لا تخزين محلي.
    /// </summary>
    [HttpPost("accounts/{id}/test")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> TestAccount(Guid id, CancellationToken ct)
        => PassThroughAsync(id, (acc, pwd, token) =>
            _sasClient.TestAccountAsync(acc.ServerUrl, acc.Username, pwd, token), null, ct);

    /// <summary>
    /// مزامنة محلية لمشتركي الحساب من الساس إلى التخزين المحلي — كتابة محلية (manage).
    /// يمرّر <c>accountId = account.Id</c> لعزل التخزين المحلي. يعيد <c>{count, expiry, synced_at}</c> خاماً.
    /// </summary>
    [HttpPost("accounts/{id}/sync")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> SyncAccount(Guid id, CancellationToken ct)
        => PassThroughWriteAsync(id, (acc, pwd, token) =>
            _sasClient.SyncAccountAsync(acc.ServerUrl, acc.Username, pwd, acc.Id.ToString(), token), ct);

    /// <summary>
    /// جلب المشتركين من التخزين المحلي المعزول بـ accountId — قراءة (view). بلا اعتماد ساس (لا فكّ تشفير).
    /// يمرّر <c>accountId = account.Id</c> فقط للخدمة المحلية.
    /// </summary>
    [HttpGet("accounts/{id}/subscribers-local")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetLocalSubscribers(
        Guid id,
        [FromQuery] string? search = null,
        [FromQuery] string? status = null,
        [FromQuery] string? profile = null,
        [FromQuery] string? expiring = null,
        [FromQuery] int? page = null,
        [FromQuery] int? count = null,
        CancellationToken ct = default)
    {
        // قصّ آمن للوسائط النصّية والعددية قبل التمرير.
        var safeSearch = Trim(search);
        var safeStatus = Trim(status);
        var safeProfile = Trim(profile);
        var safePage = page.HasValue ? Math.Clamp(page.Value, 1, 100000) : (int?)null;
        var safeCount = count.HasValue ? Math.Clamp(count.Value, 1, 1000) : (int?)null;

        return LocalPassThroughAsync(id, (acc, token) =>
            _sasClient.GetLocalSubscribersAsync(
                acc.Id.ToString(), safeSearch, safeStatus, safeProfile, expiring, safePage, safeCount, token), ct);
    }

    /// <summary>
    /// ملخّص مشتركي الحساب من التخزين المحلي المعزول بـ accountId — قراءة (view). بلا اعتماد ساس (لا فكّ تشفير).
    /// يمرّر <c>accountId = account.Id</c> فقط للخدمة المحلية، ويعيد ردّها خاماً
    /// <c>{ total, active, expired, online, expiry:{overdue,today,soon3,soon7}, last_sync }</c> كما هو.
    /// </summary>
    [HttpGet("accounts/{id}/subscribers/summary")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetSubscribersSummary(Guid id, CancellationToken ct)
        => LocalPassThroughAsync(id, (acc, token) =>
            _sasClient.GetSubscribersSummaryAsync(acc.Id.ToString(), token), ct);

    /// <summary>
    /// تقديم تصريح/بلنك شهري — كتابة محلية (manage). معزول بـ accountId + companyId + ownerUserId.
    /// يمرّر <c>accountId=account.Id</c> و<c>companyId=account.CompanyId</c> و<c>ownerUserId=account.OwnerUserId</c>.
    /// </summary>
    [HttpPost("accounts/{id}/report")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> SubmitReport(Guid id, [FromBody] SubmitReportRequest request, CancellationToken ct)
    {
        if (request == null)
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "بيانات التصريح مطلوبة" }));

        if (request.DeclaredTotal < 0 || request.DeclaredActive < 0)
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "قيم التصريح غير صالحة" }));

        if (request.DeclaredActive > request.DeclaredTotal)
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "الفعّالون لا يتجاوزون الإجمالي" }));

        var note = Trim(request.Note);

        // submittedBy من هوية المستخدم الحالي (تدقيق) — لا من إدخال العميل.
        var submittedBy = GetCurrentUserId().ToString();

        return LocalPassThroughAsync(id, (acc, token) =>
            _sasClient.SubmitReportAsync(
                acc.Id.ToString(),
                acc.CompanyId.ToString(),
                acc.OwnerUserId.ToString(),
                request.DeclaredTotal,
                request.DeclaredActive,
                note,
                submittedBy,
                token), ct);
    }

    /// <summary>
    /// قائمة تصاريح/بلنكات الحساب من التخزين المحلي المعزول بـ accountId — قراءة (view). بلا اعتماد.
    /// </summary>
    [HttpGet("accounts/{id}/reports")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> ListReports(Guid id, CancellationToken ct)
        => LocalPassThroughAsync(id, (acc, token) =>
            _sasClient.ListReportsAsync(acc.Id.ToString(), token), ct);

    /// <summary>
    /// المقاطعة/المطابقة بين المُصرَّح والفعلي — قراءة (view). تفكّ التشفير في الذاكرة فقط لجلب الفعلي.
    /// يمرّر <c>accountId=account.Id</c> + الاعتماد. يعيد <c>{declared, actual, diff, verdict}</c> خاماً.
    /// </summary>
    [HttpGet("accounts/{id}/reconciliation")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetReconciliation(Guid id, CancellationToken ct)
        => PassThroughAsync(id, (acc, pwd, token) =>
            _sasClient.GetReconciliationAsync(acc.Id.ToString(), acc.ServerUrl, acc.Username, pwd, token), null, ct);

    // ==================== التذاكر (user-scoped — تخصّ الوكيل لا حساب ساس) ====================
    // على عكس نقاط الحساب أعلاه، هذه النقاط لا تمرّ عبر GetOwnedAccountAsync ولا تلمس أي حساب ساس.
    // العزل يُشتق مباشرةً من التوكن عبر TryResolveScope:
    //   companyId  = tenant.CompanyId (يرفض SuperAdmin/بلا شركة عبر Forbid)
    //   ownerUserId= currentUserId (المستخدم المالك)
    // لا يؤخذ companyId/ownerUserId من إدخال المستخدم إطلاقاً. لا اعتماد ساس ولا فكّ تشفير.
    // القراءات: view · الكتابات: manage — كلها failClosed:true.

    /// <summary>إحصاءات تذاكر الوكيل الحالي — قراءة (view). معزولة بـ company+owner من التوكن.</summary>
    [HttpGet("tickets/stats")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetTicketsStats(CancellationToken ct)
        => TicketsPassThroughAsync((companyId, ownerUserId, token) =>
            _sasClient.GetTicketsStatsAsync(companyId, ownerUserId, token), ct);

    /// <summary>قائمة تذاكر الوكيل الحالي (status/category/search/page/count) — قراءة (view).</summary>
    [HttpGet("tickets")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetTickets(
        [FromQuery] string? status = null,
        [FromQuery] string? category = null,
        [FromQuery] string? search = null,
        [FromQuery] int? page = null,
        [FromQuery] int? count = null,
        CancellationToken ct = default)
    {
        // قصّ آمن للوسائط النصّية والعددية قبل التمرير.
        var safeStatus = Trim(status);
        var safeCategory = Trim(category);
        var safeSearch = Trim(search);
        var safePage = page.HasValue ? Math.Clamp(page.Value, 1, 100000) : (int?)null;
        var safeCount = count.HasValue ? Math.Clamp(count.Value, 1, 1000) : (int?)null;

        return TicketsPassThroughAsync((companyId, ownerUserId, token) =>
            _sasClient.GetTicketsListAsync(
                companyId, ownerUserId, safeStatus, safeCategory, safeSearch, safePage, safeCount, token), ct);
    }

    /// <summary>تفاصيل تذكرة محدّدة تخصّ الوكيل الحالي — قراءة (view).</summary>
    [HttpGet("tickets/{ticketId}")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetTicket(string ticketId, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(ticketId))
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "معرّف التذكرة مطلوب" }));

        var safeTicketId = ticketId.Trim();
        return TicketsPassThroughAsync((companyId, ownerUserId, token) =>
            _sasClient.GetTicketAsync(companyId, ownerUserId, safeTicketId, token), ct);
    }

    /// <summary>إنشاء تذكرة جديدة للوكيل الحالي — كتابة (manage). created_by من الهوية خادمياً.</summary>
    [HttpPost("tickets")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> CreateTicket([FromBody] SasAgentCreateTicketRequest request, CancellationToken ct)
    {
        if (request == null || string.IsNullOrWhiteSpace(request.Subject) || string.IsNullOrWhiteSpace(request.Body))
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "العنوان والنصّ مطلوبان" }));

        var subject = request.Subject.Trim();
        var body = request.Body.Trim();
        var category = Trim(request.Category);
        var priority = Trim(request.Priority);
        var subscriberRef = Trim(request.SubscriberRef);

        return TicketsPassThroughAsync((companyId, ownerUserId, token) =>
            _sasClient.CreateTicketAsync(
                companyId,
                ownerUserId,
                subject,
                body,
                category,
                priority,
                subscriberRef,
                // created_by من هوية المستخدم الحالي (تدقيق) — لا من إدخال العميل.
                ownerUserId,
                token), ct);
    }

    /// <summary>إضافة ردّ على تذكرة تخصّ الوكيل الحالي — كتابة (manage). author من الهوية خادمياً.</summary>
    [HttpPost("tickets/{ticketId}/reply")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> ReplyTicket(string ticketId, [FromBody] SasAgentReplyTicketRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(ticketId))
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "معرّف التذكرة مطلوب" }));

        if (request == null || string.IsNullOrWhiteSpace(request.Body))
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "نصّ الردّ مطلوب" }));

        var safeTicketId = ticketId.Trim();
        var body = request.Body.Trim();

        return TicketsPassThroughAsync((companyId, ownerUserId, token) =>
            _sasClient.ReplyTicketAsync(
                companyId,
                ownerUserId,
                safeTicketId,
                body,
                request.IsInternal,
                // author من هوية المستخدم الحالي (تدقيق) — لا من إدخال العميل.
                ownerUserId,
                token), ct);
    }

    /// <summary>تحديث تذكرة تخصّ الوكيل الحالي (status/priority/category) — كتابة (manage).</summary>
    [HttpPatch("tickets/{ticketId}")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> UpdateTicket(string ticketId, [FromBody] SasAgentUpdateTicketRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(ticketId))
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "معرّف التذكرة مطلوب" }));

        if (request == null)
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "بيانات التحديث مطلوبة" }));

        var safeTicketId = ticketId.Trim();
        var status = Trim(request.Status);
        var priority = Trim(request.Priority);
        var category = Trim(request.Category);

        if (status == null && priority == null && category == null)
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "لا يوجد حقل للتحديث" }));

        return TicketsPassThroughAsync((companyId, ownerUserId, token) =>
            _sasClient.UpdateTicketAsync(
                companyId, ownerUserId, safeTicketId, status, priority, category, token), ct);
    }

    // ==================== العقارات (Premises — user-scoped: شركة + مالك) ====================
    // مثل التذاكر تماماً: لا تمرّ عبر GetOwnedAccountAsync ولا تلمس أي حساب ساس.
    // العزل يُشتق مباشرةً من التوكن عبر UserScopedPassThroughAsync (الذي يستدعي TryResolveScope):
    //   companyId  = tenant.CompanyId (يرفض SuperAdmin/بلا شركة عبر Forbid)
    //   ownerUserId= currentUserId (المستخدم المالك)
    // لا يؤخذ companyId/ownerUserId من إدخال المستخدم إطلاقاً. لا اعتماد ساس ولا فكّ تشفير.
    // القراءات: view · الكتابات: manage — كلها failClosed:true. قصّ آمن للمدخلات قبل التمرير.

    // ---------- العقارات: قراءات (view) ----------

    /// <summary>قائمة عقارات الوكيل الحالي (search/ownership/ptype/page/count) — قراءة (view).</summary>
    [HttpGet("premises")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetPremisesList(
        [FromQuery] string? search = null,
        [FromQuery] string? ownership = null,
        [FromQuery] string? ptype = null,
        [FromQuery] int? page = null,
        [FromQuery] int? count = null,
        CancellationToken ct = default)
    {
        // قصّ آمن للوسائط النصّية والعددية قبل التمرير.
        var safeSearch = Trim(search);
        var safeOwnership = Trim(ownership);
        var safePtype = Trim(ptype);
        var safePage = page.HasValue ? Math.Clamp(page.Value, 1, 100000) : (int?)null;
        var safeCount = count.HasValue ? Math.Clamp(count.Value, 1, 1000) : (int?)null;

        return UserScopedPassThroughAsync((companyId, ownerUserId, token) =>
            _sasClient.GetPremisesListAsync(
                companyId, ownerUserId, safeSearch, safeOwnership, safePtype, safePage, safeCount, token), ct);
    }

    /// <summary>تفاصيل عقار محدّد يخصّ الوكيل الحالي — قراءة (view).</summary>
    [HttpGet("premises/{pid}")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetPremises(string pid, CancellationToken ct)
    {
        if (!TryNormalizePremisesId(pid, out var safePid, out var bad))
            return Task.FromResult(bad!);

        return UserScopedPassThroughAsync((companyId, ownerUserId, token) =>
            _sasClient.GetPremisesAsync(companyId, ownerUserId, safePid, token), ct);
    }

    /// <summary>مشتركو عقار محدّد يخصّ الوكيل الحالي — قراءة (view).</summary>
    [HttpGet("premises/{pid}/subscribers")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetPremisesSubscribers(string pid, CancellationToken ct)
    {
        if (!TryNormalizePremisesId(pid, out var safePid, out var bad))
            return Task.FromResult(bad!);

        return UserScopedPassThroughAsync((companyId, ownerUserId, token) =>
            _sasClient.GetPremisesSubscribersAsync(companyId, ownerUserId, safePid, token), ct);
    }

    /// <summary>العقار المرتبط بمشترك محدّد يخصّ الوكيل الحالي — قراءة (view).</summary>
    [HttpGet("premises/by-subscriber/{sref}")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetPremisesBySubscriber(string sref, CancellationToken ct)
    {
        var safeRef = Trim(sref);
        if (safeRef == null)
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "مرجع المشترك مطلوب" }));

        return UserScopedPassThroughAsync((companyId, ownerUserId, token) =>
            _sasClient.GetPremisesBySubscriberAsync(companyId, ownerUserId, safeRef, token), ct);
    }

    /// <summary>مرشّحو الربط (مشتركون قابلون للربط بعقار) للوكيل الحالي (search اختياري) — قراءة (view).</summary>
    [HttpGet("premises/link-candidates")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetPremisesLinkCandidates([FromQuery] string? search = null, CancellationToken ct = default)
    {
        var safeSearch = Trim(search);
        return UserScopedPassThroughAsync((companyId, ownerUserId, token) =>
            _sasClient.GetPremisesLinkCandidatesAsync(companyId, ownerUserId, safeSearch, token), ct);
    }

    /// <summary>صورة عقار محدّد يخصّ الوكيل الحالي — قراءة (view). يُمرَّر JSON خام (يتضمّن الصورة/ext) كما تعيده الخدمة.</summary>
    [HttpGet("premises/{pid}/photo")]
    [RequirePermission("sas_agent", "view", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> GetPremisesPhoto(string pid, CancellationToken ct)
    {
        if (!TryNormalizePremisesId(pid, out var safePid, out var bad))
            return Task.FromResult(bad!);

        return UserScopedPassThroughAsync((companyId, ownerUserId, token) =>
            _sasClient.GetPremisesPhotoAsync(companyId, ownerUserId, safePid, token), ct);
    }

    // ---------- العقارات: كتابات (manage) ----------

    /// <summary>إنشاء عقار جديد للوكيل الحالي — كتابة (manage). created_by من الهوية خادمياً.</summary>
    [HttpPost("premises")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> CreatePremises([FromBody] PremisesCreateRequest request, CancellationToken ct)
    {
        if (request == null
            || string.IsNullOrWhiteSpace(request.Governorate)
            || string.IsNullOrWhiteSpace(request.Area)
            || string.IsNullOrWhiteSpace(request.Landmark))
            return Task.FromResult<IActionResult>(
                BadRequest(new { success = false, message = "المحافظة والمنطقة والنقطة الدالّة مطلوبة" }));

        if (!TryValidateCoordinates(request.Lat, request.Lon, out var coordError))
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = coordError }));

        var governorate = TrimRequired(request.Governorate);
        var area = TrimRequired(request.Area);
        var landmark = TrimRequired(request.Landmark);
        var phone = Trim(request.Phone);
        var ownership = Trim(request.Ownership);
        var ptype = Trim(request.Ptype);

        return UserScopedPassThroughAsync((companyId, ownerUserId, token) =>
            _sasClient.CreatePremisesAsync(
                companyId,
                ownerUserId,
                governorate!,
                area!,
                landmark!,
                request.Lat,
                request.Lon,
                phone,
                ownership,
                ptype,
                // created_by من هوية المستخدم الحالي (تدقيق) — لا من إدخال العميل.
                ownerUserId,
                token), ct);
    }

    /// <summary>تعديل عقار يخصّ الوكيل الحالي — كتابة (manage). كل الحقول اختيارية؛ يُرفض إن كانت كلها فارغة.</summary>
    [HttpPatch("premises/{pid}")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> UpdatePremises(string pid, [FromBody] PremisesUpdateRequest request, CancellationToken ct)
    {
        if (!TryNormalizePremisesId(pid, out var safePid, out var bad))
            return Task.FromResult(bad!);

        if (request == null)
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "بيانات التحديث مطلوبة" }));

        if (!TryValidateCoordinates(request.Lat, request.Lon, out var coordError))
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = coordError }));

        var governorate = Trim(request.Governorate);
        var area = Trim(request.Area);
        var landmark = Trim(request.Landmark);
        var phone = Trim(request.Phone);
        var ownership = Trim(request.Ownership);
        var ptype = Trim(request.Ptype);

        if (governorate == null && area == null && landmark == null && phone == null
            && ownership == null && ptype == null
            && !request.Lat.HasValue && !request.Lon.HasValue)
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "لا يوجد حقل للتحديث" }));

        return UserScopedPassThroughAsync((companyId, ownerUserId, token) =>
            _sasClient.UpdatePremisesAsync(
                companyId, ownerUserId, safePid,
                governorate, area, landmark, request.Lat, request.Lon, phone, ownership, ptype, token), ct);
    }

    /// <summary>حذف عقار يخصّ الوكيل الحالي — كتابة (manage).</summary>
    [HttpDelete("premises/{pid}")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> DeletePremises(string pid, CancellationToken ct)
    {
        if (!TryNormalizePremisesId(pid, out var safePid, out var bad))
            return Task.FromResult(bad!);

        return UserScopedPassThroughAsync((companyId, ownerUserId, token) =>
            _sasClient.DeletePremisesAsync(companyId, ownerUserId, safePid, token), ct);
    }

    /// <summary>رفع صورة عقار (base64) يخصّ الوكيل الحالي — كتابة (manage). حدّ حجم معقول + امتداد مسموح.</summary>
    [HttpPost("premises/{pid}/photo")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> UploadPremisesPhoto(string pid, [FromBody] PremisesPhotoUploadRequest request, CancellationToken ct)
    {
        if (!TryNormalizePremisesId(pid, out var safePid, out var bad))
            return Task.FromResult(bad!);

        if (request == null || string.IsNullOrWhiteSpace(request.ImageBase64))
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "بيانات الصورة مطلوبة" }));

        // تنظيف بادئة data URI إن وُجدت (data:image/png;base64,....) ثم إسقاط أي فراغات.
        var raw = request.ImageBase64.Trim();
        var commaIdx = raw.IndexOf(',');
        if (raw.StartsWith("data:", StringComparison.OrdinalIgnoreCase) && commaIdx >= 0)
            raw = raw[(commaIdx + 1)..];
        raw = raw.Replace("\r", string.Empty).Replace("\n", string.Empty).Replace(" ", string.Empty);

        // حدّ حجم معقول على طول base64 (≈ 6.7MB بيانات خام عند 5MB base64 تقريباً).
        if (raw.Length > MaxPhotoBase64Length)
            return Task.FromResult<IActionResult>(
                new ObjectResult(new { success = false, message = "حجم الصورة يتجاوز الحد المسموح" }) { StatusCode = 413 });

        // تحقّق أنّ المحتوى base64 صالح فعلاً (يمنع تمرير حمولة عشوائية للخدمة).
        if (!IsValidBase64(raw))
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "ترميز الصورة غير صالح" }));

        // امتداد مسموح فقط (قائمة سماح) — افتراضي jpg.
        var ext = NormalizePhotoExt(request.Ext);
        if (ext == null)
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "امتداد الصورة غير مدعوم" }));

        return UserScopedPassThroughAsync((companyId, ownerUserId, token) =>
            _sasClient.UploadPremisesPhotoAsync(companyId, ownerUserId, safePid, raw, ext, token), ct);
    }

    /// <summary>ربط مشترك بعقار يخصّ الوكيل الحالي — كتابة (manage).</summary>
    [HttpPost("premises/{pid}/link")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> LinkPremisesSubscriber(string pid, [FromBody] PremisesLinkRequest request, CancellationToken ct)
    {
        if (!TryNormalizePremisesId(pid, out var safePid, out var bad))
            return Task.FromResult(bad!);

        var safeRef = Trim(request?.SubscriberRef);
        if (safeRef == null)
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "مرجع المشترك مطلوب" }));

        return UserScopedPassThroughAsync((companyId, ownerUserId, token) =>
            _sasClient.LinkPremisesSubscriberAsync(companyId, ownerUserId, safePid, safeRef, token), ct);
    }

    /// <summary>فكّ ربط مشترك عن عقار يخصّ الوكيل الحالي — كتابة (manage).</summary>
    [HttpPost("premises/{pid}/unlink")]
    [RequirePermission("sas_agent", "manage", PermissionSystem.Second, failClosed: true)]
    public Task<IActionResult> UnlinkPremisesSubscriber(string pid, [FromBody] PremisesLinkRequest request, CancellationToken ct)
    {
        if (!TryNormalizePremisesId(pid, out var safePid, out var bad))
            return Task.FromResult(bad!);

        var safeRef = Trim(request?.SubscriberRef);
        if (safeRef == null)
            return Task.FromResult<IActionResult>(BadRequest(new { success = false, message = "مرجع المشترك مطلوب" }));

        return UserScopedPassThroughAsync((companyId, ownerUserId, token) =>
            _sasClient.UnlinkPremisesSubscriberAsync(companyId, ownerUserId, safePid, safeRef, token), ct);
    }

    // ---------- مساعدات العقارات ----------

    /// <summary>الحد الأقصى لطول سلسلة base64 لصورة العقار (حماية من الإساءة/استهلاك الذاكرة).</summary>
    private const int MaxPhotoBase64Length = 5 * 1024 * 1024; // ~5MB base64 ≈ ~3.75MB بيانات

    /// <summary>الحد الأقصى لطول معرّف العقار الممرَّر للخدمة.</summary>
    private const int MaxPremisesIdLength = 128;

    /// <summary>امتدادات الصور المسموح بها (قائمة سماح صارمة).</summary>
    private static readonly HashSet<string> AllowedPhotoExts = new(StringComparer.OrdinalIgnoreCase)
    {
        "jpg", "jpeg", "png", "webp"
    };

    /// <summary>يقصّ ويتحقّق من معرّف العقار؛ يعيد false + BadRequest عند الفراغ.</summary>
    private bool TryNormalizePremisesId(string? pid, out string safePid, out IActionResult? bad)
    {
        safePid = string.Empty;
        bad = null;
        var v = Trim(pid);
        if (v == null)
        {
            bad = BadRequest(new { success = false, message = "معرّف العقار مطلوب" });
            return false;
        }
        if (v.Length > MaxPremisesIdLength)
            v = v[..MaxPremisesIdLength];
        safePid = v;
        return true;
    }

    /// <summary>قصّ لقيمة نصّية مطلوبة (بعد التحقّق من عدم الفراغ مسبقاً) مع حدّ الطول.</summary>
    private static string? TrimRequired(string value)
        => Trim(value);

    /// <summary>تحقّق من صحّة الإحداثيات إن وُجدت (نطاق lat/lon المعياري).</summary>
    private static bool TryValidateCoordinates(double? lat, double? lon, out string error)
    {
        error = string.Empty;
        if (lat.HasValue && (double.IsNaN(lat.Value) || lat.Value < -90 || lat.Value > 90))
        {
            error = "خط العرض غير صالح";
            return false;
        }
        if (lon.HasValue && (double.IsNaN(lon.Value) || lon.Value < -180 || lon.Value > 180))
        {
            error = "خط الطول غير صالح";
            return false;
        }
        return true;
    }

    /// <summary>يطبّع امتداد الصورة إلى قيمة مسموحة (بلا نقطة، حروف صغيرة) أو null إن غير مدعوم.</summary>
    private static string? NormalizePhotoExt(string? ext)
    {
        if (string.IsNullOrWhiteSpace(ext))
            return "jpg"; // افتراضي آمن
        var e = ext.Trim().TrimStart('.').ToLowerInvariant();
        return AllowedPhotoExts.Contains(e) ? e : null;
    }

    /// <summary>يتحقّق أنّ السلسلة base64 صالحة الترميز دون تخصيص مصفوفة كبيرة (فكّ تجريبي).</summary>
    private static bool IsValidBase64(string value)
    {
        if (string.IsNullOrEmpty(value) || (value.Length % 4) != 0)
            return false;
        // FromBase64String يرمي عند عدم الصلاحية؛ نتحقّق دون استخدام الناتج (مجرّد تحقّق شكلي).
        var buffer = new byte[((value.Length * 3) + 3) / 4];
        return Convert.TryFromBase64String(value, buffer, out _);
    }

    /// <summary>
    /// نمط تمرير user-scoped عام: يحصر النطاق عبر <see cref="TryResolveScope"/> فيمرّر
    /// <c>companyId=tenant.CompanyId</c> و<c>ownerUserId=currentUserId</c> (من التوكن حصراً، لا من العميل)
    /// إلى الدالة المزوَّدة، ثم يعيد JSON خاماً — مع ترجمة تعذّر الخدمة إلى 503.
    /// لا يلمس أي حساب ساس ولا يفكّ أي تشفير. يُستخدم للعقارات (وأي ميزة user-scoped مماثلة).
    /// </summary>
    private Task<IActionResult> UserScopedPassThroughAsync(
        Func<string, string, CancellationToken, Task<string>> call,
        CancellationToken ct)
        => TicketsPassThroughAsync(call, ct);

    /// <summary>
    /// نمط تمرير التذاكر (user-scoped): يحصر النطاق عبر <see cref="TryResolveScope"/> فيمرّر
    /// <c>companyId=tenant.CompanyId</c> و<c>ownerUserId=currentUserId</c> (من التوكن حصراً, لا من العميل)
    /// إلى الدالة المزوَّدة، ثم يعيد JSON خاماً — مع ترجمة تعذّر الخدمة إلى 503.
    /// لا يلمس أي حساب ساس ولا يفكّ أي تشفير.
    /// </summary>
    private async Task<IActionResult> TicketsPassThroughAsync(
        Func<string, string, CancellationToken, Task<string>> call,
        CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied))
            return denied!;

        try
        {
            var raw = await call(companyId.ToString(), userId.ToString(), ct);
            return Content(raw, "application/json");
        }
        catch (SasServiceUnavailableException ex)
        {
            _logger.LogWarning(ex, "خدمة التذاكر غير متاحة أثناء التمرير");
            return StatusCode(503, new { success = false, message = "خدمة التذاكر غير متاحة حالياً" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في التمرير لخدمة التذاكر");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>قصّ آمن لقيمة نصّية اختيارية (تفريغ الفراغ + حدّ الطول) قبل التمرير للخدمة.</summary>
    private static string? Trim(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
            return null;
        var v = value.Trim();
        return v.Length > MaxQueryValueLength ? v[..MaxQueryValueLength] : v;
    }

    /// <summary>
    /// مفتاح ذمة المشترك الفريد في دفتر الذمم: «SasAccountId:SubscriberUid».
    /// يضمن ربط ذمة كل مشترك بحساب فرعي ثابت تحت «ذمم المواطنين 1180» عبر الزمن والعمليات.
    /// </summary>
    private static string CitizenKey(Guid accountId, string uid) => $"{accountId:N}:{uid}";

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
    /// نمط تمرير الكتابة الموحّد: مطابق لـ <see cref="PassThroughAsync"/> في العزل وفكّ التشفير
    /// والإرجاع الخام، ويُستخدم لنقاط الكتابة (manage). الفصل لأجل وضوح السياق في السجلّات
    /// (لا يُسجَّل أي اعتماد/سرّ). كل النقاط الكتابية تفرض [RequirePermission(..,"manage"..)] فوقه.
    /// </summary>
    private async Task<IActionResult> PassThroughWriteAsync(
        Guid id,
        Func<SasAccount, string, CancellationToken, Task<string>> call,
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
            _logger.LogWarning(ex, "خدمة الساس غير متاحة أثناء عملية الكتابة");
            return StatusCode(503, new { success = false, message = "خدمة الساس غير متاحة حالياً" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في عملية الكتابة عبر خدمة الساس");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// نمط تمرير محلي: يحصر النطاق ويجلب الحساب بالمطابقة الصارمة، ثم ينادي الخدمة المحلية
    /// دون فكّ أي تشفير ودون تمرير اعتماد ساس (نقاط التخزين المحلي: subscribers-local/report/reports).
    /// العزل مضمون عبر <see cref="GetOwnedAccountAsync"/>؛ accountId يُشتق من الحساب المملوك فقط.
    /// </summary>
    private async Task<IActionResult> LocalPassThroughAsync(
        Guid id,
        Func<SasAccount, CancellationToken, Task<string>> call,
        CancellationToken ct)
    {
        if (!TryResolveScope(out var companyId, out var userId, out var denied))
            return denied!;

        var account = await GetOwnedAccountAsync(id, companyId, userId, ct);
        if (account == null)
            return NotFound(new { success = false, message = "حساب الساس غير موجود" });

        try
        {
            var raw = await call(account, ct);
            return Content(raw, "application/json");
        }
        catch (SasServiceUnavailableException ex)
        {
            _logger.LogWarning(ex, "خدمة الساس غير متاحة أثناء عملية محلية");
            return StatusCode(503, new { success = false, message = "خدمة الساس غير متاحة حالياً" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في عملية محلية عبر خدمة الساس");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ---------- مساعدات التفعيل المحاسبي (activate-billed) ----------

    /// <summary>
    /// نتيجة قلب التفعيل المفوتر (<see cref="ActivateBilledCoreAsync"/>) — محايدة عن HTTP ليترجمها
    /// المستدعي (الفردي إلى IActionResult، والجماعي إلى عنصر في مصفوفة النتائج).
    /// لا تحمل أي سرّ: فقط حالة العملية + معرّفات السجل/القيد + الإيصال.
    /// </summary>
    private sealed class SasBilledResult
    {
        /// <summary>نجحت العملية (سجل + محاولة قيد) — ⇒ رد 200.</summary>
        public bool Ok { get; private init; }

        /// <summary>تكرار idempotency (معرّف عملية مكرّر) — ⇒ رد 409.</summary>
        public bool Conflict { get; private init; }

        /// <summary>رمز الحالة المقترح عند الفشل (مثل 502 لفشل الساس).</summary>
        public int StatusCode { get; private init; }

        /// <summary>رسالة وصفية (نجاح/فشل/تكرار) — بلا أسرار.</summary>
        public string? Message { get; private init; }

        /// <summary>معرّف السجل (SubscriptionLog) عند النجاح.</summary>
        public long? LogId { get; private init; }

        /// <summary>معرّف القيد المحاسبي عند نجاحه (قد يكون null إن فشل القيد والسجل باقٍ).</summary>
        public Guid? JournalEntryId { get; private init; }

        /// <summary>كائن الإيصال (للطباعة/الواتساب) عند النجاح.</summary>
        public object? Receipt { get; private init; }

        /// <summary>معرّف العملية المستخدم (idempotency).</summary>
        public string? TransactionId { get; private init; }

        public static SasBilledResult AsSuccess(long logId, Guid? journalEntryId, object receipt, string transactionId)
            => new() { Ok = true, StatusCode = 200, LogId = logId, JournalEntryId = journalEntryId, Receipt = receipt, TransactionId = transactionId };

        public static SasBilledResult AsConflict(string transactionId, string message)
            => new() { Ok = false, Conflict = true, StatusCode = 409, Message = message, TransactionId = transactionId };

        public static SasBilledResult AsFailure(int statusCode, string message, string? transactionId = null)
            => new() { Ok = false, StatusCode = statusCode, Message = message, TransactionId = transactionId };
    }

    /// <summary>الحد الأقصى لطول معرّف العملية (idempotency) الممرَّر/المخزَّن.</summary>
    private const int MaxTransactionIdLength = 64;

    /// <summary>
    /// يطبّع معرّف العملية (idempotency): يقبل قيمة العميل إن كانت غير فارغة ومعقولة الطول،
    /// وإلا يولّد Guid جديداً خادمياً (لا يُعتمد على العميل لضمان الفرادة).
    /// </summary>
    private static string NormalizeTransactionId(string? clientTxn)
    {
        if (!string.IsNullOrWhiteSpace(clientTxn))
        {
            var v = clientTxn.Trim();
            if (v.Length is > 0 and <= MaxTransactionIdLength)
                return v;
        }
        return Guid.NewGuid().ToString("N");
    }

    /// <summary>
    /// يبني وسائط إجراء الساس المالي: method=credit + money_collected=true + transaction_id،
    /// مع months للتفعيل/التمديد أو profile_id لتغيير الباقة.
    /// </summary>
    private static Dictionary<string, object?> BuildActionParams(
        string action, int? months, string? profileId, string transactionId)
    {
        var p = new Dictionary<string, object?>
        {
            ["method"] = "credit",
            ["money_collected"] = true,
            ["transaction_id"] = transactionId
        };
        if (action is "activate" or "extend" && months.HasValue)
            p["months"] = months.Value;
        if (action == "changeProfile" && !string.IsNullOrWhiteSpace(profileId))
            p["profile_id"] = profileId.Trim();
        return p;
    }

    /// <summary>
    /// يحلّل استجابة <c>user/activationData/{uid}</c> لاستخراج السعر المطلوب (BasePrice) واسم الباقة ومعرّفها.
    /// يقرأ <c>n_required_amount</c> (أو <c>required_amount</c>) و<c>profile_name</c>/<c>profile</c> و<c>profile_id</c>
    /// من الجذر أو <c>data</c>؛ يُرجع (0, null, null) بأمان إن تعذّر.
    /// </summary>
    private static (decimal basePrice, string? planName, string? profileId) ParseActivationData(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
            return (0, null, null);

        try
        {
            using var doc = System.Text.Json.JsonDocument.Parse(raw);
            var root = doc.RootElement;

            // قد تكون البيانات في الجذر أو تحت "data".
            System.Text.Json.JsonElement node = root;
            if (root.ValueKind == System.Text.Json.JsonValueKind.Object
                && root.TryGetProperty("data", out var dataEl)
                && dataEl.ValueKind == System.Text.Json.JsonValueKind.Object)
                node = dataEl;

            decimal price = ReadDecimal(node, "n_required_amount") ?? ReadDecimal(node, "required_amount") ?? 0;
            string? plan = ReadString(node, "profile_name") ?? ReadString(node, "profile");
            // معرّف الباقة قد يكون رقماً أو نصّاً — نقرؤه من profile_id ثم profile كبديل.
            string? profileId = ReadString(node, "profile_id")
                                ?? ReadNumberAsString(node, "profile_id")
                                ?? ReadString(node, "profile")
                                ?? ReadNumberAsString(node, "profile");

            return (price < 0 ? 0 : price, plan, profileId);
        }
        catch
        {
            return (0, null, null);
        }
    }

    /// <summary>
    /// يحدّد معرّف الباقة المستخدَم في البحث عن التسعير: أولوية <paramref name="requestProfileId"/> (من الطلب)
    /// ثم المستنتَج من activationData. يُرجع null إن تعذّر (تساهل — المحاسبة تتابع بالسلوك الحالي).
    /// </summary>
    private static string? ResolvePricingProfileId(string? requestProfileId, string? activationProfileId)
    {
        var fromRequest = Trim(requestProfileId);
        if (!string.IsNullOrWhiteSpace(fromRequest))
            return fromRequest;
        var fromActivation = Trim(activationProfileId);
        return string.IsNullOrWhiteSpace(fromActivation) ? null : fromActivation;
    }

    /// <summary>يحاول قراءة اسم المستخدم من استجابة الإجراء الخام (إن وُجد)؛ null بأمان.</summary>
    private static string? ParseUsername(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
            return null;
        try
        {
            using var doc = System.Text.Json.JsonDocument.Parse(raw);
            var root = doc.RootElement;
            if (root.ValueKind != System.Text.Json.JsonValueKind.Object)
                return null;
            return ReadString(root, "username")
                ?? (root.TryGetProperty("data", out var d) && d.ValueKind == System.Text.Json.JsonValueKind.Object
                    ? ReadString(d, "username")
                    : null);
        }
        catch
        {
            return null;
        }
    }

    /// <summary>يقرأ قيمة عددية (decimal) من خاصيّة JSON (رقم أو نص رقمي)؛ null إن غابت/غير صالحة.</summary>
    private static decimal? ReadDecimal(System.Text.Json.JsonElement obj, string name)
    {
        if (obj.ValueKind != System.Text.Json.JsonValueKind.Object || !obj.TryGetProperty(name, out var el))
            return null;
        if (el.ValueKind == System.Text.Json.JsonValueKind.Number && el.TryGetDecimal(out var d))
            return d;
        if (el.ValueKind == System.Text.Json.JsonValueKind.String
            && decimal.TryParse(el.GetString(), System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out var s))
            return s;
        return null;
    }

    /// <summary>يقرأ قيمة نصّية من خاصيّة JSON؛ null إن غابت/فارغة.</summary>
    private static string? ReadString(System.Text.Json.JsonElement obj, string name)
    {
        if (obj.ValueKind != System.Text.Json.JsonValueKind.Object || !obj.TryGetProperty(name, out var el))
            return null;
        if (el.ValueKind == System.Text.Json.JsonValueKind.String)
        {
            var v = el.GetString();
            return string.IsNullOrWhiteSpace(v) ? null : v;
        }
        return null;
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
    DateTime? LastSyncAt,
    decimal AmountMultiplier = 1000m);

/// <summary>طلب ربط حساب ساس جديد.</summary>
public record CreateSasAccountRequest(
    string? Label,
    string ServerUrl,
    string Username,
    string? Password,
    SasAccountType AccountType,
    bool? IsActive,
    decimal? AmountMultiplier = null);

/// <summary>طلب تعديل حساب ساس — كل الحقول اختيارية؛ Password فقط عند التغيير.</summary>
public record UpdateSasAccountRequest(
    string? Label,
    string? ServerUrl,
    string? Username,
    string? Password,
    SasAccountType? AccountType,
    bool? IsActive,
    decimal? AmountMultiplier = null);

/// <summary>طلب تجديد جماعي — معرّفات المشتركين وعدد الأشهر وبروفايل اختياري ومعاينة (dryRun).</summary>
public record BulkRenewRequest(
    List<string> SubscriberIds,
    int Months,
    string? ProfileId,
    bool? DryRun);

/// <summary>طلب إجراء على مشترك/مدير — اسم الإجراء + وسائط حرّة (JSON) تُمرَّر كما هي لخدمة الساس.</summary>
public record SasActionRequest(
    string Action,
    System.Text.Json.JsonElement? Params);

/// <summary>
/// طلب تفعيل/تجديد/تغيير باقة مشترك ساس مع قيد محاسبي (محاسبة موحّدة مع FTTH).
/// السعر (BasePrice) يُجلب خادمياً من activationData — لا من هذا الطلب.
/// companyId/userId/accountId مختومة خادمياً من الحساب المملوك — لا من العميل.
/// </summary>
/// <param name="Action">الإجراء: activate | extend | changeProfile.</param>
/// <param name="Months">عدد الأشهر (مطلوب لـ activate/extend).</param>
/// <param name="ProfileId">معرّف الباقة (مطلوب لـ changeProfile).</param>
/// <param name="CollectionType">نوع التحصيل: cash | credit | agent (افتراضي cash).</param>
/// <param name="MaintenanceFee">أجور صيانة/هامش اختياري (≥0).</param>
/// <param name="ManualDiscount">خصم يدوي اختياري للعميل (≥0).</param>
/// <param name="SystemDiscountEnabled">هل خصم الشركة مفعّل (افتراضي true).</param>
/// <param name="LinkedAgentId">الوكيل المرتبط (مطلوب عند CollectionType=agent).</param>
/// <param name="LinkedTechnicianId">الفني المرتبط (مطلوب عند CollectionType=technician).</param>
/// <param name="Phone">هاتف المشترك (اختياري — للإيصال/الواتساب لاحقاً).</param>
/// <param name="SubscriberUsername">اسم مستخدم المشترك (اختياري — للإيصال).</param>
/// <param name="TransactionId">معرّف عملية للـ idempotency (اختياري — يُولَّد خادمياً إن غاب).</param>
/// <param name="Note">ملاحظة اختيارية.</param>
public record SasActivateBilledRequest(
    string Action,
    int? Months,
    string? ProfileId,
    string CollectionType,
    decimal? MaintenanceFee,
    decimal? ManualDiscount,
    bool SystemDiscountEnabled = true,
    Guid? LinkedAgentId = null,
    Guid? LinkedTechnicianId = null,
    string? Phone = null,
    string? SubscriberUsername = null,
    string? TransactionId = null,
    string? Note = null);

/// <summary>طلب إجراء جماعي — معرّفات + اسم الإجراء + وسائط حرّة (JSON).</summary>
public record SasBulkActionRequest(
    List<string> Uids,
    string Action,
    System.Text.Json.JsonElement? Params);

/// <summary>
/// طلب تجديد/تفعيل جماعي مفوتر — نفس خطّ <c>activate-billed</c> لكل مشترك (قيد موحّد Source=Sas).
/// معرّف العملية (idempotency) يُولَّد خادمياً لكل مشترك على حدة — لا من العميل.
/// companyId/userId/accountId مختومة خادمياً من الحساب المملوك — لا من العميل.
/// </summary>
/// <param name="SubscriberIds">معرّفات مشتركي الساس (uid) — مطلوبة (تُزال التكرارات والفوارغ).</param>
/// <param name="Action">الإجراء: activate | extend (افتراضي extend).</param>
/// <param name="Months">عدد الأشهر (مطلوب — 1..60).</param>
/// <param name="ProfileId">معرّف الباقة (اختياري — إن رُغب تثبيت باقة موحّدة).</param>
/// <param name="CollectionType">نوع التحصيل: cash | credit | agent (افتراضي cash).</param>
/// <param name="MaintenanceFee">أجور صيانة/هامش اختياري لكل مشترك (≥0).</param>
/// <param name="ManualDiscount">خصم يدوي اختياري لكل مشترك (≥0).</param>
/// <param name="SystemDiscountEnabled">هل خصم الشركة مفعّل (افتراضي true).</param>
/// <param name="LinkedAgentId">الوكيل المرتبط (مطلوب عند CollectionType=agent).</param>
/// <param name="LinkedTechnicianId">الفني المرتبط (مطلوب عند CollectionType=technician).</param>
public record SasBulkBilledRequest(
    List<string> SubscriberIds,
    string Action = "extend",
    int? Months = null,
    string? ProfileId = null,
    string CollectionType = "cash",
    decimal? MaintenanceFee = null,
    decimal? ManualDiscount = null,
    bool SystemDiscountEnabled = true,
    Guid? LinkedAgentId = null,
    Guid? LinkedTechnicianId = null);

/// <summary>طلب يحمل حمولة JSON حرّة (إنشاء/تعديل مشترك) تُمرَّر كما هي لخدمة الساس.</summary>
public record SasPayloadRequest(
    System.Text.Json.JsonElement? Payload);

/// <summary>طلب بروكسي عام POST — مسار ساس + حمولة JSON حرّة اختيارية.</summary>
public record SasProxyPostRequest(
    string Path,
    System.Text.Json.JsonElement? Payload);

/// <summary>
/// طلب تقديم تصريح/بلنك شهري — الإجمالي والفعّالون المُصرَّح بهم وملاحظة اختيارية.
/// (accountId/companyId/ownerUserId/submittedBy تُشتق خادمياً من الحساب المملوك والهوية — لا من العميل.)
/// </summary>
public record SubmitReportRequest(
    int DeclaredTotal,
    int DeclaredActive,
    string? Note);

/// <summary>
/// طلب إنشاء تذكرة وكيل — العنوان والنصّ مطلوبان؛ التصنيف/الأولوية/مرجع المشترك اختيارية.
/// (companyId/ownerUserId/createdBy تُشتق خادمياً من التوكن — لا من العميل.)
/// </summary>
public record SasAgentCreateTicketRequest(
    string Subject,
    string Body,
    string? Category,
    string? Priority,
    string? SubscriberRef);

/// <summary>
/// طلب إضافة ردّ على تذكرة وكيل — النصّ مطلوب؛ isInternal اختياري.
/// (companyId/ownerUserId/author تُشتق خادمياً من التوكن — لا من العميل.)
/// </summary>
public record SasAgentReplyTicketRequest(
    string Body,
    bool? IsInternal);

/// <summary>
/// طلب تحديث تذكرة وكيل — كل الحقول اختيارية (status/priority/category)؛ يُرفض إن كانت كلها فارغة.
/// (companyId/ownerUserId تُشتق خادمياً من التوكن — لا من العميل.)
/// </summary>
public record SasAgentUpdateTicketRequest(
    string? Status,
    string? Priority,
    string? Category);

// ==================== DTOs العقارات (Premises) ====================
// بادئة Premises لتفادي التصادم. companyId/ownerUserId/createdBy تُشتق خادمياً من التوكن — لا من العميل.

/// <summary>
/// طلب إنشاء عقار — المحافظة والمنطقة والنقطة الدالّة مطلوبة؛ الإحداثيات/الهاتف/الملكية/النوع اختيارية.
/// </summary>
public record PremisesCreateRequest(
    string Governorate,
    string Area,
    string Landmark,
    double? Lat,
    double? Lon,
    string? Phone,
    string? Ownership,
    string? Ptype);

/// <summary>
/// طلب تعديل عقار — كل الحقول اختيارية؛ يُرفض إن كانت كلها فارغة. (premises_id من المسار.)
/// </summary>
public record PremisesUpdateRequest(
    string? Governorate,
    string? Area,
    string? Landmark,
    double? Lat,
    double? Lon,
    string? Phone,
    string? Ownership,
    string? Ptype);

/// <summary>طلب رفع صورة عقار — الصورة base64 (تُنظَّف بادئة data:) وامتداد اختياري (افتراضي jpg).</summary>
public record PremisesPhotoUploadRequest(
    string ImageBase64,
    string? Ext);

/// <summary>طلب ربط/فكّ ربط مشترك بعقار — مرجع المشترك مطلوب. (premises_id من المسار.)</summary>
public record PremisesLinkRequest(
    string? SubscriberRef);

// ==================== DTOs إدارة الوكلاء (للأدمن — company-scoped) ====================
// بادئة SasAgentAdmin لتفادي التصادم. ⚠️ بلا أي سرّ (لا PasswordEncrypted، لا Username لحساب الساس).

/// <summary>
/// مقاطعة/مطابقة حساب ساس واحد (المُصرَّح مقابل الفعلي) من خدمة Python — للعرض في لوحة الأدمن.
/// </summary>
public record SasAgentAdminReconciliationDto(
    int DeclaredTotal,
    int DeclaredActive,
    int ActualTotal,
    int ActualActive,
    int Diff,
    string? Verdict,
    string? LastSync);

/// <summary>حساب ساس واحد ضمن وكيل (بلا أسرار) + مقاطعته (قد تكون null إذا تعذّرت الخدمة).</summary>
public record SasAgentAdminAccountDto(
    Guid Id,
    string Label,
    string ServerUrl,
    bool IsActive,
    SasAgentAdminReconciliationDto? Reconciliation);

/// <summary>مجاميع وكيل واحد: عدد الحسابات + مجموع المُصرَّح + مجموع الفعلي.</summary>
public record SasAgentAdminTotalsDto(
    int Accounts,
    int Declared,
    int Actual);

/// <summary>وكيل واحد (مالك حسابات ساس) ضمن الشركة + حساباته + مجاميعه — للوحة الأدمن.</summary>
public record SasAgentAdminAgentDto(
    Guid UserId,
    string FullName,
    string? Username,
    List<SasAgentAdminAccountDto> Accounts,
    SasAgentAdminTotalsDto Totals);

// ==================== DTOs تسعير الباقات (SasPricing — نظام الأرباح) ====================
// بادئة SasPricing لتفادي التصادم. CompanyId/SasAccountId مختومة خادمياً من الحساب المملوك — لا من العميل.

/// <summary>
/// تسعير باقة واحدة للعرض — الكلفة وسعر البيع والربح (محسوب = SellingPrice − Cost) وحالة التفعيل.
/// باقة غير مسعّرة تُعاد بأصفار.
/// </summary>
public record SasPricingPackageDto(
    string ProfileId,
    string ProfileName,
    decimal Cost,
    decimal SellingPrice,
    decimal Profit,
    bool IsActive);

/// <summary>عنصر تسعير واحد في طلب الحفظ (upsert) — profileId مفتاح الـ upsert.</summary>
public record SasPricingUpsertItem(
    string ProfileId,
    string? ProfileName,
    decimal Cost,
    decimal SellingPrice,
    bool? IsActive);

/// <summary>طلب حفظ أسعار الباقات (upsert) — قائمة عناصر التسعير. (accountId من المسار؛ companyId خادمياً.)</summary>
public record SasPricingUpsertRequest(
    List<SasPricingUpsertItem> Items);

// ==================== DTOs بيانات المواطن الموسّعة (SasProfile) ====================
// بادئة SasProfile لتفادي التصادم. CompanyId/SasAccountId/uid مختومة خادمياً — لا من العميل.

/// <summary>بيانات المواطن الموسّعة للعرض (مع الـ uid)؛ الحقول null إن لم تُحفظ بعد.</summary>
public record SasProfileDto(
    string SubscriberUid,
    string? SubscriberUsername,
    string? NationalId,
    string? FullNameQuad,
    DateTime? BirthDate,
    string? Gender,
    string? AltPhone,
    string? WhatsappNumber,
    string? Email,
    Guid? RegionId,
    string? RegionName,
    string? AddressDetail,
    double? Latitude,
    double? Longitude,
    string? PropertyType,
    string? Landmark);

// ==================== DTOs دفتر ذمم المواطنين (SasCitizenPayment) ====================
// accountId/uid من المسار؛ companyId/sasAccountId مختومة خادمياً — لا من العميل.

/// <summary>طلب تسديد ذمّة مشترك (آجل) — المبلغ موجب؛ الوسيلة cash|master؛ ملاحظة اختيارية.</summary>
public record SasCitizenPaymentRequest(
    decimal Amount,
    string? Method,
    string? Note);

/// <summary>طلب حفظ بيانات المواطن الموسّعة (upsert) — كل الحقول اختيارية. (accountId/uid من المسار؛ companyId خادمياً.)</summary>
public record SasProfileUpsertRequest(
    string? SubscriberUsername,
    string? NationalId,
    string? FullNameQuad,
    DateTime? BirthDate,
    string? Gender,
    string? AltPhone,
    string? WhatsappNumber,
    string? Email,
    Guid? RegionId,
    string? AddressDetail,
    double? Latitude,
    double? Longitude,
    string? PropertyType,
    string? Landmark);

// ==================== DTOs المناطق (SasRegion) ====================
// CompanyId مختوم خادمياً — لا من العميل. أجور الصيانة تُطبَّق تلقائياً على مشتركي المنطقة.

/// <summary>منطقة للعرض — مع عدد المشتركين المرتبطين (للتقارير).</summary>
public record SasRegionDto(
    Guid Id,
    string Name,
    string? Code,
    string? Governorate,
    string? City,
    decimal MaintenanceFee,
    bool IsActive,
    string? Notes,
    int SubscribersCount);

/// <summary>طلب إنشاء/تعديل منطقة — الاسم مطلوب؛ أجور الصيانة ≥0. (companyId خادمياً.)</summary>
public record SasRegionUpsertRequest(
    string Name,
    string? Code,
    string? Governorate,
    string? City,
    decimal MaintenanceFee,
    bool? IsActive,
    string? Notes);

/// <summary>طلب فكّ دفعة حمولات ساس مشفّرة (مستكشف الساس). items = حمولات base64 (Salted__).</summary>
public record SasExplorerDecryptRequest(
    List<string> Items);

/// <summary>صفّ تفصيل في تقرير الأرباح (مجموعة: منطقة/باقة/إجمالي). الربح = المحصّل − الكلفة.</summary>
public record SasProfitRow(
    string Label,
    int Count,
    decimal Cost,
    decimal Profit,
    decimal Revenue);
