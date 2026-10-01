using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.API.Authorization;
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

        // قائمة سماح لنوع التحصيل (مطابق لمنطق المحاسبة الموحّد).
        var collectionType = string.IsNullOrWhiteSpace(request.CollectionType) ? "cash" : request.CollectionType.Trim().ToLowerInvariant();
        if (collectionType is not ("cash" or "credit" or "agent"))
            return BadRequest(new { success = false, message = "نوع تحصيل غير مدعوم (المتاح: cash | credit | agent)" });

        if (collectionType == "agent" && (!request.LinkedAgentId.HasValue || request.LinkedAgentId.Value == Guid.Empty))
            return BadRequest(new { success = false, message = "يجب تحديد الوكيل عند اختيار نوع التحصيل 'وكيل'" });

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
        var maintenanceFee = Math.Max(0, req.MaintenanceFee ?? 0);
        var manualDiscount = Math.Max(0, req.ManualDiscount ?? 0);

        // 1) idempotency: معرّف عملية فريد — من الطلب إن أُرسل (وصالح) وإلا نولّده خادمياً.
        var transactionId = NormalizeTransactionId(req.TransactionId);

        var alreadyLogged = await _unitOfWork.SubscriptionLogs.AsQueryable()
            .AnyAsync(l => l.FtthTransactionId == transactionId && l.CompanyId == companyId, ct);
        if (alreadyLogged)
            return SasBilledResult.AsConflict(transactionId, "العملية مُنفّذة مسبقاً (معرّف عملية مكرّر)");

        var safePhone = Trim(req.Phone);
        var note = Trim(req.Note);

        // 2) جلب السعر خادمياً من activationData (لا نثق بالعميل في السعر).
        //    للـ extend قد لا يعيد سعراً — نستخدم activationData نفسه؛ إن غاب يبقى 0 (منطق بديل في المحاسبة).
        decimal basePrice = 0;
        string? planName = null;
        try
        {
            var activationRaw = await _sasClient.SasGetAsync(
                account.ServerUrl, account.Username, pwd, $"user/activationData/{uid}", ct);
            (basePrice, planName) = ParseActivationData(activationRaw);
        }
        catch (SasServiceUnavailableException)
        {
            // إذا تعذّر جلب السعر لا نُجهض كلياً: نُكمل بسعر 0 (يُسجَّل تحذير) لأن الإجراء قد ينجح دون سعر معروف.
            _logger.LogWarning("تعذّر جلب activationData للمشترك {Uid} — سيُستخدم سعر 0", uid);
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

        // قائمة سماح لنوع التحصيل (مطابق لمنطق المحاسبة الموحّد).
        var collectionType = string.IsNullOrWhiteSpace(request.CollectionType)
            ? "cash"
            : request.CollectionType.Trim().ToLowerInvariant();
        if (collectionType is not ("cash" or "credit" or "agent"))
            return BadRequest(new { success = false, message = "نوع تحصيل غير مدعوم (المتاح: cash | credit | agent)" });

        if (collectionType == "agent" && (!request.LinkedAgentId.HasValue || request.LinkedAgentId.Value == Guid.Empty))
            return BadRequest(new { success = false, message = "يجب تحديد الوكيل عند اختيار نوع التحصيل 'وكيل'" });

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
                    l.JournalEntryId
                })
                .ToListAsync(ct);

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
                journalEntryId = l.JournalEntryId
            }).ToList();

            return Ok(new { success = true, total, data });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب سجل حركات حساب الساس");
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
        [FromQuery] bool? expiring = null,
        [FromQuery] int? page = null,
        [FromQuery] int? count = null,
        CancellationToken ct = default)
    {
        // قصّ آمن للوسائط النصّية والعددية قبل التمرير.
        var safeSearch = Trim(search);
        var safeStatus = Trim(status);
        var safePage = page.HasValue ? Math.Clamp(page.Value, 1, 100000) : (int?)null;
        var safeCount = count.HasValue ? Math.Clamp(count.Value, 1, 1000) : (int?)null;

        return LocalPassThroughAsync(id, (acc, token) =>
            _sasClient.GetLocalSubscribersAsync(
                acc.Id.ToString(), safeSearch, safeStatus, expiring, safePage, safeCount, token), ct);
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
    /// يحلّل استجابة <c>user/activationData/{uid}</c> لاستخراج السعر المطلوب (BasePrice) واسم الباقة.
    /// يقرأ <c>n_required_amount</c> (أو <c>required_amount</c>) من الجذر أو <c>data</c>؛ يُرجع (0, null) بأمان إن تعذّر.
    /// </summary>
    private static (decimal basePrice, string? planName) ParseActivationData(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
            return (0, null);

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

            return (price < 0 ? 0 : price, plan);
        }
        catch
        {
            return (0, null);
        }
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
public record SasBulkBilledRequest(
    List<string> SubscriberIds,
    string Action = "extend",
    int? Months = null,
    string? ProfileId = null,
    string CollectionType = "cash",
    decimal? MaintenanceFee = null,
    decimal? ManualDiscount = null,
    bool SystemDiscountEnabled = true,
    Guid? LinkedAgentId = null);

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
