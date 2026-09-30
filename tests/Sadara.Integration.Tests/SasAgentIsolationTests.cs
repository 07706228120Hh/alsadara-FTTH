using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Sadara.API.Authorization;
using Sadara.API.Controllers;
using Sadara.Application.Interfaces;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Data;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// اختبارات عزل الأمان لـ <see cref="SasAgentController"/>.
///
/// كل اختبار يستخدم EF InMemory معزولاً (dbName فريد) — لا قاعدة بيانات حقيقية، لا تلوّث بين الاختبارات.
/// المضاعفات (fakes) لـ ICurrentTenant / ISecretProtector / ISasServiceClient مُعرَّفة داخلياً.
///
/// تغطية:
///  1) عزل الشركات: مستخدم شركة أ لا يصل لحساب شركة ب => NotFound.
///  2) عزل المالك: مستخدم يطلب حساب زميل بنفس الشركة (OwnerUserId مختلف) => NotFound.
///  3) حارس النطاق: CompanyId==null (SuperAdmin/سياق نظام) => Forbid على القائمة والإنشاء.
///  4) ختم الإنشاء: POST يختم CompanyId/OwnerUserId من السياق (لا من الجسم)،
///                   يستدعي Protect، والـ DTO لا يحتوي حقل كلمة مرور.
///  5) failClosed (unit): HasPermission(null, "sas_agent", "view", failClosed:true)  => false.
///                        HasPermission(null, "sas_agent", "view", failClosed:false) => true.
///  6) SecretProtector (unit): Protect->Unprotect يعيد النص الأصلي، والمشفَّر != النص.
/// </summary>
public class SasAgentIsolationTests
{
    // ── ثوابت الاختبار ────────────────────────────────────────────────────────
    private static readonly Guid CompanyA = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid CompanyB = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid UserA1   = Guid.Parse("a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1");
    private static readonly Guid UserA2   = Guid.Parse("a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2");

    // ── Fakes / Stubs ──────────────────────────────────────────────────────────

    /// <summary>ICurrentTenant قابل للضبط.</summary>
    private sealed class FakeTenant : ICurrentTenant
    {
        public Guid? CompanyId { get; init; }
        public bool IsSuperAdmin { get; init; }
        public bool BypassTenantFilter { get; init; }
        public Guid? DefaultCompanyId { get; init; }
        public bool EnforceIsolation { get; init; }
    }

    /// <summary>ISecretProtector بسيط (Base64 لأغراض الاختبار — لا تشفير حقيقي).</summary>
    private sealed class FakeSecretProtector : ISecretProtector
    {
        public int ProtectCallCount { get; private set; }

        public string Protect(string plaintext)
        {
            ProtectCallCount++;
            if (string.IsNullOrEmpty(plaintext)) return string.Empty;
            return "FAKE:" + Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(plaintext));
        }

        public string Unprotect(string ciphertext)
        {
            if (string.IsNullOrEmpty(ciphertext)) return string.Empty;
            if (!ciphertext.StartsWith("FAKE:", StringComparison.Ordinal))
                throw new InvalidOperationException("لا يمكن فكّ تشفير قيمة ليست من FakeSecretProtector");
            return System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(ciphertext[5..]));
        }
    }

    /// <summary>ISasServiceClient يطلق استثناء إن استُدعي (الاختبارات لا تصل للـ SAS).</summary>
    private sealed class UnreachableSasClient : ISasServiceClient
    {
        public Task<SasLoginResult> LoginAsync(string s, string u, string p, CancellationToken ct = default)
            => throw new InvalidOperationException("SasClient لا يجب أن يُستدعى في هذا الاختبار");
        public Task<string> GetDashboardAsync(string s, string u, string p, CancellationToken ct = default)
            => throw new InvalidOperationException("SasClient لا يجب أن يُستدعى في هذا الاختبار");
        public Task<string> GetSubscribersAsync(string s, string u, string p, IDictionary<string, string?>? q = null, CancellationToken ct = default)
            => throw new InvalidOperationException("SasClient لا يجب أن يُستدعى في هذا الاختبار");
        public Task<string> GetReportAsync(string s, string u, string p, IDictionary<string, string?>? q = null, CancellationToken ct = default)
            => throw new InvalidOperationException("SasClient لا يجب أن يُستدعى في هذا الاختبار");
        public Task<string> GetPackagesAsync(string s, string u, string p, CancellationToken ct = default)
            => throw new InvalidOperationException("SasClient لا يجب أن يُستدعى في هذا الاختبار");
        public Task<string> GetFinanceAsync(string s, string u, string p, CancellationToken ct = default)
            => throw new InvalidOperationException("SasClient لا يجب أن يُستدعى في هذا الاختبار");
        public Task<string> GetHealthAsync(string s, string u, string p, CancellationToken ct = default)
            => throw new InvalidOperationException("SasClient لا يجب أن يُستدعى في هذا الاختبار");
        public Task<string> GetRenewalCandidatesAsync(string s, string u, string p, int? d = null, string? q = null, CancellationToken ct = default)
            => throw new InvalidOperationException("SasClient لا يجب أن يُستدعى في هذا الاختبار");
        public Task<string> BulkRenewAsync(string s, string u, string p, IEnumerable<string> ids, int m, string? pid = null, bool dry = false, CancellationToken ct = default)
            => throw new InvalidOperationException("SasClient لا يجب أن يُستدعى في هذا الاختبار");

        // ── أعضاء الواجهة الموسّعة ─────────────────────────────────────────────
        // الاختبارات القديمة لا تبلغ هذه النقاط؛ الإضافة لإرضاء المُجمِّع فقط.
        private static Task<string> _Unreachable() => throw new InvalidOperationException("SasClient لا يجب أن يُستدعى في هذا الاختبار");

        public Task<string> GetUserDetailAsync(string s, string u, string p, string uid, CancellationToken ct = default) => _Unreachable();
        public Task<string> GetUserOverviewAsync(string s, string u, string p, string uid, CancellationToken ct = default) => _Unreachable();
        public Task<string> GetUserHistoryAsync(string s, string u, string p, string uid, CancellationToken ct = default) => _Unreachable();
        public Task<string> GetUserExtendDataAsync(string s, string u, string p, string uid, CancellationToken ct = default) => _Unreachable();
        public Task<string> UserActionAsync(string s, string u, string p, string uid, string action, object? pms = null, CancellationToken ct = default) => _Unreachable();
        public Task<string> UsersBulkActionAsync(string s, string u, string p, IEnumerable<string> uids, string action, object? pms = null, CancellationToken ct = default) => _Unreachable();
        public Task<string> CreateUserAsync(string s, string u, string p, object payload, CancellationToken ct = default) => _Unreachable();
        public Task<string> UpdateUserAsync(string s, string u, string p, string uid, object payload, CancellationToken ct = default) => _Unreachable();
        public Task<string> DeleteUserAsync(string s, string u, string p, string uid, CancellationToken ct = default) => _Unreachable();
        public Task<string> GetUserRefundDataAsync(string s, string u, string p, string uid, CancellationToken ct = default) => _Unreachable();
        public Task<string> RefundUserAsync(string s, string u, string p, string uid, CancellationToken ct = default) => _Unreachable();
        public Task<string> GetOnlineAsync(string s, string u, string p, CancellationToken ct = default) => _Unreachable();
        public Task<string> GetManagersAsync(string s, string u, string p, CancellationToken ct = default) => _Unreachable();
        public Task<string> ManagerActionAsync(string s, string u, string p, string mid, string action, object? pms = null, CancellationToken ct = default) => _Unreachable();
        public Task<string> DeleteManagerAsync(string s, string u, string p, string mid, CancellationToken ct = default) => _Unreachable();
        public Task<string> SasGetAsync(string s, string u, string p, string path, CancellationToken ct = default) => _Unreachable();
        public Task<string> SasPostAsync(string s, string u, string p, string path, object? payload = null, CancellationToken ct = default) => _Unreachable();
        public Task<string> TestAccountAsync(string s, string u, string p, CancellationToken ct = default) => _Unreachable();
        public Task<string> SyncAccountAsync(string s, string u, string p, string accountId, CancellationToken ct = default) => _Unreachable();
        public Task<string> GetLocalSubscribersAsync(string accountId, string? search = null, string? status = null, bool? expiring = null, int? page = null, int? count = null, CancellationToken ct = default) => _Unreachable();
        public Task<string> GetSubscribersSummaryAsync(string accountId, CancellationToken ct = default) => _Unreachable();
        public Task<string> SubmitReportAsync(string accountId, string companyId, string ownerUserId, int declaredTotal, int declaredActive, string? note = null, string? submittedBy = null, CancellationToken ct = default) => _Unreachable();
        public Task<string> ListReportsAsync(string accountId, CancellationToken ct = default) => _Unreachable();
        public Task<string> GetReconciliationAsync(string accountId, string s, string u, string p, CancellationToken ct = default) => _Unreachable();
        public Task<string> GetAgentsSummaryAsync(string companyId, IEnumerable<string> accountIds, CancellationToken ct = default) => _Unreachable();
        public Task<string> GetTicketsStatsAsync(string companyId, string ownerUserId, CancellationToken ct = default) => _Unreachable();
        public Task<string> GetTicketsListAsync(string companyId, string ownerUserId, string? status = null, string? category = null, string? search = null, int? page = null, int? count = null, CancellationToken ct = default) => _Unreachable();
        public Task<string> GetTicketAsync(string companyId, string ownerUserId, string ticketId, CancellationToken ct = default) => _Unreachable();
        public Task<string> CreateTicketAsync(string companyId, string ownerUserId, string subject, string body, string? category = null, string? priority = null, string? subscriberRef = null, string? createdBy = null, CancellationToken ct = default) => _Unreachable();
        public Task<string> ReplyTicketAsync(string companyId, string ownerUserId, string ticketId, string body, bool? isInternal = null, string? author = null, CancellationToken ct = default) => _Unreachable();
        public Task<string> UpdateTicketAsync(string companyId, string ownerUserId, string ticketId, string? status = null, string? priority = null, string? category = null, CancellationToken ct = default) => _Unreachable();
        public Task<string> GetPremisesListAsync(string companyId, string ownerUserId, string? search = null, string? ownership = null, string? ptype = null, int? page = null, int? count = null, CancellationToken ct = default) => _Unreachable();
        public Task<string> GetPremisesAsync(string companyId, string ownerUserId, string premisesId, CancellationToken ct = default) => _Unreachable();
        public Task<string> GetPremisesSubscribersAsync(string companyId, string ownerUserId, string premisesId, CancellationToken ct = default) => _Unreachable();
        public Task<string> GetPremisesBySubscriberAsync(string companyId, string ownerUserId, string subscriberRef, CancellationToken ct = default) => _Unreachable();
        public Task<string> GetPremisesLinkCandidatesAsync(string companyId, string ownerUserId, string? search = null, CancellationToken ct = default) => _Unreachable();
        public Task<string> GetPremisesPhotoAsync(string companyId, string ownerUserId, string premisesId, CancellationToken ct = default) => _Unreachable();
        public Task<string> CreatePremisesAsync(string companyId, string ownerUserId, string governorate, string area, string landmark, double? lat = null, double? lon = null, string? phone = null, string? ownership = null, string? ptype = null, string? createdBy = null, CancellationToken ct = default) => _Unreachable();
        public Task<string> UpdatePremisesAsync(string companyId, string ownerUserId, string premisesId, string? governorate = null, string? area = null, string? landmark = null, double? lat = null, double? lon = null, string? phone = null, string? ownership = null, string? ptype = null, CancellationToken ct = default) => _Unreachable();
        public Task<string> DeletePremisesAsync(string companyId, string ownerUserId, string premisesId, CancellationToken ct = default) => _Unreachable();
        public Task<string> UploadPremisesPhotoAsync(string companyId, string ownerUserId, string premisesId, string imageBase64, string ext, CancellationToken ct = default) => _Unreachable();
        public Task<string> LinkPremisesSubscriberAsync(string companyId, string ownerUserId, string premisesId, string subscriberRef, CancellationToken ct = default) => _Unreachable();
        public Task<string> UnlinkPremisesSubscriberAsync(string companyId, string ownerUserId, string premisesId, string subscriberRef, CancellationToken ct = default) => _Unreachable();
    }

    // ── مساعدات البناء ─────────────────────────────────────────────────────────

    private static SadaraDbContext NewInMemoryContext(string dbName, ICurrentTenant tenant)
        => new(new DbContextOptionsBuilder<SadaraDbContext>()
            .UseInMemoryDatabase(dbName)
            .Options, tenant);

    /// <summary>يبني SasAgentController مع سياق مستخدم محدد (JWT claims).</summary>
    private static SasAgentController BuildController(
        SadaraDbContext db,
        ICurrentTenant tenant,
        Guid currentUserId,
        ISecretProtector? protector = null)
    {
        var fakeSas = new UnreachableSasClient();
        var ctrl = new SasAgentController(
            db,
            tenant,
            protector ?? new FakeSecretProtector(),
            fakeSas,
            NullLogger<SasAgentController>.Instance);

        // حقن ClaimsPrincipal كمستخدم مصادَق
        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, currentUserId.ToString()),
            new(ClaimTypes.Role, "Employee"),
        };
        var identity = new ClaimsIdentity(claims, "TestScheme");
        ctrl.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(identity),
            }
        };

        return ctrl;
    }

    /// <summary>يزرع حساب ساس عبر سياق النظام (bypass).</summary>
    private static SasAccount SeedAccount(
        string dbName,
        Guid accountId,
        Guid companyId,
        Guid ownerUserId,
        bool isDeleted = false)
    {
        var systemTenant = new FakeTenant { BypassTenantFilter = true, IsSuperAdmin = true };
        using var seed = NewInMemoryContext(dbName, systemTenant);

        // نحتاج User و Company لأن EF InMemory يطبّق قيود FK عبر navigation ولكن
        // المزوّد InMemory لا يطبّق FK حقيقية — يكفي إدراج الحساب مباشرةً.
        var account = new SasAccount
        {
            Id         = accountId,
            CompanyId  = companyId,
            OwnerUserId = ownerUserId,
            Label      = "حساب اختبار",
            ServerUrl  = "http://sas.test",
            Username   = "testuser",
            PasswordEncrypted = "FAKE:dGVzdHBhc3M=",
            AccountType = SasAccountType.SasManager,
            IsActive   = true,
            IsDeleted  = isDeleted,
        };
        seed.SasAccounts.Add(account);
        seed.SaveChanges();
        return account;
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 1) عزل الشركات
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task CompanyA_User_Cannot_Access_CompanyB_Account_Returns_NotFound()
    {
        var dbName = Guid.NewGuid().ToString();
        var accountId = Guid.NewGuid();

        // نزرع حساباً لشركة ب
        SeedAccount(dbName, accountId, CompanyB, UserA2);

        // مستخدم شركة أ يحاول الوصول
        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA1);

        var result = await ctrl.UpdateAccount(
            accountId,
            new UpdateSasAccountRequest(null, null, null, null, null, null),
            CancellationToken.None);

        // يجب NotFound — الحساب غير مرئي عبر GetOwnedAccountAsync
        Assert.IsType<NotFoundObjectResult>(result);
    }

    [Fact]
    public async Task CompanyA_User_Cannot_Delete_CompanyB_Account_Returns_NotFound()
    {
        var dbName = Guid.NewGuid().ToString();
        var accountId = Guid.NewGuid();
        SeedAccount(dbName, accountId, CompanyB, UserA2);

        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA1);

        var result = await ctrl.DeleteAccount(accountId, CancellationToken.None);

        Assert.IsType<NotFoundObjectResult>(result);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 2) عزل المالك
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task SameCompany_DifferentOwner_Returns_NotFound()
    {
        var dbName = Guid.NewGuid().ToString();
        var accountId = Guid.NewGuid();

        // الحساب يخصّ UserA2 (نفس الشركة لكن مستخدم مختلف)
        SeedAccount(dbName, accountId, CompanyA, UserA2);

        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewInMemoryContext(dbName, tenantA);
        // المتحكّم يعمل كـ UserA1
        var ctrl = BuildController(db, tenantA, UserA1);

        var result = await ctrl.UpdateAccount(
            accountId,
            new UpdateSasAccountRequest(null, null, null, null, null, null),
            CancellationToken.None);

        Assert.IsType<NotFoundObjectResult>(result);
    }

    [Fact]
    public async Task SameCompany_DifferentOwner_Delete_Returns_NotFound()
    {
        var dbName = Guid.NewGuid().ToString();
        var accountId = Guid.NewGuid();
        SeedAccount(dbName, accountId, CompanyA, UserA2);

        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA1);

        var result = await ctrl.DeleteAccount(accountId, CancellationToken.None);

        Assert.IsType<NotFoundObjectResult>(result);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 3) حارس النطاق — SuperAdmin / CompanyId == null
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task NullCompanyId_GetAccounts_Returns_Forbid()
    {
        var dbName = Guid.NewGuid().ToString();
        var superAdminTenant = new FakeTenant { CompanyId = null, IsSuperAdmin = true, BypassTenantFilter = true };
        using var db = NewInMemoryContext(dbName, superAdminTenant);
        var ctrl = BuildController(db, superAdminTenant, UserA1);

        var result = await ctrl.GetAccounts(CancellationToken.None);

        Assert.IsType<ForbidResult>(result);
    }

    [Fact]
    public async Task NullCompanyId_CreateAccount_Returns_Forbid()
    {
        var dbName = Guid.NewGuid().ToString();
        var superAdminTenant = new FakeTenant { CompanyId = null, IsSuperAdmin = true, BypassTenantFilter = true };
        using var db = NewInMemoryContext(dbName, superAdminTenant);
        var ctrl = BuildController(db, superAdminTenant, UserA1);

        var result = await ctrl.CreateAccount(
            new CreateSasAccountRequest("label", "http://srv", "user", "pass", SasAccountType.SasManager, true),
            CancellationToken.None);

        Assert.IsType<ForbidResult>(result);
    }

    [Fact]
    public async Task EmptyCompanyId_GetAccounts_Returns_Forbid()
    {
        var dbName = Guid.NewGuid().ToString();
        // Guid.Empty يُعامَل كـ null في TryResolveScope
        var emptyTenant = new FakeTenant { CompanyId = Guid.Empty, BypassTenantFilter = false };
        using var db = NewInMemoryContext(dbName, emptyTenant);
        var ctrl = BuildController(db, emptyTenant, UserA1);

        var result = await ctrl.GetAccounts(CancellationToken.None);

        Assert.IsType<ForbidResult>(result);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 4) ختم الإنشاء
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task CreateAccount_Stamps_CompanyId_And_OwnerId_From_Context_Not_Body()
    {
        var dbName = Guid.NewGuid().ToString();
        var protector = new FakeSecretProtector();
        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA1, protector);

        var result = await ctrl.CreateAccount(
            new CreateSasAccountRequest("mylabel", "http://sas.internal", "agentuser", "s3cr3t", SasAccountType.SasManager, true),
            CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(result);
        Assert.Equal(200, ok.StatusCode);

        // تحقّق من القاعدة
        var systemTenant = new FakeTenant { BypassTenantFilter = true, IsSuperAdmin = true };
        using var check = NewInMemoryContext(dbName, systemTenant);
        var saved = Assert.Single(check.SasAccounts.ToList());

        // الختم: CompanyId وOwnerUserId من السياق
        Assert.Equal(CompanyA, saved.CompanyId);
        Assert.Equal(UserA1, saved.OwnerUserId);

        // Protect استُدعي مرة واحدة
        Assert.Equal(1, protector.ProtectCallCount);

        // كلمة المرور مشفّرة (لا تساوي النص الصريح)
        Assert.NotEqual("s3cr3t", saved.PasswordEncrypted);
        Assert.False(string.IsNullOrEmpty(saved.PasswordEncrypted));
    }

    [Fact]
    public async Task CreateAccount_Dto_Does_Not_Contain_Password_Field()
    {
        // SasAccountDto يجب ألا يحتوي أي خاصية اسمها Password أو PasswordEncrypted
        var dtoType = typeof(SasAccountDto);

        var passwordProps = dtoType
            .GetProperties()
            .Where(p => p.Name.Contains("assword", StringComparison.OrdinalIgnoreCase)
                     || p.Name.Contains("ecret",  StringComparison.OrdinalIgnoreCase))
            .ToList();

        Assert.Empty(passwordProps); // لا خصائص كلمة مرور في الـ DTO
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 5) failClosed — اختبار وحدة RequirePermissionAttribute.HasPermission
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public void HasPermission_NullJson_FailClosed_True_Returns_False()
    {
        var result = RequirePermissionAttribute.HasPermission(null, "sas_agent", "view", failClosed: true);
        Assert.False(result);
    }

    [Fact]
    public void HasPermission_EmptyJson_FailClosed_True_Returns_False()
    {
        var result = RequirePermissionAttribute.HasPermission("", "sas_agent", "view", failClosed: true);
        Assert.False(result);
    }

    [Fact]
    public void HasPermission_NullJson_FailClosed_False_Returns_True()
    {
        var result = RequirePermissionAttribute.HasPermission(null, "sas_agent", "view", failClosed: false);
        Assert.True(result);
    }

    [Fact]
    public void HasPermission_EmptyJson_FailClosed_False_Returns_True()
    {
        var result = RequirePermissionAttribute.HasPermission("", "sas_agent", "view", failClosed: false);
        Assert.True(result);
    }

    [Fact]
    public void HasPermission_ExplicitGrant_Returns_True()
    {
        const string json = """{"sas_agent":{"view":true,"manage":false}}""";
        Assert.True(RequirePermissionAttribute.HasPermission(json, "sas_agent", "view", failClosed: true));
        Assert.False(RequirePermissionAttribute.HasPermission(json, "sas_agent", "manage", failClosed: true));
    }

    [Fact]
    public void HasPermission_ExplicitDeny_Returns_False_Regardless_Of_FailClosed()
    {
        const string json = """{"sas_agent":{"view":false}}""";
        Assert.False(RequirePermissionAttribute.HasPermission(json, "sas_agent", "view", failClosed: true));
        Assert.False(RequirePermissionAttribute.HasPermission(json, "sas_agent", "view", failClosed: false));
    }

    [Fact]
    public void HasPermission_MalformedJson_Returns_False()
    {
        Assert.False(RequirePermissionAttribute.HasPermission("{NOTJSON}", "sas_agent", "view", failClosed: false));
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 6) SecretProtector — اختبار وحدة FakeSecretProtector (نظير للتحقّق من عقد الواجهة)
    //    ملاحظة: SecretProtector الحقيقي يعتمد على Data Protection (مفتاح في نظام الملفات/DPAPI).
    //    اختباره عبر unit test يتطلّب IDataProtectionProvider حقيقي؛ نختبر الـ fake هنا للعقد،
    //    وإن أُريد اختبار التنفيذ الحقيقي يُضاف اختبار تكامل منفصل مع EphemeralDataProtector.
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public void FakeSecretProtector_ProtectUnprotect_RoundTrip_Succeeds()
    {
        var protector = new FakeSecretProtector();
        const string plain = "my_secret_password_123";

        var cipher = protector.Protect(plain);
        var roundTripped = protector.Unprotect(cipher);

        Assert.Equal(plain, roundTripped);
        Assert.NotEqual(plain, cipher);
        Assert.False(string.IsNullOrEmpty(cipher));
    }

    [Fact]
    public void FakeSecretProtector_EmptyString_Returns_EmptyString()
    {
        var protector = new FakeSecretProtector();
        Assert.Equal(string.Empty, protector.Protect(string.Empty));
        Assert.Equal(string.Empty, protector.Unprotect(string.Empty));
    }

    [Fact]
    public void RealSecretProtector_Contract_ProtectUnprotect_RoundTrip()
    {
        // اختبار SecretProtector الحقيقي باستخدام EphemeralDataProtectionProvider
        // (لا يعتمد على نظام الملفات — آمن في بيئة CI)
        var provider = new Microsoft.AspNetCore.DataProtection.EphemeralDataProtectionProvider();
        var protector = new Sadara.Infrastructure.Services.Security.SecretProtector(provider);
        const string plain = "SasAgentPassword!42";

        var cipher = protector.Protect(plain);
        var recovered = protector.Unprotect(cipher);

        Assert.Equal(plain, recovered);
        Assert.NotEqual(plain, cipher);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // اختبارات إضافية: حذف ناعم — حساب محذوف لا يرى
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task SoftDeleted_Account_Returns_NotFound()
    {
        var dbName = Guid.NewGuid().ToString();
        var accountId = Guid.NewGuid();
        // نزرع حساباً محذوفاً بالمالك الصحيح
        SeedAccount(dbName, accountId, CompanyA, UserA1, isDeleted: true);

        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA1);

        // الحساب محذوف — GetOwnedAccountAsync يقصيه (!IsDeleted)
        var result = await ctrl.DeleteAccount(accountId, CancellationToken.None);

        Assert.IsType<NotFoundObjectResult>(result);
    }

    [Fact]
    public async Task OwnedAccount_GetAccounts_Returns_OnlyOwnersAccounts()
    {
        var dbName = Guid.NewGuid().ToString();
        var idOwned  = Guid.NewGuid();
        var idOther  = Guid.NewGuid();

        SeedAccount(dbName, idOwned,  CompanyA, UserA1);
        SeedAccount(dbName, idOther,  CompanyA, UserA2); // نفس الشركة، مالك آخر

        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA1);

        var result = await ctrl.GetAccounts(CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(result);
        // نتحقّق أن total == 1 (الحساب الخاص بـ UserA1 فقط)
        // نستخدم JSON لاستخراج الخصائص من anonymous object (غير قابل للوصول dynamic خارج التجميع)
        var json = System.Text.Json.JsonSerializer.Serialize(ok.Value);
        var doc  = System.Text.Json.JsonDocument.Parse(json);
        var total = doc.RootElement.GetProperty("total").GetInt32();
        Assert.Equal(1, total);
    }
}
