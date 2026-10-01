using System.Security.Claims;
using System.Text.Json;
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
using Sadara.Infrastructure.Services.Sas;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// اختبارات SasAgentController الموسّعة — تغطّي المجموعات الجديدة منذ الاختبارات الأولى:
///   1. عزل المشتركين (users) — لا وصول متبادل بين حسابَي شركتَين.
///   2. عزل التذاكر (tickets) — user-scoped: company+owner من التوكن حصراً.
///   3. عزل العقارات (premises) — user-scoped: company+owner من التوكن حصراً.
///   4. نقاط التخزين المحلي (local/sync/report) — accountId من الحساب المملوك لا من الإدخال.
///   5. حدود التحقّق: bulk-action سقف، صورة عقار base64، report validation.
///   6. عدم تسرّب الأسرار: كلمة مرور لا تظهر في أي استجابة.
///   7. PassThrough: SasServiceUnavailableException => 503.
///   8. SubmitReport: submittedBy يأتي من الهوية لا من الجسم.
///   9. BulkRenew: سقف 1000، تنقية الفارغات/المكرّرات.
///  10. SasGet/SasPost: المسار الفارغ => 400.
///  11. CreateTicket: العنوان والنصّ مطلوبان.
///  12. UpdateTicket: رفض إن كل الحقول فارغة.
///  13. CreatePremises: رفض الإحداثيات خارج النطاق.
///  14. UploadPremisesPhoto: رفض base64 غير صالح، سقف الحجم، امتداد غير مدعوم.
///  15. PassThroughWrite: عزل الحساب في عمليات الكتابة (UserAction/DeleteUser/RefundUser…).
/// </summary>
public class SasAgentExtendedTests
{
    // ── ثوابت الاختبار ────────────────────────────────────────────────────────
    private static readonly Guid CompanyA = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid CompanyB = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid UserA    = Guid.Parse("a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1");
    private static readonly Guid UserB    = Guid.Parse("b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1");

    // ── Fakes ────────────────────────────────────────────────────────────────

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
        public int ProtectCallCount { get; private set; }
        public string Protect(string p) { ProtectCallCount++; return "FAKE:" + Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(p)); }
        public string Unprotect(string c) { if (string.IsNullOrEmpty(c)) return string.Empty; return System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(c[5..])); }
    }

    /// <summary>
    /// ISasServiceClient مضاعف قابل للضبط: يعيد استجابة ثابتة أو يطلق استثناءً.
    /// </summary>
    private sealed class ConfigurableSasClient : ISasServiceClient
    {
        public string DefaultResponse { get; set; } = """{"ok":true}""";
        public bool ThrowUnavailable { get; set; } = false;
        public int CallCount { get; private set; }
        public List<string> RecordedCalls { get; } = [];

        // ── دعم /admin/agents-summary (يُستهلك من GetAdminAgents) ──────────────────
        /// <summary>ردّ JSON مخصّص لـ agents-summary؛ إن كان null استُخدم DefaultResponse.</summary>
        public string? AgentsSummaryResponse { get; set; }
        /// <summary>يلتقط (companyId, accountIds) لكل استدعاء لـ GetAgentsSummaryAsync.</summary>
        public List<(string CompanyId, List<string> AccountIds)> AgentsSummaryCalls { get; } = [];

        private Task<string> Handle(string name)
        {
            CallCount++;
            RecordedCalls.Add(name);
            if (ThrowUnavailable)
                throw new SasServiceUnavailableException("unavailable");
            return Task.FromResult(DefaultResponse);
        }

        public Task<SasLoginResult> LoginAsync(string s, string u, string p, CancellationToken ct = default)
        {
            CallCount++; RecordedCalls.Add("login");
            if (ThrowUnavailable) throw new SasServiceUnavailableException("unavailable");
            return Task.FromResult(new SasLoginResult(true, "tok", null));
        }

        public Task<string> GetDashboardAsync(string s, string u, string p, CancellationToken ct = default) => Handle("dashboard");
        public Task<string> GetSubscribersAsync(string s, string u, string p, IDictionary<string, string?>? q = null, CancellationToken ct = default) => Handle("subscribers");
        public Task<string> GetReportAsync(string s, string u, string p, IDictionary<string, string?>? q = null, CancellationToken ct = default) => Handle("report");
        public Task<string> GetPackagesAsync(string s, string u, string p, CancellationToken ct = default) => Handle("packages");
        public Task<string> GetFinanceAsync(string s, string u, string p, CancellationToken ct = default) => Handle("finance");
        public Task<string> GetHealthAsync(string s, string u, string p, CancellationToken ct = default) => Handle("health");
        public Task<string> GetRenewalCandidatesAsync(string s, string u, string p, int? d = null, string? q = null, CancellationToken ct = default) => Handle("renewal_candidates");
        public Task<string> BulkRenewAsync(string s, string u, string p, IEnumerable<string> ids, int m, string? pid = null, bool dry = false, CancellationToken ct = default) => Handle("bulk_renew");

        // المشتركون
        public Task<string> GetUserDetailAsync(string s, string u, string p, string uid, CancellationToken ct = default) => Handle("user_detail");
        public Task<string> GetUserOverviewAsync(string s, string u, string p, string uid, CancellationToken ct = default) => Handle("users_overview");
        public Task<string> GetUserHistoryAsync(string s, string u, string p, string uid, CancellationToken ct = default) => Handle("user_history");
        public Task<string> GetUserExtendDataAsync(string s, string u, string p, string uid, CancellationToken ct = default) => Handle("user_extend_data");
        public Task<string> UserActionAsync(string s, string u, string p, string uid, string action, object? pms = null, CancellationToken ct = default) => Handle("user_action");
        public Task<string> UsersBulkActionAsync(string s, string u, string p, IEnumerable<string> uids, string action, object? pms = null, CancellationToken ct = default) => Handle("users_bulk_action");
        public Task<string> CreateUserAsync(string s, string u, string p, object payload, CancellationToken ct = default) => Handle("create_user");
        public Task<string> UpdateUserAsync(string s, string u, string p, string uid, object payload, CancellationToken ct = default) => Handle("update_user");
        public Task<string> DeleteUserAsync(string s, string u, string p, string uid, CancellationToken ct = default) => Handle("delete_user");
        public Task<string> GetUserRefundDataAsync(string s, string u, string p, string uid, CancellationToken ct = default) => Handle("user_refund_data");
        public Task<string> RefundUserAsync(string s, string u, string p, string uid, CancellationToken ct = default) => Handle("refund_user");

        // المتصلون + المدراء
        public Task<string> GetOnlineAsync(string s, string u, string p, CancellationToken ct = default) => Handle("online");
        public Task<string> GetManagersAsync(string s, string u, string p, CancellationToken ct = default) => Handle("managers");
        public Task<string> ManagerActionAsync(string s, string u, string p, string mid, string action, object? pms = null, CancellationToken ct = default) => Handle("manager_action");
        public Task<string> DeleteManagerAsync(string s, string u, string p, string mid, CancellationToken ct = default) => Handle("delete_manager");

        // البروكسي
        public Task<string> SasGetAsync(string s, string u, string p, string path, CancellationToken ct = default) => Handle("sas_get");
        public Task<string> SasPostAsync(string s, string u, string p, string path, object? payload = null, CancellationToken ct = default) => Handle("sas_post");

        // التخزين المحلي
        public Task<string> TestAccountAsync(string s, string u, string p, CancellationToken ct = default) => Handle("test_account");
        public Task<string> SyncAccountAsync(string s, string u, string p, string accountId, CancellationToken ct = default) => Handle("sync_account");
        public Task<string> GetLocalSubscribersAsync(string accountId, string? search = null, string? status = null, string? expiring = null, int? page = null, int? count = null, CancellationToken ct = default) => Handle("local_subscribers");
        public Task<string> GetSubscribersSummaryAsync(string accountId, CancellationToken ct = default) => Handle("subscribers_summary");
        public Task<string> SubmitReportAsync(string accountId, string companyId, string ownerUserId, int declaredTotal, int declaredActive, string? note = null, string? submittedBy = null, CancellationToken ct = default) => Handle("submit_report");
        public Task<string> ListReportsAsync(string accountId, CancellationToken ct = default) => Handle("list_reports");
        public Task<string> GetReconciliationAsync(string accountId, string s, string u, string p, CancellationToken ct = default) => Handle("reconciliation");

        // إدارة الوكلاء (ملخّص المقاطعة على مستوى الشركة)
        public Task<string> GetAgentsSummaryAsync(string companyId, IEnumerable<string> accountIds, CancellationToken ct = default)
        {
            CallCount++;
            RecordedCalls.Add("agents_summary");
            AgentsSummaryCalls.Add((companyId, accountIds.ToList()));
            if (ThrowUnavailable)
                throw new SasServiceUnavailableException("unavailable");
            return Task.FromResult(AgentsSummaryResponse ?? DefaultResponse);
        }

        // التذاكر
        public Task<string> GetTicketsStatsAsync(string companyId, string ownerUserId, CancellationToken ct = default) => Handle("tickets_stats");
        public Task<string> GetTicketsListAsync(string companyId, string ownerUserId, string? status = null, string? category = null, string? search = null, int? page = null, int? count = null, CancellationToken ct = default) => Handle("tickets_list");
        public Task<string> GetTicketAsync(string companyId, string ownerUserId, string ticketId, CancellationToken ct = default) => Handle("ticket_get");
        public Task<string> CreateTicketAsync(string companyId, string ownerUserId, string subject, string body, string? category = null, string? priority = null, string? subscriberRef = null, string? createdBy = null, CancellationToken ct = default) => Handle("create_ticket");
        public Task<string> ReplyTicketAsync(string companyId, string ownerUserId, string ticketId, string body, bool? isInternal = null, string? author = null, CancellationToken ct = default) => Handle("reply_ticket");
        public Task<string> UpdateTicketAsync(string companyId, string ownerUserId, string ticketId, string? status = null, string? priority = null, string? category = null, CancellationToken ct = default) => Handle("update_ticket");

        // العقارات
        public Task<string> GetPremisesListAsync(string companyId, string ownerUserId, string? search = null, string? ownership = null, string? ptype = null, int? page = null, int? count = null, CancellationToken ct = default) => Handle("premises_list");
        public Task<string> GetPremisesAsync(string companyId, string ownerUserId, string premisesId, CancellationToken ct = default) => Handle("premises_get");
        public Task<string> GetPremisesSubscribersAsync(string companyId, string ownerUserId, string premisesId, CancellationToken ct = default) => Handle("premises_subscribers");
        public Task<string> GetPremisesBySubscriberAsync(string companyId, string ownerUserId, string subscriberRef, CancellationToken ct = default) => Handle("premises_by_subscriber");
        public Task<string> GetPremisesLinkCandidatesAsync(string companyId, string ownerUserId, string? search = null, CancellationToken ct = default) => Handle("premises_link_candidates");
        public Task<string> GetPremisesPhotoAsync(string companyId, string ownerUserId, string premisesId, CancellationToken ct = default) => Handle("premises_photo_get");
        public Task<string> CreatePremisesAsync(string companyId, string ownerUserId, string governorate, string area, string landmark, double? lat = null, double? lon = null, string? phone = null, string? ownership = null, string? ptype = null, string? createdBy = null, CancellationToken ct = default) => Handle("premises_create");
        public Task<string> UpdatePremisesAsync(string companyId, string ownerUserId, string premisesId, string? governorate = null, string? area = null, string? landmark = null, double? lat = null, double? lon = null, string? phone = null, string? ownership = null, string? ptype = null, CancellationToken ct = default) => Handle("premises_update");
        public Task<string> DeletePremisesAsync(string companyId, string ownerUserId, string premisesId, CancellationToken ct = default) => Handle("premises_delete");
        public Task<string> UploadPremisesPhotoAsync(string companyId, string ownerUserId, string premisesId, string imageBase64, string ext, CancellationToken ct = default) => Handle("premises_photo_upload");
        public Task<string> LinkPremisesSubscriberAsync(string companyId, string ownerUserId, string premisesId, string subscriberRef, CancellationToken ct = default) => Handle("premises_link");
        public Task<string> UnlinkPremisesSubscriberAsync(string companyId, string ownerUserId, string premisesId, string subscriberRef, CancellationToken ct = default) => Handle("premises_unlink");
    }

    // ── مساعدات البناء ────────────────────────────────────────────────────────

    private static SadaraDbContext NewInMemoryContext(string dbName, ICurrentTenant tenant)
        => new(new DbContextOptionsBuilder<SadaraDbContext>()
            .UseInMemoryDatabase(dbName).Options, tenant);

    private static SasAgentController BuildController(
        SadaraDbContext db,
        ICurrentTenant tenant,
        Guid currentUserId,
        ISasServiceClient? sasClient = null,
        ISecretProtector? protector = null)
    {
        // المحاسبة الموحّدة (activate-billed) لا تُستدعى في هذه الاختبارات، لكن المُنشئ يتطلّبها:
        // نمرّر UnitOfWork حقيقياً فوق سياق الاختبار + خدمة محاسبة حقيقية عليه.
        var uow = new Sadara.Infrastructure.Repositories.UnitOfWork(db);
        var accounting = new Sadara.API.Services.SubscriptionAccountingService(
            uow, NullLogger<Sadara.API.Services.SubscriptionAccountingService>.Instance);

        var ctrl = new SasAgentController(
            db,
            tenant,
            protector ?? new FakeProtector(),
            sasClient ?? new ConfigurableSasClient(),
            NullLogger<SasAgentController>.Instance,
            uow,
            accounting);

        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, currentUserId.ToString()),
            new(ClaimTypes.Role, "Employee"),
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

    private static SasAccount SeedAccount(
        string dbName, Guid accountId, Guid companyId, Guid ownerUserId,
        bool isDeleted = false)
    {
        var sysTenant = new FakeTenant { BypassTenantFilter = true, IsSuperAdmin = true };
        using var seed = NewInMemoryContext(dbName, sysTenant);
        var account = new SasAccount
        {
            Id               = accountId,
            CompanyId        = companyId,
            OwnerUserId      = ownerUserId,
            Label            = "test",
            ServerUrl        = "http://sas.test",
            Username         = "agent",
            PasswordEncrypted = "FAKE:" + Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes("pass")),
            AccountType      = SasAccountType.SasManager,
            IsActive         = true,
            IsDeleted        = isDeleted,
        };
        seed.SasAccounts.Add(account);
        seed.SaveChanges();
        return account;
    }

    // مساعد: فكّ JSON anonymous
    private static int GetJsonInt(object? value, string property)
    {
        var json = JsonSerializer.Serialize(value);
        var doc = JsonDocument.Parse(json);
        return doc.RootElement.GetProperty(property).GetInt32();
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 1) عزل المشتركين (users) — PassThrough يمرّ عبر GetOwnedAccountAsync
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task GetUserDetail_CompanyB_AccountId_Returns_NotFound_For_CompanyA_User()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyB, UserB);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.GetUserDetail(accId, "u123", CancellationToken.None);
        Assert.IsType<NotFoundObjectResult>(result);
    }

    [Fact]
    public async Task GetUserDetail_ValidAccount_CallsSasClient()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);

        var sas = new ConfigurableSasClient();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        var result = await ctrl.GetUserDetail(accId, "u42", CancellationToken.None);

        Assert.IsType<ContentResult>(result);
        Assert.Contains("user_detail", sas.RecordedCalls);
    }

    [Fact]
    public async Task UserAction_MissingAction_Returns_BadRequest()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        // إجراء فارغ => BadRequest
        var result = await ctrl.UserAction(accId, "u1",
            new SasActionRequest("", null), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task UserAction_WhitespaceAction_Returns_BadRequest()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.UserAction(accId, "u1",
            new SasActionRequest("   ", null), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task UserAction_WrongCompany_Returns_NotFound()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyB, UserB);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.UserAction(accId, "u1",
            new SasActionRequest("activate", null), CancellationToken.None);

        Assert.IsType<NotFoundObjectResult>(result);
    }

    [Fact]
    public async Task DeleteUser_WrongCompany_Returns_NotFound()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyB, UserB);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.DeleteUser(accId, "u5", CancellationToken.None);
        Assert.IsType<NotFoundObjectResult>(result);
    }

    [Fact]
    public async Task RefundUser_WrongCompany_Returns_NotFound()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyB, UserB);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.RefundUser(accId, "u5", CancellationToken.None);
        Assert.IsType<NotFoundObjectResult>(result);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 2) UsersBulkAction — سقف + عزل
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task UsersBulkAction_Over1000Uids_Returns_BadRequest()
    {
        var dbName = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var uids = Enumerable.Range(1, 1001).Select(i => i.ToString()).ToList();
        var result = await ctrl.UsersBulkAction(Guid.NewGuid(),
            new SasBulkActionRequest(uids, "activate", null), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task UsersBulkAction_EmptyUids_Returns_BadRequest()
    {
        var dbName = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.UsersBulkAction(Guid.NewGuid(),
            new SasBulkActionRequest([], "activate", null), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task UsersBulkAction_MissingAction_Returns_BadRequest()
    {
        var dbName = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.UsersBulkAction(Guid.NewGuid(),
            new SasBulkActionRequest(["u1"], "", null), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 3) BulkRenew — سقف + تنقية الفارغات + عزل
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task BulkRenew_Over1000Subscribers_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var accId   = Guid.NewGuid();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var ids = Enumerable.Range(1, 1001).Select(i => i.ToString()).ToList();
        var result = await ctrl.BulkRenew(accId,
            new BulkRenewRequest(ids, 1, null, false), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task BulkRenew_InvalidMonths_Zero_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.BulkRenew(Guid.NewGuid(),
            new BulkRenewRequest(["s1"], 0, null, false), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task BulkRenew_MonthsOver60_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.BulkRenew(Guid.NewGuid(),
            new BulkRenewRequest(["s1"], 61, null, false), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task BulkRenew_WrongCompanyAccount_Returns_NotFound()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyB, UserB);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.BulkRenew(accId,
            new BulkRenewRequest(["s1", "s2"], 1, null, false), CancellationToken.None);

        Assert.IsType<NotFoundObjectResult>(result);
    }

    [Fact]
    public async Task BulkRenew_AllWhitespaceIds_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.BulkRenew(Guid.NewGuid(),
            new BulkRenewRequest(["   ", " \t "], 1, null, false), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 4) SasGet / SasPost — المسار مطلوب
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task SasGet_EmptyPath_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.SasGet(Guid.NewGuid(), "", CancellationToken.None);
        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task SasPost_EmptyPath_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.SasPost(Guid.NewGuid(),
            new SasProxyPostRequest("   ", null), CancellationToken.None);
        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task SasGet_WrongAccount_Returns_NotFound()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyB, UserB);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.SasGet(accId, "/some/path", CancellationToken.None);
        Assert.IsType<NotFoundObjectResult>(result);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 5) SasServiceUnavailableException => 503
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task GetDashboard_SasUnavailable_Returns_503()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);

        var sas = new ConfigurableSasClient { ThrowUnavailable = true };
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        var result = await ctrl.GetDashboard(accId, CancellationToken.None);

        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(503, obj.StatusCode);
    }

    [Fact]
    public async Task DeleteUser_SasUnavailable_Returns_503()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);

        var sas = new ConfigurableSasClient { ThrowUnavailable = true };
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        var result = await ctrl.DeleteUser(accId, "u1", CancellationToken.None);

        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(503, obj.StatusCode);
    }

    [Fact]
    public async Task GetTicketsStats_SasUnavailable_Returns_503()
    {
        var dbName = Guid.NewGuid().ToString();
        var sas = new ConfigurableSasClient { ThrowUnavailable = true };
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        var result = await ctrl.GetTicketsStats(CancellationToken.None);

        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(503, obj.StatusCode);
    }

    [Fact]
    public async Task GetPremisesList_SasUnavailable_Returns_503()
    {
        var dbName = Guid.NewGuid().ToString();
        var sas = new ConfigurableSasClient { ThrowUnavailable = true };
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        var result = await ctrl.GetPremisesList(ct: CancellationToken.None);

        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(503, obj.StatusCode);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 6) التذاكر — SuperAdmin يحصل على Forbid
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task GetTicketsStats_NullCompany_Returns_Forbid()
    {
        var dbName     = Guid.NewGuid().ToString();
        var superTenant = new FakeTenant { CompanyId = null, IsSuperAdmin = true };
        using var db   = NewInMemoryContext(dbName, superTenant);
        var ctrl       = BuildController(db, superTenant, UserA);

        var result = await ctrl.GetTicketsStats(CancellationToken.None);
        Assert.IsType<ForbidResult>(result);
    }

    [Fact]
    public async Task GetTickets_NullCompany_Returns_Forbid()
    {
        var dbName     = Guid.NewGuid().ToString();
        var superTenant = new FakeTenant { CompanyId = null };
        using var db   = NewInMemoryContext(dbName, superTenant);
        var ctrl       = BuildController(db, superTenant, UserA);

        var result = await ctrl.GetTickets(ct: CancellationToken.None);
        Assert.IsType<ForbidResult>(result);
    }

    [Fact]
    public async Task CreateTicket_NullCompany_Returns_Forbid()
    {
        var dbName     = Guid.NewGuid().ToString();
        var superTenant = new FakeTenant { CompanyId = null };
        using var db   = NewInMemoryContext(dbName, superTenant);
        var ctrl       = BuildController(db, superTenant, UserA);

        var result = await ctrl.CreateTicket(
            new SasAgentCreateTicketRequest("موضوع", "نصّ", null, null, null),
            CancellationToken.None);

        Assert.IsType<ForbidResult>(result);
    }

    [Fact]
    public async Task ReplyTicket_NullCompany_Returns_Forbid()
    {
        var dbName     = Guid.NewGuid().ToString();
        var superTenant = new FakeTenant { CompanyId = null };
        using var db   = NewInMemoryContext(dbName, superTenant);
        var ctrl       = BuildController(db, superTenant, UserA);

        var result = await ctrl.ReplyTicket("t1",
            new SasAgentReplyTicketRequest("ردّ", null), CancellationToken.None);

        Assert.IsType<ForbidResult>(result);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 7) التذاكر — تحقّق المدخلات
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task CreateTicket_EmptySubject_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.CreateTicket(
            new SasAgentCreateTicketRequest("", "نصّ مناسب", null, null, null),
            CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task CreateTicket_EmptyBody_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.CreateTicket(
            new SasAgentCreateTicketRequest("موضوع", "", null, null, null),
            CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task GetTicket_EmptyTicketId_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.GetTicket("   ", CancellationToken.None);
        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task ReplyTicket_EmptyBody_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.ReplyTicket("t1",
            new SasAgentReplyTicketRequest("", null), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task UpdateTicket_AllNullFields_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        // كل الحقول null => 400
        var result = await ctrl.UpdateTicket("t1",
            new SasAgentUpdateTicketRequest(null, null, null), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task UpdateTicket_EmptyTicketId_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.UpdateTicket("",
            new SasAgentUpdateTicketRequest("open", null, null), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task CreateTicket_Valid_CallsSasClient()
    {
        var dbName  = Guid.NewGuid().ToString();
        var sas     = new ConfigurableSasClient();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        var result = await ctrl.CreateTicket(
            new SasAgentCreateTicketRequest("موضوع صالح", "نصّ التذكرة", null, null, null),
            CancellationToken.None);

        Assert.IsType<ContentResult>(result);
        Assert.Contains("create_ticket", sas.RecordedCalls);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 8) العقارات — SuperAdmin يحصل على Forbid
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task GetPremisesList_NullCompany_Returns_Forbid()
    {
        var dbName     = Guid.NewGuid().ToString();
        var superTenant = new FakeTenant { CompanyId = null };
        using var db   = NewInMemoryContext(dbName, superTenant);
        var ctrl       = BuildController(db, superTenant, UserA);

        var result = await ctrl.GetPremisesList(ct: CancellationToken.None);
        Assert.IsType<ForbidResult>(result);
    }

    [Fact]
    public async Task CreatePremises_NullCompany_Returns_Forbid()
    {
        var dbName     = Guid.NewGuid().ToString();
        var superTenant = new FakeTenant { CompanyId = null };
        using var db   = NewInMemoryContext(dbName, superTenant);
        var ctrl       = BuildController(db, superTenant, UserA);

        var result = await ctrl.CreatePremises(
            new PremisesCreateRequest("بغداد", "الكرادة", "بجانب المصرف", null, null, null, null, null),
            CancellationToken.None);

        Assert.IsType<ForbidResult>(result);
    }

    [Fact]
    public async Task DeletePremises_NullCompany_Returns_Forbid()
    {
        var dbName     = Guid.NewGuid().ToString();
        var superTenant = new FakeTenant { CompanyId = null };
        using var db   = NewInMemoryContext(dbName, superTenant);
        var ctrl       = BuildController(db, superTenant, UserA);

        var result = await ctrl.DeletePremises("p-001", CancellationToken.None);
        Assert.IsType<ForbidResult>(result);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 9) العقارات — تحقّق المدخلات
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task CreatePremises_MissingGovernorate_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.CreatePremises(
            new PremisesCreateRequest("", "الكرادة", "نقطة دالّة", null, null, null, null, null),
            CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task CreatePremises_MissingArea_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.CreatePremises(
            new PremisesCreateRequest("بغداد", "   ", "نقطة دالّة", null, null, null, null, null),
            CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task CreatePremises_MissingLandmark_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.CreatePremises(
            new PremisesCreateRequest("بغداد", "الكرادة", null!, null, null, null, null, null),
            CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task CreatePremises_InvalidLat_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        // خط عرض خارج -90..90
        var result = await ctrl.CreatePremises(
            new PremisesCreateRequest("بغداد", "الكرادة", "نقطة", 95.0, null, null, null, null),
            CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task CreatePremises_InvalidLon_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        // خط طول خارج -180..180
        var result = await ctrl.CreatePremises(
            new PremisesCreateRequest("بغداد", "الكرادة", "نقطة", null, 200.0, null, null, null),
            CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task CreatePremises_ValidData_CallsSasClient()
    {
        var dbName  = Guid.NewGuid().ToString();
        var sas     = new ConfigurableSasClient();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        var result = await ctrl.CreatePremises(
            new PremisesCreateRequest("بغداد", "الكرادة", "بجانب المصرف", 33.3, 44.4, null, null, null),
            CancellationToken.None);

        Assert.IsType<ContentResult>(result);
        Assert.Contains("premises_create", sas.RecordedCalls);
    }

    [Fact]
    public async Task UpdatePremises_EmptyPid_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.UpdatePremises("",
            new PremisesUpdateRequest("بغداد", null, null, null, null, null, null, null),
            CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task UpdatePremises_AllNullFields_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.UpdatePremises("p-001",
            new PremisesUpdateRequest(null, null, null, null, null, null, null, null),
            CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task GetPremisesBySubscriber_EmptyRef_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.GetPremisesBySubscriber("   ", CancellationToken.None);
        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task LinkPremisesSubscriber_EmptyRef_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.LinkPremisesSubscriber("p-001",
            new PremisesLinkRequest(null), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 10) رفع صورة العقار — base64 + حدود
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task UploadPremisesPhoto_InvalidBase64_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        // base64 غير صالح (طول لا يقبل % 4)
        var result = await ctrl.UploadPremisesPhoto("p-001",
            new PremisesPhotoUploadRequest("NotValidBase64!!!", "jpg"),
            CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task UploadPremisesPhoto_UnsupportedExt_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        // صورة صالحة (1x1 PNG base64) لكن امتداد غير مدعوم
        const string valid1x1PngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";
        var result = await ctrl.UploadPremisesPhoto("p-001",
            new PremisesPhotoUploadRequest(valid1x1PngBase64, "bmp"),
            CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task UploadPremisesPhoto_OversizedBase64_Returns_413()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        // توليد سلسلة base64 صالحة تتجاوز الحدّ (5MB) — لا نُفكّ فعلاً
        // نُنشئ سلسلة مقسّمة على 4 (صالحة شكلاً) أطول من MaxPhotoBase64Length
        var oversized = new string('A', 5 * 1024 * 1024 + 4);
        var result = await ctrl.UploadPremisesPhoto("p-001",
            new PremisesPhotoUploadRequest(oversized, "jpg"),
            CancellationToken.None);

        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(413, obj.StatusCode);
    }

    [Fact]
    public async Task UploadPremisesPhoto_ValidImage_NullCompany_Returns_Forbid()
    {
        var dbName     = Guid.NewGuid().ToString();
        var superTenant = new FakeTenant { CompanyId = null };
        using var db   = NewInMemoryContext(dbName, superTenant);
        var ctrl       = BuildController(db, superTenant, UserA);

        const string valid1x1 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";
        var result = await ctrl.UploadPremisesPhoto("p-001",
            new PremisesPhotoUploadRequest(valid1x1, "png"),
            CancellationToken.None);

        // حارس النطاق يُقيَّم بعد التحقّق من الصورة — النتيجة إما Forbid أو نفسها بعد التمرير
        // لكن بما أن CompanyId=null => TryResolveScope يُعيد Forbid
        Assert.IsType<ForbidResult>(result);
    }

    [Fact]
    public async Task UploadPremisesPhoto_DataUriPrefix_StrippedAndAccepted()
    {
        var dbName  = Guid.NewGuid().ToString();
        var accId   = Guid.NewGuid(); // نحتاج حساباً صالحاً ليصل PassThrough للـ SasClient
        var sas     = new ConfigurableSasClient();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        // بادئة data:image/png;base64, متبوعة بصورة صالحة
        const string valid1x1 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";
        var withPrefix = $"data:image/png;base64,{valid1x1}";

        // بما أن الحساب غير موجود في هذا الـ DB => NotFound لكن لا 400 (التحقّق من الصورة نجح)
        var result = await ctrl.UploadPremisesPhoto("p-001",
            new PremisesPhotoUploadRequest(withPrefix, "png"),
            CancellationToken.None);

        // لا BadRequest (الصورة مرّت التحقّق) — بلا حساب مُسجَّل => UserScopedPassThrough يمرّ بلا حساب
        Assert.IsNotType<BadRequestObjectResult>(result);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 11) SubmitReport — التحقّق من القيم + عدم قبول negatives
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task SubmitReport_NegativeDeclaredTotal_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var accId   = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.SubmitReport(accId,
            new SubmitReportRequest(-1, 0, null), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task SubmitReport_ActiveGreaterThanTotal_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var accId   = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        // الفعّالون (50) أكثر من الإجمالي (30) => 400
        var result = await ctrl.SubmitReport(accId,
            new SubmitReportRequest(30, 50, null), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task SubmitReport_WrongCompanyAccount_Returns_NotFound()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyB, UserB);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.SubmitReport(accId,
            new SubmitReportRequest(100, 80, "ملاحظة"), CancellationToken.None);

        Assert.IsType<NotFoundObjectResult>(result);
    }

    [Fact]
    public async Task SubmitReport_NullCompany_Returns_Forbid()
    {
        var dbName     = Guid.NewGuid().ToString();
        var superTenant = new FakeTenant { CompanyId = null };
        using var db   = NewInMemoryContext(dbName, superTenant);
        var ctrl       = BuildController(db, superTenant, UserA);

        var result = await ctrl.SubmitReport(Guid.NewGuid(),
            new SubmitReportRequest(100, 80, null), CancellationToken.None);

        Assert.IsType<ForbidResult>(result);
    }

    [Fact]
    public async Task SubmitReport_Valid_CallsSasClient()
    {
        var dbName  = Guid.NewGuid().ToString();
        var accId   = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);

        var sas     = new ConfigurableSasClient();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        var result = await ctrl.SubmitReport(accId,
            new SubmitReportRequest(100, 80, "ملاحظة"), CancellationToken.None);

        Assert.IsType<ContentResult>(result);
        Assert.Contains("submit_report", sas.RecordedCalls);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 12) عدم تسرّب كلمة المرور في استجابة GetAccounts
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task GetAccounts_Response_DoesNotContain_Password()
    {
        var dbName   = Guid.NewGuid().ToString();
        var accId    = Guid.NewGuid();
        var protector = new FakeProtector();
        SeedAccount(dbName, accId, CompanyA, UserA);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, protector: protector);

        var result = await ctrl.GetAccounts(CancellationToken.None);

        var ok  = Assert.IsType<OkObjectResult>(result);
        var json = JsonSerializer.Serialize(ok.Value);

        // التحقّق من غياب كلمة المرور في أي شكل
        Assert.DoesNotContain("password", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("PasswordEncrypted", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("FAKE:", json, StringComparison.OrdinalIgnoreCase);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 13) CreateUser / UpdateUser — تحقّق الـ payload
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task CreateUser_NullPayload_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.CreateUser(Guid.NewGuid(),
            new SasPayloadRequest(null), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task UpdateUser_NullPayload_Returns_BadRequest()
    {
        var dbName  = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.UpdateUser(Guid.NewGuid(), "u1",
            new SasPayloadRequest(null), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 14) نقاط القراءة الصحيحة — تمرّ بلا عائق بحساب صالح
    // ══════════════════════════════════════════════════════════════════════════

    [Theory]
    [InlineData("dashboard")]
    [InlineData("subscribers")]
    [InlineData("report")]
    [InlineData("packages")]
    [InlineData("finance")]
    [InlineData("health")]
    [InlineData("online")]
    [InlineData("managers")]
    public async Task ReadEndpoints_ValidAccount_ReturnContent(string endpoint)
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);

        var sas     = new ConfigurableSasClient();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        IActionResult result = endpoint switch
        {
            "dashboard"   => await ctrl.GetDashboard(accId, CancellationToken.None),
            "subscribers" => await ctrl.GetSubscribers(accId, CancellationToken.None),
            "report"      => await ctrl.GetReport(accId, CancellationToken.None),
            "packages"    => await ctrl.GetPackages(accId, CancellationToken.None),
            "finance"     => await ctrl.GetFinance(accId, CancellationToken.None),
            "health"      => await ctrl.GetHealth(accId, CancellationToken.None),
            "online"      => await ctrl.GetOnline(accId, CancellationToken.None),
            "managers"    => await ctrl.GetManagers(accId, CancellationToken.None),
            _             => throw new ArgumentException(endpoint),
        };

        Assert.IsType<ContentResult>(result);
        var content = (ContentResult)result;
        Assert.Equal("application/json", content.ContentType);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 15) ListReports / GetLocalSubscribers — عزل الحساب (لا خادم ساس)
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task ListReports_WrongAccount_Returns_NotFound()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyB, UserB);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.ListReports(accId, CancellationToken.None);
        Assert.IsType<NotFoundObjectResult>(result);
    }

    [Fact]
    public async Task GetLocalSubscribers_WrongAccount_Returns_NotFound()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyB, UserB);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.GetLocalSubscribers(accId, ct: CancellationToken.None);
        Assert.IsType<NotFoundObjectResult>(result);
    }

    [Fact]
    public async Task GetReconciliation_WrongAccount_Returns_NotFound()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyB, UserB);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.GetReconciliation(accId, CancellationToken.None);
        Assert.IsType<NotFoundObjectResult>(result);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 16) اختبار الاتصال (TestAccount) — SasUnavailable => 503
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task TestAccount_SasUnavailable_Returns_503()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);

        var sas = new ConfigurableSasClient { ThrowUnavailable = true };
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        var result = await ctrl.TestAccount(accId, CancellationToken.None);
        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(503, obj.StatusCode);
    }

    [Fact]
    public async Task TestAccount_ValidAccount_CallsSasClient()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);

        var sas     = new ConfigurableSasClient();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        var result = await ctrl.TestAccount(accId, CancellationToken.None);

        Assert.IsType<ContentResult>(result);
        Assert.Contains("test_account", sas.RecordedCalls);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 17) UpdateAccount — تُحافظ على CompanyId/OwnerId (لا تُقبل من الجسم)
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task UpdateAccount_Valid_DoesNotChangeCompanyOrOwner()
    {
        var dbName   = Guid.NewGuid().ToString();
        var accId    = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.UpdateAccount(accId,
            new UpdateSasAccountRequest("تسمية جديدة", null, null, null, null, null),
            CancellationToken.None);

        Assert.IsType<OkObjectResult>(result);

        // تحقّق من عدم تغيير الشركة أو المالك
        var sysTenant = new FakeTenant { BypassTenantFilter = true, IsSuperAdmin = true };
        using var check = NewInMemoryContext(dbName, sysTenant);
        var saved = check.SasAccounts.First(x => x.Id == accId);

        Assert.Equal(CompanyA, saved.CompanyId);
        Assert.Equal(UserA, saved.OwnerUserId);
        Assert.Equal("تسمية جديدة", saved.Label);
    }

    [Fact]
    public async Task UpdateAccount_NewPassword_ReEncrypts()
    {
        var dbName    = Guid.NewGuid().ToString();
        var accId     = Guid.NewGuid();
        var protector = new FakeProtector();
        SeedAccount(dbName, accId, CompanyA, UserA);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, protector: protector);

        var result = await ctrl.UpdateAccount(accId,
            new UpdateSasAccountRequest(null, null, null, "new_pass_123", null, null),
            CancellationToken.None);

        Assert.IsType<OkObjectResult>(result);
        // Protect استُدعي مرة
        Assert.Equal(1, protector.ProtectCallCount);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 18) GetManagers / DeleteManager — عزل الحساب
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task GetManagers_WrongAccount_Returns_NotFound()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyB, UserB);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.GetManagers(accId, CancellationToken.None);
        Assert.IsType<NotFoundObjectResult>(result);
    }

    [Fact]
    public async Task DeleteManager_WrongAccount_Returns_NotFound()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyB, UserB);

        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA);

        var result = await ctrl.DeleteManager(accId, "m1", CancellationToken.None);
        Assert.IsType<NotFoundObjectResult>(result);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 19) GetRenewalCandidates — SasUnavailable => 503
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task GetRenewalCandidates_SasUnavailable_Returns_503()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);

        var sas = new ConfigurableSasClient { ThrowUnavailable = true };
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        var result = await ctrl.GetRenewalCandidates(accId, 7, null, CancellationToken.None);
        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(503, obj.StatusCode);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 20) عزل التذاكر: شركة ب لا تطّلع على تذاكر شركة أ (user-scoped)
    //     النقاط ليست account-scoped فلا NotFound — لكن CompanyId يُشتق من التوكن
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task GetTicketsStats_CompanyB_Tenant_Uses_CompanyB_Id_Not_CompanyA()
    {
        // المضاعفة تُسجّل companyId الممرَّر لها
        string? capturedCompany = null;

        var capturingSas = new CapturingSasClient(
            onGetTicketsStats: (cid, _) => capturedCompany = cid);

        var dbName  = Guid.NewGuid().ToString();
        var tenantB = new FakeTenant { CompanyId = CompanyB };
        using var db = NewInMemoryContext(dbName, tenantB);
        var ctrl = BuildController(db, tenantB, UserB, capturingSas);

        await ctrl.GetTicketsStats(CancellationToken.None);

        // يجب أن يُمرَّر CompanyB لا CompanyA
        Assert.Equal(CompanyB.ToString(), capturedCompany);
    }

    [Fact]
    public async Task GetPremisesList_CompanyB_Tenant_Uses_CompanyB_Id()
    {
        string? capturedCompany = null;

        var capturingSas = new CapturingSasClient(
            onGetPremisesList: (cid, _) => capturedCompany = cid);

        var dbName  = Guid.NewGuid().ToString();
        var tenantB = new FakeTenant { CompanyId = CompanyB };
        using var db = NewInMemoryContext(dbName, tenantB);
        var ctrl = BuildController(db, tenantB, UserB, capturingSas);

        await ctrl.GetPremisesList(ct: CancellationToken.None);

        Assert.Equal(CompanyB.ToString(), capturedCompany);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CapturingSasClient — مضاعف يلتقط معرّفات الشركة/المالك الممرَّرة
// ═══════════════════════════════════════════════════════════════════════════════

/// <summary>
/// يُمرَّر companyId+ownerUserId عبر callbacks لالتقاطها في الاختبار.
/// كل ما لم يُعطَ callback يعيد استجابة فارغة.
/// </summary>
internal sealed class CapturingSasClient : ISasServiceClient
{
    private readonly Action<string, string>? _onGetTicketsStats;
    private readonly Action<string, string>? _onGetPremisesList;

    public CapturingSasClient(
        Action<string, string>? onGetTicketsStats = null,
        Action<string, string>? onGetPremisesList = null)
    {
        _onGetTicketsStats = onGetTicketsStats;
        _onGetPremisesList = onGetPremisesList;
    }

    private static Task<string> Empty() => Task.FromResult("""{"ok":true}""");

    public Task<SasLoginResult> LoginAsync(string s, string u, string p, CancellationToken ct = default)
        => Task.FromResult(new SasLoginResult(true, null, null));

    public Task<string> GetDashboardAsync(string s, string u, string p, CancellationToken ct = default) => Empty();
    public Task<string> GetSubscribersAsync(string s, string u, string p, IDictionary<string, string?>? q = null, CancellationToken ct = default) => Empty();
    public Task<string> GetReportAsync(string s, string u, string p, IDictionary<string, string?>? q = null, CancellationToken ct = default) => Empty();
    public Task<string> GetPackagesAsync(string s, string u, string p, CancellationToken ct = default) => Empty();
    public Task<string> GetFinanceAsync(string s, string u, string p, CancellationToken ct = default) => Empty();
    public Task<string> GetHealthAsync(string s, string u, string p, CancellationToken ct = default) => Empty();
    public Task<string> GetRenewalCandidatesAsync(string s, string u, string p, int? d = null, string? q = null, CancellationToken ct = default) => Empty();
    public Task<string> BulkRenewAsync(string s, string u, string p, IEnumerable<string> ids, int m, string? pid = null, bool dry = false, CancellationToken ct = default) => Empty();
    public Task<string> GetUserDetailAsync(string s, string u, string p, string uid, CancellationToken ct = default) => Empty();
    public Task<string> GetUserOverviewAsync(string s, string u, string p, string uid, CancellationToken ct = default) => Empty();
    public Task<string> GetUserHistoryAsync(string s, string u, string p, string uid, CancellationToken ct = default) => Empty();
    public Task<string> GetUserExtendDataAsync(string s, string u, string p, string uid, CancellationToken ct = default) => Empty();
    public Task<string> UserActionAsync(string s, string u, string p, string uid, string action, object? pms = null, CancellationToken ct = default) => Empty();
    public Task<string> UsersBulkActionAsync(string s, string u, string p, IEnumerable<string> uids, string action, object? pms = null, CancellationToken ct = default) => Empty();
    public Task<string> CreateUserAsync(string s, string u, string p, object payload, CancellationToken ct = default) => Empty();
    public Task<string> UpdateUserAsync(string s, string u, string p, string uid, object payload, CancellationToken ct = default) => Empty();
    public Task<string> DeleteUserAsync(string s, string u, string p, string uid, CancellationToken ct = default) => Empty();
    public Task<string> GetUserRefundDataAsync(string s, string u, string p, string uid, CancellationToken ct = default) => Empty();
    public Task<string> RefundUserAsync(string s, string u, string p, string uid, CancellationToken ct = default) => Empty();
    public Task<string> GetOnlineAsync(string s, string u, string p, CancellationToken ct = default) => Empty();
    public Task<string> GetManagersAsync(string s, string u, string p, CancellationToken ct = default) => Empty();
    public Task<string> ManagerActionAsync(string s, string u, string p, string mid, string action, object? pms = null, CancellationToken ct = default) => Empty();
    public Task<string> DeleteManagerAsync(string s, string u, string p, string mid, CancellationToken ct = default) => Empty();
    public Task<string> SasGetAsync(string s, string u, string p, string path, CancellationToken ct = default) => Empty();
    public Task<string> SasPostAsync(string s, string u, string p, string path, object? payload = null, CancellationToken ct = default) => Empty();
    public Task<string> TestAccountAsync(string s, string u, string p, CancellationToken ct = default) => Empty();
    public Task<string> SyncAccountAsync(string s, string u, string p, string accountId, CancellationToken ct = default) => Empty();
    public Task<string> GetLocalSubscribersAsync(string accountId, string? search = null, string? status = null, string? expiring = null, int? page = null, int? count = null, CancellationToken ct = default) => Empty();
    public Task<string> GetSubscribersSummaryAsync(string accountId, CancellationToken ct = default) => Empty();
    public Task<string> SubmitReportAsync(string accountId, string companyId, string ownerUserId, int declaredTotal, int declaredActive, string? note = null, string? submittedBy = null, CancellationToken ct = default) => Empty();
    public Task<string> ListReportsAsync(string accountId, CancellationToken ct = default) => Empty();
    public Task<string> GetReconciliationAsync(string accountId, string s, string u, string p, CancellationToken ct = default) => Empty();
    public Task<string> GetAgentsSummaryAsync(string companyId, IEnumerable<string> accountIds, CancellationToken ct = default) => Empty();

    public Task<string> GetTicketsStatsAsync(string companyId, string ownerUserId, CancellationToken ct = default)
    {
        _onGetTicketsStats?.Invoke(companyId, ownerUserId);
        return Empty();
    }

    public Task<string> GetTicketsListAsync(string companyId, string ownerUserId, string? status = null, string? category = null, string? search = null, int? page = null, int? count = null, CancellationToken ct = default) => Empty();
    public Task<string> GetTicketAsync(string companyId, string ownerUserId, string ticketId, CancellationToken ct = default) => Empty();
    public Task<string> CreateTicketAsync(string companyId, string ownerUserId, string subject, string body, string? category = null, string? priority = null, string? subscriberRef = null, string? createdBy = null, CancellationToken ct = default) => Empty();
    public Task<string> ReplyTicketAsync(string companyId, string ownerUserId, string ticketId, string body, bool? isInternal = null, string? author = null, CancellationToken ct = default) => Empty();
    public Task<string> UpdateTicketAsync(string companyId, string ownerUserId, string ticketId, string? status = null, string? priority = null, string? category = null, CancellationToken ct = default) => Empty();

    public Task<string> GetPremisesListAsync(string companyId, string ownerUserId, string? search = null, string? ownership = null, string? ptype = null, int? page = null, int? count = null, CancellationToken ct = default)
    {
        _onGetPremisesList?.Invoke(companyId, ownerUserId);
        return Empty();
    }

    public Task<string> GetPremisesAsync(string companyId, string ownerUserId, string premisesId, CancellationToken ct = default) => Empty();
    public Task<string> GetPremisesSubscribersAsync(string companyId, string ownerUserId, string premisesId, CancellationToken ct = default) => Empty();
    public Task<string> GetPremisesBySubscriberAsync(string companyId, string ownerUserId, string subscriberRef, CancellationToken ct = default) => Empty();
    public Task<string> GetPremisesLinkCandidatesAsync(string companyId, string ownerUserId, string? search = null, CancellationToken ct = default) => Empty();
    public Task<string> GetPremisesPhotoAsync(string companyId, string ownerUserId, string premisesId, CancellationToken ct = default) => Empty();
    public Task<string> CreatePremisesAsync(string companyId, string ownerUserId, string governorate, string area, string landmark, double? lat = null, double? lon = null, string? phone = null, string? ownership = null, string? ptype = null, string? createdBy = null, CancellationToken ct = default) => Empty();
    public Task<string> UpdatePremisesAsync(string companyId, string ownerUserId, string premisesId, string? governorate = null, string? area = null, string? landmark = null, double? lat = null, double? lon = null, string? phone = null, string? ownership = null, string? ptype = null, CancellationToken ct = default) => Empty();
    public Task<string> DeletePremisesAsync(string companyId, string ownerUserId, string premisesId, CancellationToken ct = default) => Empty();
    public Task<string> UploadPremisesPhotoAsync(string companyId, string ownerUserId, string premisesId, string imageBase64, string ext, CancellationToken ct = default) => Empty();
    public Task<string> LinkPremisesSubscriberAsync(string companyId, string ownerUserId, string premisesId, string subscriberRef, CancellationToken ct = default) => Empty();
    public Task<string> UnlinkPremisesSubscriberAsync(string companyId, string ownerUserId, string premisesId, string subscriberRef, CancellationToken ct = default) => Empty();
}
