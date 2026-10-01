using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Sadara.Application.Interfaces;
using Sadara.API.Controllers;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Data;
using Sadara.Infrastructure.Services.Sas;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// اختبارات تكامل لميزة «إدارة الوكلاء» — النقطة GET /api/sas-agent/admin/agents (GetAdminAgents).
///
/// تغطّي:
///   1. حجب الدور: مستخدم غير أدمن (Employee) => Forbid (403) رغم صلاحية sas_agent.
///   2. نجاح الأدمن: CompanyAdmin بشركة فيها حسابات لعدّة ملّاك => 200 + قائمة مجمّعة (userId/accounts/totals).
///   3. عزل الشركة: أدمن شركة-أ لا يرى وكلاء/حسابات شركة-ب إطلاقاً.
///   4. عدم تسريب الأسرار: لا PasswordEncrypted / كلمة مرور في جسم الرد (فحص نصّي).
///   5. تدهور رشيق: عند SasServiceUnavailableException => reconciliation=null بدل فشل الطلب.
///   6. دمج المقاطعة: totals تُجمَّع من ملخّص خدمة الساس (declared/actual).
///   7. رفض بلا شركة: SuperAdmin/سياق نظام (بلا CompanyId) => Forbid (النقطة company-scoped).
///
/// الأسلوب: استدعاء المتحكّم مباشرةً (unit-level) مع مضاعفات ICurrentTenant/ISecretProtector/ISasServiceClient
/// وقاعدة EF InMemory — بنفس نمط SasAgentExtendedTests / SasAgentIsolationTests.
///
/// ملاحظة: بما أنّ الاستدعاء مباشر، فلتر [RequirePermission] لا يُنفَّذ؛ الحجب هنا يقع عبر
/// منطق المتحكّم الداخلي: TryResolveScope + IsCompanyAdminOrAbove. صلاحية sas_agent
/// (فلتر السمة) تُختبَر في مسار المصادقة الكامل لا هنا.
/// </summary>
public class SasAgentAdminAgentsTests
{
    // ── ثوابت ─────────────────────────────────────────────────────────────────
    private static readonly Guid CompanyA = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid CompanyB = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");

    private static readonly Guid AdminA   = Guid.Parse("a0a0a0a0-a0a0-a0a0-a0a0-a0a0a0a0a0a0");
    private static readonly Guid OwnerA1  = Guid.Parse("a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1");
    private static readonly Guid OwnerA2  = Guid.Parse("a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2");

    private static readonly Guid AdminB   = Guid.Parse("b0b0b0b0-b0b0-b0b0-b0b0-b0b0b0b0b0b0");
    private static readonly Guid OwnerB1  = Guid.Parse("b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1");

    // ── Fakes ─────────────────────────────────────────────────────────────────

    private sealed class FakeTenant : ICurrentTenant
    {
        public Guid? CompanyId { get; init; }
        public bool IsSuperAdmin { get; init; }
        public bool BypassTenantFilter { get; init; }
        public Guid? DefaultCompanyId { get; init; }
        public bool EnforceIsolation { get; init; }
    }

    private sealed class FakeProtector : ISecretProtector
    {
        public string Protect(string p) => "FAKE:" + Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(p));
        public string Unprotect(string c) => string.IsNullOrEmpty(c) ? string.Empty
            : System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(c[5..]));
    }

    /// <summary>
    /// ISasServiceClient مضاعف يخصّ agents-summary: ردّ JSON قابل للضبط + التقاط النداءات،
    /// وخيار إطلاق SasServiceUnavailableException لاختبار التدهور الرشيق.
    /// كل الأعضاء الأخرى تُطلق استثناءً (لا يجب أن تُستدعى في هذه النقطة).
    /// </summary>
    private sealed class SummaryOnlySasClient : ISasServiceClient
    {
        public string AgentsSummaryJson { get; set; } = """{"items":[]}""";
        public bool ThrowUnavailable { get; set; }
        public List<(string CompanyId, List<string> AccountIds)> Calls { get; } = [];

        public Task<string> GetAgentsSummaryAsync(string companyId, IEnumerable<string> accountIds, CancellationToken ct = default)
        {
            Calls.Add((companyId, accountIds.ToList()));
            if (ThrowUnavailable)
                throw new SasServiceUnavailableException("خدمة الساس غير متاحة");
            return Task.FromResult(AgentsSummaryJson);
        }

        private static Task<string> Nope() => throw new InvalidOperationException("لا يجب استدعاؤها في نقطة admin/agents");

        public Task<SasLoginResult> LoginAsync(string s, string u, string p, CancellationToken ct = default) => throw new InvalidOperationException("لا يجب استدعاؤها");
        public Task<string> GetDashboardAsync(string s, string u, string p, CancellationToken ct = default) => Nope();
        public Task<string> GetSubscribersAsync(string s, string u, string p, IDictionary<string, string?>? q = null, CancellationToken ct = default) => Nope();
        public Task<string> GetReportAsync(string s, string u, string p, IDictionary<string, string?>? q = null, CancellationToken ct = default) => Nope();
        public Task<string> GetPackagesAsync(string s, string u, string p, CancellationToken ct = default) => Nope();
        public Task<string> GetFinanceAsync(string s, string u, string p, CancellationToken ct = default) => Nope();
        public Task<string> GetHealthAsync(string s, string u, string p, CancellationToken ct = default) => Nope();
        public Task<string> GetRenewalCandidatesAsync(string s, string u, string p, int? d = null, string? q = null, CancellationToken ct = default) => Nope();
        public Task<string> BulkRenewAsync(string s, string u, string p, IEnumerable<string> ids, int m, string? pid = null, bool dry = false, CancellationToken ct = default) => Nope();
        public Task<string> GetUserDetailAsync(string s, string u, string p, string uid, CancellationToken ct = default) => Nope();
        public Task<string> GetUserOverviewAsync(string s, string u, string p, string uid, CancellationToken ct = default) => Nope();
        public Task<string> GetUserHistoryAsync(string s, string u, string p, string uid, CancellationToken ct = default) => Nope();
        public Task<string> GetUserExtendDataAsync(string s, string u, string p, string uid, CancellationToken ct = default) => Nope();
        public Task<string> UserActionAsync(string s, string u, string p, string uid, string action, object? pms = null, CancellationToken ct = default) => Nope();
        public Task<string> UsersBulkActionAsync(string s, string u, string p, IEnumerable<string> uids, string action, object? pms = null, CancellationToken ct = default) => Nope();
        public Task<string> CreateUserAsync(string s, string u, string p, object payload, CancellationToken ct = default) => Nope();
        public Task<string> UpdateUserAsync(string s, string u, string p, string uid, object payload, CancellationToken ct = default) => Nope();
        public Task<string> DeleteUserAsync(string s, string u, string p, string uid, CancellationToken ct = default) => Nope();
        public Task<string> GetUserRefundDataAsync(string s, string u, string p, string uid, CancellationToken ct = default) => Nope();
        public Task<string> RefundUserAsync(string s, string u, string p, string uid, CancellationToken ct = default) => Nope();
        public Task<string> GetOnlineAsync(string s, string u, string p, CancellationToken ct = default) => Nope();
        public Task<string> GetManagersAsync(string s, string u, string p, CancellationToken ct = default) => Nope();
        public Task<string> ManagerActionAsync(string s, string u, string p, string mid, string action, object? pms = null, CancellationToken ct = default) => Nope();
        public Task<string> DeleteManagerAsync(string s, string u, string p, string mid, CancellationToken ct = default) => Nope();
        public Task<string> SasGetAsync(string s, string u, string p, string path, CancellationToken ct = default) => Nope();
        public Task<string> SasPostAsync(string s, string u, string p, string path, object? payload = null, CancellationToken ct = default) => Nope();
        public Task<string> TestAccountAsync(string s, string u, string p, CancellationToken ct = default) => Nope();
        public Task<string> SyncAccountAsync(string s, string u, string p, string accountId, CancellationToken ct = default) => Nope();
        public Task<string> GetLocalSubscribersAsync(string accountId, string? search = null, string? status = null, bool? expiring = null, int? page = null, int? count = null, CancellationToken ct = default) => Nope();
        public Task<string> GetSubscribersSummaryAsync(string accountId, CancellationToken ct = default) => Nope();
        public Task<string> SubmitReportAsync(string accountId, string companyId, string ownerUserId, int declaredTotal, int declaredActive, string? note = null, string? submittedBy = null, CancellationToken ct = default) => Nope();
        public Task<string> ListReportsAsync(string accountId, CancellationToken ct = default) => Nope();
        public Task<string> GetReconciliationAsync(string accountId, string s, string u, string p, CancellationToken ct = default) => Nope();
        public Task<string> GetTicketsStatsAsync(string companyId, string ownerUserId, CancellationToken ct = default) => Nope();
        public Task<string> GetTicketsListAsync(string companyId, string ownerUserId, string? status = null, string? category = null, string? search = null, int? page = null, int? count = null, CancellationToken ct = default) => Nope();
        public Task<string> GetTicketAsync(string companyId, string ownerUserId, string ticketId, CancellationToken ct = default) => Nope();
        public Task<string> CreateTicketAsync(string companyId, string ownerUserId, string subject, string body, string? category = null, string? priority = null, string? subscriberRef = null, string? createdBy = null, CancellationToken ct = default) => Nope();
        public Task<string> ReplyTicketAsync(string companyId, string ownerUserId, string ticketId, string body, bool? isInternal = null, string? author = null, CancellationToken ct = default) => Nope();
        public Task<string> UpdateTicketAsync(string companyId, string ownerUserId, string ticketId, string? status = null, string? priority = null, string? category = null, CancellationToken ct = default) => Nope();
        public Task<string> GetPremisesListAsync(string companyId, string ownerUserId, string? search = null, string? ownership = null, string? ptype = null, int? page = null, int? count = null, CancellationToken ct = default) => Nope();
        public Task<string> GetPremisesAsync(string companyId, string ownerUserId, string premisesId, CancellationToken ct = default) => Nope();
        public Task<string> GetPremisesSubscribersAsync(string companyId, string ownerUserId, string premisesId, CancellationToken ct = default) => Nope();
        public Task<string> GetPremisesBySubscriberAsync(string companyId, string ownerUserId, string subscriberRef, CancellationToken ct = default) => Nope();
        public Task<string> GetPremisesLinkCandidatesAsync(string companyId, string ownerUserId, string? search = null, CancellationToken ct = default) => Nope();
        public Task<string> GetPremisesPhotoAsync(string companyId, string ownerUserId, string premisesId, CancellationToken ct = default) => Nope();
        public Task<string> CreatePremisesAsync(string companyId, string ownerUserId, string governorate, string area, string landmark, double? lat = null, double? lon = null, string? phone = null, string? ownership = null, string? ptype = null, string? createdBy = null, CancellationToken ct = default) => Nope();
        public Task<string> UpdatePremisesAsync(string companyId, string ownerUserId, string premisesId, string? governorate = null, string? area = null, string? landmark = null, double? lat = null, double? lon = null, string? phone = null, string? ownership = null, string? ptype = null, CancellationToken ct = default) => Nope();
        public Task<string> DeletePremisesAsync(string companyId, string ownerUserId, string premisesId, CancellationToken ct = default) => Nope();
        public Task<string> UploadPremisesPhotoAsync(string companyId, string ownerUserId, string premisesId, string imageBase64, string ext, CancellationToken ct = default) => Nope();
        public Task<string> LinkPremisesSubscriberAsync(string companyId, string ownerUserId, string premisesId, string subscriberRef, CancellationToken ct = default) => Nope();
        public Task<string> UnlinkPremisesSubscriberAsync(string companyId, string ownerUserId, string premisesId, string subscriberRef, CancellationToken ct = default) => Nope();
    }

    // ── مساعدات ────────────────────────────────────────────────────────────────

    private static SadaraDbContext NewInMemoryContext(string dbName, ICurrentTenant tenant)
        => new(new DbContextOptionsBuilder<SadaraDbContext>()
            .UseInMemoryDatabase(dbName).Options, tenant);

    /// <summary>يبني المتحكّم مع دور محدّد (role_id) لضبط IsCompanyAdminOrAbove.</summary>
    private static SasAgentController BuildController(
        SadaraDbContext db,
        ICurrentTenant tenant,
        Guid currentUserId,
        UserRole role,
        ISasServiceClient sasClient)
    {
        var uow = new Sadara.Infrastructure.Repositories.UnitOfWork(db);
        var accounting = new Sadara.API.Services.SubscriptionAccountingService(
            uow, NullLogger<Sadara.API.Services.SubscriptionAccountingService>.Instance);
        var ctrl = new SasAgentController(
            db,
            tenant,
            new FakeProtector(),
            sasClient,
            NullLogger<SasAgentController>.Instance,
            uow,
            accounting);

        // role_id يُقرأ أولاً في IsCompanyAdminOrAbove (CompanyAdmin=20).
        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, currentUserId.ToString()),
            new("role_id", ((int)role).ToString()),
        };
        ctrl.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(new ClaimsIdentity(claims, "TestScheme")),
            }
        };
        return ctrl;
    }

    /// <summary>يزرع حساب ساس + مالكه (User) عبر سياق النظام (bypass).</summary>
    private static void SeedAccount(
        string dbName, Guid accountId, Guid companyId, Guid ownerUserId,
        string label = "حساب", string ownerName = "مالك", bool isDeleted = false)
    {
        var sysTenant = new FakeTenant { BypassTenantFilter = true, IsSuperAdmin = true };
        using var seed = NewInMemoryContext(dbName, sysTenant);

        if (!seed.Users.Any(u => u.Id == ownerUserId))
        {
            seed.Users.Add(new User
            {
                Id = ownerUserId,
                Username = "u_" + ownerUserId.ToString()[..8],
                FullName = ownerName,
                CompanyId = companyId,
                Role = UserRole.Employee,
            });
        }

        seed.SasAccounts.Add(new SasAccount
        {
            Id = accountId,
            CompanyId = companyId,
            OwnerUserId = ownerUserId,
            Label = label,
            ServerUrl = "http://sas.test",
            Username = "sas_" + label,
            // سرّ مميّز يمكن البحث عنه في الرد لإثبات عدم التسريب.
            PasswordEncrypted = "FAKE:" + Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes("SECRET_" + label)),
            AccountType = SasAccountType.SasManager,
            IsActive = true,
            IsDeleted = isDeleted,
        });
        seed.SaveChanges();
    }

    /// <summary>
    /// خيارات تحاكي خطّ ASP.NET Core الفعلي (camelCase) عند تسلسل قيمة الاستجابة —
    /// حتى تطابق أسماء الحقول ما يراه العميل (userId/fullName/accounts/reconciliation…).
    /// </summary>
    private static readonly JsonSerializerOptions CamelCase = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    /// <summary>يفكّ OkObjectResult الملفوف {success,data,total} إلى JsonDocument (camelCase).</summary>
    private static JsonDocument ParseOk(IActionResult result)
    {
        var ok = Assert.IsType<OkObjectResult>(result);
        var json = JsonSerializer.Serialize(ok.Value, CamelCase);
        return JsonDocument.Parse(json);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 1) حجب الدور — موظّف غير أدمن => Forbid (403)
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task GetAdminAgents_NonAdminEmployee_Returns_Forbid()
    {
        var dbName = Guid.NewGuid().ToString();
        SeedAccount(dbName, Guid.NewGuid(), CompanyA, OwnerA1);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var sas = new SummaryOnlySasClient();
        // موظّف عادي (Employee=10) لديه سياق شركة صالح لكنه ليس CompanyAdmin.
        var ctrl = BuildController(db, tenantA, AdminA, UserRole.Employee, sas);

        var result = await ctrl.GetAdminAgents(CancellationToken.None);

        Assert.IsType<ForbidResult>(result);
        // لا يجب استدعاء خدمة الساس عند رفض الدور (fail-closed قبل أي عمل).
        Assert.Empty(sas.Calls);
    }

    [Fact]
    public async Task GetAdminAgents_ManagerRole_BelowCompanyAdmin_Returns_Forbid()
    {
        // Manager=14 < CompanyAdmin=20 => يجب الرفض.
        var dbName = Guid.NewGuid().ToString();
        SeedAccount(dbName, Guid.NewGuid(), CompanyA, OwnerA1);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, AdminA, UserRole.Manager, new SummaryOnlySasClient());

        var result = await ctrl.GetAdminAgents(CancellationToken.None);

        Assert.IsType<ForbidResult>(result);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 2) نجاح الأدمن — CompanyAdmin يرى وكلاء شركته مجمّعين
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task GetAdminAgents_CompanyAdmin_Returns_AggregatedAgents()
    {
        var dbName = Guid.NewGuid().ToString();
        var acc1 = Guid.NewGuid();  // مالك A1
        var acc2 = Guid.NewGuid();  // مالك A1 (حساب ثانٍ لنفس الوكيل)
        var acc3 = Guid.NewGuid();  // مالك A2

        SeedAccount(dbName, acc1, CompanyA, OwnerA1, label: "A1-حساب1", ownerName: "وكيل واحد");
        SeedAccount(dbName, acc2, CompanyA, OwnerA1, label: "A1-حساب2", ownerName: "وكيل واحد");
        SeedAccount(dbName, acc3, CompanyA, OwnerA2, label: "A2-حساب1", ownerName: "وكيل اثنان");

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, AdminA, UserRole.CompanyAdmin, new SummaryOnlySasClient());

        var result = await ctrl.GetAdminAgents(CancellationToken.None);

        using var doc = ParseOk(result);
        var root = doc.RootElement;
        Assert.True(root.GetProperty("success").GetBoolean());
        Assert.Equal(2, root.GetProperty("total").GetInt32());   // وكيلان (A1, A2)

        var data = root.GetProperty("data");
        Assert.Equal(2, data.GetArrayLength());

        // العثور على وكيل A1 (له حسابان)
        JsonElement? agentA1 = null;
        foreach (var a in data.EnumerateArray())
            if (a.GetProperty("userId").GetGuid() == OwnerA1)
                agentA1 = a;

        Assert.True(agentA1.HasValue, "يجب أن يظهر الوكيل A1");
        Assert.Equal("وكيل واحد", agentA1!.Value.GetProperty("fullName").GetString());
        Assert.Equal(2, agentA1.Value.GetProperty("accounts").GetArrayLength());
        Assert.Equal(2, agentA1.Value.GetProperty("totals").GetProperty("accounts").GetInt32());
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 3) عزل الشركة — أدمن A لا يرى وكلاء/حسابات B
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task GetAdminAgents_CompanyAdminA_Does_Not_See_CompanyB()
    {
        var dbName = Guid.NewGuid().ToString();
        var accA = Guid.NewGuid();
        var accB = Guid.NewGuid();

        SeedAccount(dbName, accA, CompanyA, OwnerA1, label: "A-حساب", ownerName: "وكيل أ");
        SeedAccount(dbName, accB, CompanyB, OwnerB1, label: "B-حساب", ownerName: "وكيل ب");

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var sas = new SummaryOnlySasClient();
        var ctrl = BuildController(db, tenantA, AdminA, UserRole.CompanyAdmin, sas);

        var result = await ctrl.GetAdminAgents(CancellationToken.None);

        using var doc = ParseOk(result);
        var root = doc.RootElement;
        Assert.Equal(1, root.GetProperty("total").GetInt32());   // وكيل واحد فقط (أ)

        var data = root.GetProperty("data");
        foreach (var agent in data.EnumerateArray())
        {
            Assert.NotEqual(OwnerB1, agent.GetProperty("userId").GetGuid());
            foreach (var acc in agent.GetProperty("accounts").EnumerateArray())
                Assert.NotEqual(accB, acc.GetProperty("id").GetGuid());
        }

        // خدمة الساس تُستدعى بمعرّف شركة-أ فقط، وقائمة الحسابات لا تحوي حساب-ب.
        Assert.Single(sas.Calls);
        Assert.Equal(CompanyA.ToString(), sas.Calls[0].CompanyId);
        Assert.DoesNotContain(accB.ToString(), sas.Calls[0].AccountIds);
        Assert.Contains(accA.ToString(), sas.Calls[0].AccountIds);
    }

    [Fact]
    public async Task GetAdminAgents_EmptyCompany_Returns_EmptyList_WithoutCallingSas()
    {
        var dbName = Guid.NewGuid().ToString();
        // حساب لشركة-ب فقط؛ أدمن-أ يستعلم فلا يجد شيئاً.
        SeedAccount(dbName, Guid.NewGuid(), CompanyB, OwnerB1);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var sas = new SummaryOnlySasClient();
        var ctrl = BuildController(db, tenantA, AdminA, UserRole.CompanyAdmin, sas);

        var result = await ctrl.GetAdminAgents(CancellationToken.None);

        using var doc = ParseOk(result);
        Assert.Equal(0, doc.RootElement.GetProperty("total").GetInt32());
        Assert.Empty(doc.RootElement.GetProperty("data").EnumerateArray());
        // لا حسابات => لا نداء لخدمة الساس (المتحكّم يعود مبكّراً).
        Assert.Empty(sas.Calls);
    }

    [Fact]
    public async Task GetAdminAgents_DeletedAccounts_Excluded()
    {
        var dbName = Guid.NewGuid().ToString();
        SeedAccount(dbName, Guid.NewGuid(), CompanyA, OwnerA1, label: "محذوف", isDeleted: true);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, AdminA, UserRole.CompanyAdmin, new SummaryOnlySasClient());

        var result = await ctrl.GetAdminAgents(CancellationToken.None);

        using var doc = ParseOk(result);
        Assert.Equal(0, doc.RootElement.GetProperty("total").GetInt32());
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 4) عدم تسريب الأسرار — لا PasswordEncrypted/كلمة مرور في الرد
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task GetAdminAgents_Response_Does_Not_Leak_Secrets()
    {
        var dbName = Guid.NewGuid().ToString();
        SeedAccount(dbName, Guid.NewGuid(), CompanyA, OwnerA1, label: "لبن", ownerName: "وكيل");
        SeedAccount(dbName, Guid.NewGuid(), CompanyA, OwnerA2, label: "عسل", ownerName: "وكيل2");

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, AdminA, UserRole.CompanyAdmin, new SummaryOnlySasClient());

        var result = await ctrl.GetAdminAgents(CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(result);
        var json = JsonSerializer.Serialize(ok.Value, CamelCase);

        // فحص نصّي صريح: لا أثر لأي حقل/قيمة سرّية.
        Assert.DoesNotContain("PasswordEncrypted", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("passwordEncrypted", json);
        Assert.DoesNotContain("password", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("SECRET_", json);            // القيمة المزروعة داخل PasswordEncrypted
        Assert.DoesNotContain("FAKE:", json);              // بادئة التشفير الوهمي
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 5) تدهور رشيق — خدمة الساس غير متاحة => reconciliation=null بدل فشل
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task GetAdminAgents_SasUnavailable_Returns_200_With_Null_Reconciliation()
    {
        var dbName = Guid.NewGuid().ToString();
        SeedAccount(dbName, Guid.NewGuid(), CompanyA, OwnerA1, label: "حساب", ownerName: "وكيل");

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var sas = new SummaryOnlySasClient { ThrowUnavailable = true };
        var ctrl = BuildController(db, tenantA, AdminA, UserRole.CompanyAdmin, sas);

        var result = await ctrl.GetAdminAgents(CancellationToken.None);

        using var doc = ParseOk(result);
        var root = doc.RootElement;
        Assert.True(root.GetProperty("success").GetBoolean());
        Assert.Equal(1, root.GetProperty("total").GetInt32());

        // reconciliation يجب أن تكون null (تدهور رشيق) وليس فشل الطلب.
        var account = root.GetProperty("data")[0].GetProperty("accounts")[0];
        var recon = account.GetProperty("reconciliation");
        Assert.Equal(JsonValueKind.Null, recon.ValueKind);

        // totals تبقى صفرية (لا مقاطعة).
        var totals = root.GetProperty("data")[0].GetProperty("totals");
        Assert.Equal(0, totals.GetProperty("declared").GetInt32());
        Assert.Equal(0, totals.GetProperty("actual").GetInt32());
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 6) دمج المقاطعة — totals تُجمَّع من ملخّص خدمة الساس
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task GetAdminAgents_MergesReconciliation_From_SasSummary()
    {
        var dbName = Guid.NewGuid().ToString();
        var acc1 = Guid.NewGuid();
        var acc2 = Guid.NewGuid();
        SeedAccount(dbName, acc1, CompanyA, OwnerA1, label: "ح1", ownerName: "وكيل");
        SeedAccount(dbName, acc2, CompanyA, OwnerA1, label: "ح2", ownerName: "وكيل");

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);

        // ملخّص خدمة الساس: حسابان بمُصرَّح/فعلي مختلفَين.
        var summary = new
        {
            items = new object[]
            {
                new { account_id = acc1.ToString(), declared_total = 100, declared_active = 90, actual_total = 98, actual_active = 88, diff = 2, verdict = "matched", last_sync = "2026-01-01T00:00:00Z" },
                new { account_id = acc2.ToString(), declared_total = 50,  declared_active = 40, actual_total = 30, actual_active = 25, diff = 20, verdict = "company_suspicious", last_sync = "2026-01-02T00:00:00Z" },
            }
        };
        var sas = new SummaryOnlySasClient { AgentsSummaryJson = JsonSerializer.Serialize(summary) };
        var ctrl = BuildController(db, tenantA, AdminA, UserRole.CompanyAdmin, sas);

        var result = await ctrl.GetAdminAgents(CancellationToken.None);

        using var doc = ParseOk(result);
        var agent = doc.RootElement.GetProperty("data")[0];
        var totals = agent.GetProperty("totals");

        // المجاميع = مجموع declared/actual عبر الحسابين.
        Assert.Equal(150, totals.GetProperty("declared").GetInt32());   // 100 + 50
        Assert.Equal(128, totals.GetProperty("actual").GetInt32());     // 98 + 30

        // كل حساب يحمل مقاطعته + حكمه.
        var verdicts = new List<string?>();
        foreach (var acc in agent.GetProperty("accounts").EnumerateArray())
            verdicts.Add(acc.GetProperty("reconciliation").GetProperty("verdict").GetString());
        Assert.Contains("matched", verdicts);
        Assert.Contains("company_suspicious", verdicts);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 7) رفض بلا شركة — SuperAdmin/سياق نظام => Forbid (company-scoped)
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task GetAdminAgents_NoCompanyContext_Returns_Forbid()
    {
        var dbName = Guid.NewGuid().ToString();
        SeedAccount(dbName, Guid.NewGuid(), CompanyA, OwnerA1);

        // بلا CompanyId (سياق نظام/SuperAdmin) — حتى لو الدور SuperAdmin => Forbid.
        var systemTenant = new FakeTenant { CompanyId = null, IsSuperAdmin = true };
        using var db = NewInMemoryContext(dbName, systemTenant);
        var sas = new SummaryOnlySasClient();
        var ctrl = BuildController(db, systemTenant, AdminA, UserRole.SuperAdmin, sas);

        var result = await ctrl.GetAdminAgents(CancellationToken.None);

        Assert.IsType<ForbidResult>(result);
        Assert.Empty(sas.Calls);
    }
}
