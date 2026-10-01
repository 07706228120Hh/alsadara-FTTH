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
/// اختبارات تكامل لنقطة «فوترة الساس»:
///   POST /api/sas-agent/accounts/{id}/users/{uid}/activate-billed  →  SasAgentController.ActivateBilled
///
/// تستدعي ميثود الكونترولر مباشرةً (نفس نمط SasAgentExtendedTests/SasAgentIsolationTests) مع:
///   - InMemory SadaraDbContext (بلا فلتر مستأجر على Account — العزل المحاسبي صريح عبر CompanyId).
///   - UnitOfWork حقيقي فوق السياق + SubscriptionAccountingService حقيقية (قيد مزدوج فعلي).
///   - مضاعف ISasServiceClient (BilledSasClient) يعيد activationData فيه n_required_amount/profile_name
///     لـ SasGetAsync، ونجاحاً (أو استثناءً مضبوطاً) لـ UserActionAsync.
///
/// الحالات:
///   1) نجاح التفعيل المفوتر → 200 + SubscriptionLog(Source=Sas) بـ CompanyId/UserId مختومة من الحساب + JournalEntryId غير فارغ.
///   2) القيد المحاسبي متوازن (مدين = دائن) + سطر رصيد الصفحة 11102 موجود.
///   3) العزل: شركة A لا تفوتر حساب شركة B → NotFound، ولا سجل/قيد؛ وعند النجاح CompanyId = شركة الحساب.
///   4) idempotency: نفس transactionId مرّتين → الثاني 409 ولا سجل/قيد مكرّر.
///   5) حجب الصلاحية: RequirePermissionAttribute.HasPermission("sas_agent","manage", failClosed) = false بلا منح.
///   6) فشل SAS4 في UserActionAsync (SasServiceUnavailable) → 502 بلا سجل/قيد.
///   7) حجب الأسرار: الرد لا يحوي كلمة مرور.
/// </summary>
public class SasAgentActivateBilledTests
{
    // ── ثوابت ──────────────────────────────────────────────────────────────────
    private static readonly Guid CompanyA = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid CompanyB = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid UserA    = Guid.Parse("a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1");
    private static readonly Guid UserB    = Guid.Parse("b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1");

    private const string PlainPassword = "secret-pass-123";

    // ── Fakes ────────────────────────────────────────────────────────────────

    private sealed class FakeTenant : ICurrentTenant
    {
        public Guid? CompanyId { get; init; }
        public bool IsSuperAdmin { get; init; }
        public bool BypassTenantFilter { get; init; }
        public Guid? DefaultCompanyId { get; init; }
        public bool EnforceIsolation { get; init; }
    }

    /// <summary>حامي أسرار بسيط عكوس (Base64) — يطابق نمط FakeProtector في بقية الاختبارات.</summary>
    private sealed class FakeProtector : ISecretProtector
    {
        public string Protect(string p) => "FAKE:" + Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(p));
        public string Unprotect(string c)
        {
            if (string.IsNullOrEmpty(c)) return string.Empty;
            return System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(c[5..]));
        }
    }

    /// <summary>
    /// مضاعف ISasServiceClient مخصّص للفوترة:
    ///  - SasGetAsync → ActivationDataResponse (مثلاً {"n_required_amount":25000,"profile_name":"باقة 50"}).
    ///  - UserActionAsync → UserActionResponse (نجاح) أو يرمي SasServiceUnavailableException إن ThrowOnUserAction.
    /// يلتقط: هل استُدعي SasGet/UserAction، والباسوورد المفكوك الممرَّر لـ UserActionAsync (للتحقّق من العزل/الأسرار).
    /// </summary>
    private sealed class BilledSasClient : ISasServiceClient
    {
        public string ActivationDataResponse { get; set; } = """{"n_required_amount":25000,"profile_name":"باقة 50"}""";
        public string UserActionResponse { get; set; } = """{"ok":true,"username":"sub_user_42"}""";
        public bool ThrowOnUserAction { get; set; } = false;
        public bool ThrowOnSasGet { get; set; } = false;

        public int SasGetCallCount { get; private set; }
        public int UserActionCallCount { get; private set; }
        public string? LastUserActionPasswordPassed { get; private set; }
        public string? LastUserActionUidPassed { get; private set; }
        public string? LastUserActionNamePassed { get; private set; }

        public Task<string> SasGetAsync(string s, string u, string p, string path, CancellationToken ct = default)
        {
            SasGetCallCount++;
            if (ThrowOnSasGet) throw new SasServiceUnavailableException("sasget unavailable");
            return Task.FromResult(ActivationDataResponse);
        }

        public Task<string> UserActionAsync(string s, string u, string p, string uid, string action, object? pms = null, CancellationToken ct = default)
        {
            UserActionCallCount++;
            LastUserActionPasswordPassed = p;
            LastUserActionUidPassed = uid;
            LastUserActionNamePassed = action;
            if (ThrowOnUserAction) throw new SasServiceUnavailableException("useraction unavailable");
            return Task.FromResult(UserActionResponse);
        }

        // ── بقية الواجهة: استجابات فارغة (غير مستخدمة في هذه الاختبارات) ──
        private static Task<string> Empty() => Task.FromResult("""{"ok":true}""");

        public Task<SasLoginResult> LoginAsync(string s, string u, string p, CancellationToken ct = default)
            => Task.FromResult(new SasLoginResult(true, "tok", null));
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
        public Task<string> SasPostAsync(string s, string u, string p, string path, object? payload = null, CancellationToken ct = default) => Empty();
        public Task<string> TestAccountAsync(string s, string u, string p, CancellationToken ct = default) => Empty();
        public Task<string> SyncAccountAsync(string s, string u, string p, string accountId, CancellationToken ct = default) => Empty();
        public Task<string> GetLocalSubscribersAsync(string accountId, string? search = null, string? status = null, bool? expiring = null, int? page = null, int? count = null, CancellationToken ct = default) => Empty();
        public Task<string> GetSubscribersSummaryAsync(string accountId, CancellationToken ct = default) => Empty();
        public Task<string> SubmitReportAsync(string accountId, string companyId, string ownerUserId, int declaredTotal, int declaredActive, string? note = null, string? submittedBy = null, CancellationToken ct = default) => Empty();
        public Task<string> ListReportsAsync(string accountId, CancellationToken ct = default) => Empty();
        public Task<string> GetReconciliationAsync(string accountId, string s, string u, string p, CancellationToken ct = default) => Empty();
        public Task<string> GetAgentsSummaryAsync(string companyId, IEnumerable<string> accountIds, CancellationToken ct = default) => Empty();
        public Task<string> GetTicketsStatsAsync(string companyId, string ownerUserId, CancellationToken ct = default) => Empty();
        public Task<string> GetTicketsListAsync(string companyId, string ownerUserId, string? status = null, string? category = null, string? search = null, int? page = null, int? count = null, CancellationToken ct = default) => Empty();
        public Task<string> GetTicketAsync(string companyId, string ownerUserId, string ticketId, CancellationToken ct = default) => Empty();
        public Task<string> CreateTicketAsync(string companyId, string ownerUserId, string subject, string body, string? category = null, string? priority = null, string? subscriberRef = null, string? createdBy = null, CancellationToken ct = default) => Empty();
        public Task<string> ReplyTicketAsync(string companyId, string ownerUserId, string ticketId, string body, bool? isInternal = null, string? author = null, CancellationToken ct = default) => Empty();
        public Task<string> UpdateTicketAsync(string companyId, string ownerUserId, string ticketId, string? status = null, string? priority = null, string? category = null, CancellationToken ct = default) => Empty();
        public Task<string> GetPremisesListAsync(string companyId, string ownerUserId, string? search = null, string? ownership = null, string? ptype = null, int? page = null, int? count = null, CancellationToken ct = default) => Empty();
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

    // ── مساعدات البناء ────────────────────────────────────────────────────────

    private static SadaraDbContext NewInMemoryContext(string dbName, ICurrentTenant tenant)
        => new(new DbContextOptionsBuilder<SadaraDbContext>()
            .UseInMemoryDatabase(dbName).Options, tenant);

    private static SasAgentController BuildController(
        SadaraDbContext db,
        ICurrentTenant tenant,
        Guid currentUserId,
        ISasServiceClient sasClient,
        ISecretProtector? protector = null)
    {
        var uow = new Sadara.Infrastructure.Repositories.UnitOfWork(db);
        var accounting = new Sadara.API.Services.SubscriptionAccountingService(
            uow, NullLogger<Sadara.API.Services.SubscriptionAccountingService>.Instance);

        var ctrl = new SasAgentController(
            db, tenant,
            protector ?? new FakeProtector(),
            sasClient,
            NullLogger<SasAgentController>.Instance,
            uow, accounting);

        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, currentUserId.ToString()),
            new(ClaimTypes.Role, "Employee"),
        };
        var httpCtx = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity(claims, "TestScheme")),
        };
        ctrl.ControllerContext = new ControllerContext { HttpContext = httpCtx };
        return ctrl;
    }

    private static SasAccount SeedAccount(string dbName, Guid accountId, Guid companyId, Guid ownerUserId)
    {
        var sysTenant = new FakeTenant { BypassTenantFilter = true, IsSuperAdmin = true };
        using var seed = NewInMemoryContext(dbName, sysTenant);
        seed.SasAccounts.Add(new SasAccount
        {
            Id                = accountId,
            CompanyId         = companyId,
            OwnerUserId       = ownerUserId,
            Label             = "test",
            ServerUrl         = "http://sas.test",
            Username          = "agent",
            PasswordEncrypted = "FAKE:" + Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(PlainPassword)),
            AccountType       = SasAccountType.SasManager,
            IsActive          = true,
            IsDeleted         = false,
        });
        seed.SaveChanges();
        return seed.SasAccounts.First(x => x.Id == accountId);
    }

    /// <summary>
    /// يبذر شجرة الحسابات الدنيا التي تحتاجها SubscriptionAccountingService لإنشاء قيد متوازن:
    ///   1110 نقد (أصول) · 11102 رصيد الصفحة (خصوم) · 4110 إيراد صيانة · 4120 إيراد خصم شركة · 5110 مصاريف عروض.
    /// بلا هذه الحسابات (خصوصاً 11102) لا يُنشأ قيد — نبذرها ليتحقّق مسار القيد الكامل.
    /// </summary>
    private static void SeedChartOfAccounts(string dbName, Guid companyId)
    {
        var sysTenant = new FakeTenant { BypassTenantFilter = true, IsSuperAdmin = true };
        using var seed = NewInMemoryContext(dbName, sysTenant);

        Account Make(string code, string name, AccountType type) => new()
        {
            Id = Guid.NewGuid(),
            Code = code,
            Name = name,
            AccountType = type,
            CompanyId = companyId,
            IsActive = true,
            IsLeaf = true,
            Level = 1,
        };

        seed.Accounts.Add(Make("1110",  "النقدية",            AccountType.Assets));
        seed.Accounts.Add(Make("11102", "رصيد الصفحة",        AccountType.Liabilities));
        seed.Accounts.Add(Make("4110",  "إيراد الصيانة",      AccountType.Revenue));
        seed.Accounts.Add(Make("4120",  "إيراد خصم الشركة",   AccountType.Revenue));
        seed.Accounts.Add(Make("5110",  "مصاريف العروض",      AccountType.Expenses));
        seed.SaveChanges();
    }

    /// <summary>يبذر مستخدماً (للمشغّل) — RecordAsync يقرأ FullName للوصف.</summary>
    private static void SeedUser(string dbName, Guid userId, Guid companyId)
    {
        var sysTenant = new FakeTenant { BypassTenantFilter = true, IsSuperAdmin = true };
        using var seed = NewInMemoryContext(dbName, sysTenant);
        seed.Users.Add(new User
        {
            Id = userId,
            FullName = "موظّف الاختبار",
            Username = "emp_test_" + userId.ToString("N")[..8],
            CompanyId = companyId,
            IsActive = true,
        });
        seed.SaveChanges();
    }

    private static SasActivateBilledRequest ActivateCash(
        string action = "activate",
        int? months = 1,
        string? transactionId = null,
        string collectionType = "cash")
        => new(
            Action: action,
            Months: months,
            ProfileId: null,
            CollectionType: collectionType,
            MaintenanceFee: null,
            ManualDiscount: null,
            SystemDiscountEnabled: true,
            LinkedAgentId: null,
            Phone: null,
            SubscriberUsername: null,
            TransactionId: transactionId,
            Note: null);

    // ══════════════════════════════════════════════════════════════════════════
    // 1) نجاح التفعيل المفوتر → 200 + SubscriptionLog(Source=Sas) + CompanyId/UserId من الحساب + JournalEntryId
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task ActivateBilled_Valid_Returns_Ok_And_Creates_SasLog_With_Sealed_Company_And_Journal()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);
        SeedChartOfAccounts(dbName, CompanyA);
        SeedUser(dbName, UserA, CompanyA);

        var sas     = new BilledSasClient();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        var txn = "txn-success-001";
        var result = await ctrl.ActivateBilled(accId, "u42", ActivateCash(transactionId: txn), CancellationToken.None);

        // 200 OK
        var ok = Assert.IsType<OkObjectResult>(result);
        Assert.Equal(200, ok.StatusCode);

        // السعر جُلب خادمياً + الإجراء نُفّذ على الساس
        Assert.Equal(1, sas.SasGetCallCount);
        Assert.Equal(1, sas.UserActionCallCount);

        // استجابة فيها journalEntryId غير فارغ + logId
        var json = JsonSerializer.Serialize(ok.Value);
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;
        Assert.True(root.GetProperty("success").GetBoolean());

        var jePropFound = root.TryGetProperty("journalEntryId", out var jeEl);
        Assert.True(jePropFound);
        Assert.NotEqual(JsonValueKind.Null, jeEl.ValueKind);
        var jeFromResponse = jeEl.GetGuid();
        Assert.NotEqual(Guid.Empty, jeFromResponse);

        // تحقّق من SubscriptionLog المخزَّن: Source=Sas + CompanyId/UserId مختومة من الحساب (لا من العميل)
        var sysTenant = new FakeTenant { BypassTenantFilter = true, IsSuperAdmin = true };
        using var check = NewInMemoryContext(dbName, sysTenant);
        var log = Assert.Single(check.SubscriptionLogs.Where(l => l.FtthTransactionId == txn));

        Assert.Equal(SubscriptionLogSource.Sas, log.Source);
        Assert.Equal(CompanyA, log.CompanyId);     // مختوم من الحساب
        Assert.Equal(UserA, log.UserId);           // مختوم من مالك الحساب
        Assert.Equal(accId, log.SasAccountId);
        Assert.Equal("u42", log.SubscriberUid);
        Assert.Equal(25000m, log.BasePrice);       // من activationData لا من العميل
        Assert.Equal("باقة 50", log.PlanName);     // profile_name من activationData
        Assert.NotNull(log.JournalEntryId);
        Assert.Equal(jeFromResponse, log.JournalEntryId!.Value);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 2) القيد المحاسبي متوازن + سطر رصيد الصفحة 11102 موجود
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task ActivateBilled_Creates_Balanced_JournalEntry_With_PageBalance_Line_11102()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);
        SeedChartOfAccounts(dbName, CompanyA);
        SeedUser(dbName, UserA, CompanyA);

        var sas     = new BilledSasClient
        {
            ActivationDataResponse = """{"n_required_amount":30000,"profile_name":"باقة 100"}"""
        };
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        var result = await ctrl.ActivateBilled(accId, "u7", ActivateCash(transactionId: "txn-balanced-001"), CancellationToken.None);
        var ok = Assert.IsType<OkObjectResult>(result);
        var je = JsonDocument.Parse(JsonSerializer.Serialize(ok.Value)).RootElement.GetProperty("journalEntryId").GetGuid();

        var sysTenant = new FakeTenant { BypassTenantFilter = true, IsSuperAdmin = true };
        using var check = NewInMemoryContext(dbName, sysTenant);

        var entry = Assert.Single(check.JournalEntries.Where(j => j.Id == je));
        var lines = check.JournalEntryLines.Where(l => l.JournalEntryId == je).ToList();

        // القيد متوازن: مجموع المدين = مجموع الدائن
        var totalDebit  = lines.Sum(l => l.DebitAmount);
        var totalCredit = lines.Sum(l => l.CreditAmount);
        Assert.True(totalDebit > 0, "مجموع المدين يجب أن يكون موجباً");
        Assert.Equal(totalDebit, totalCredit);

        // توازن رأس القيد نفسه
        Assert.Equal(entry.TotalDebit, entry.TotalCredit);

        // القيد مُرحَّل ومرتبط بالساس
        Assert.Equal(JournalEntryStatus.Posted, entry.Status);
        Assert.Equal(JournalReferenceType.SasSubscription, entry.ReferenceType);
        Assert.Equal(CompanyA, entry.CompanyId);

        // سطر رصيد الصفحة 11102 موجود (دائن) بقيمة السعر
        var pageAccount = Assert.Single(check.Accounts.Where(a => a.Code == "11102" && a.CompanyId == CompanyA));
        var pageLine = Assert.Single(lines, l => l.AccountId == pageAccount.Id);
        Assert.Equal(30000m, pageLine.CreditAmount);
        Assert.Equal(0m, pageLine.DebitAmount);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 3) العزل: شركة A لا تفوتر حساب شركة B → NotFound، بلا سجل/قيد
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task ActivateBilled_CrossCompany_Account_Returns_NotFound_No_Log_No_Journal()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        // الحساب مملوك لشركة B
        SeedAccount(dbName, accId, CompanyB, UserB);
        SeedChartOfAccounts(dbName, CompanyA);
        SeedChartOfAccounts(dbName, CompanyB);

        var sas     = new BilledSasClient();
        // المستأجر شركة A يحاول فوترة حساب شركة B
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        var result = await ctrl.ActivateBilled(accId, "u1", ActivateCash(transactionId: "txn-cross-001"), CancellationToken.None);

        Assert.IsType<NotFoundObjectResult>(result);
        // لم يُستدعَ الساس إطلاقاً (التوقّف عند العزل قبل أي نداء)
        Assert.Equal(0, sas.SasGetCallCount);
        Assert.Equal(0, sas.UserActionCallCount);

        // لا سجل ولا قيد
        var sysTenant = new FakeTenant { BypassTenantFilter = true, IsSuperAdmin = true };
        using var check = NewInMemoryContext(dbName, sysTenant);
        Assert.Empty(check.SubscriptionLogs.Where(l => l.FtthTransactionId == "txn-cross-001"));
        Assert.Empty(check.JournalEntries.ToList());
    }

    [Fact]
    public async Task ActivateBilled_Success_Log_Carries_Account_CompanyId_Not_Tenant_Of_Caller()
    {
        // سيناريو: مالك الحساب هو UserA ضمن CompanyA، ونتحقّق أن CompanyId على السجل = شركة الحساب.
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);
        SeedChartOfAccounts(dbName, CompanyA);
        SeedUser(dbName, UserA, CompanyA);

        var sas     = new BilledSasClient();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        var txn = "txn-sealed-company-001";
        var result = await ctrl.ActivateBilled(accId, "u9", ActivateCash(transactionId: txn), CancellationToken.None);
        Assert.IsType<OkObjectResult>(result);

        var sysTenant = new FakeTenant { BypassTenantFilter = true, IsSuperAdmin = true };
        using var check = NewInMemoryContext(dbName, sysTenant);
        var log = Assert.Single(check.SubscriptionLogs.Where(l => l.FtthTransactionId == txn));
        Assert.Equal(CompanyA, log.CompanyId);
        Assert.NotEqual(CompanyB, log.CompanyId);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 4) idempotency: نفس transactionId مرّتين → الثاني 409، بلا سجل/قيد مكرّر
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task ActivateBilled_SameTransactionId_Twice_SecondReturns_Conflict_No_Duplicate()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);
        SeedChartOfAccounts(dbName, CompanyA);
        SeedUser(dbName, UserA, CompanyA);

        var sas     = new BilledSasClient();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        var txn = "txn-idem-001";

        // الاستدعاء الأول — نجاح
        using (var db1 = NewInMemoryContext(dbName, tenantA))
        {
            var ctrl1 = BuildController(db1, tenantA, UserA, sas);
            var r1 = await ctrl1.ActivateBilled(accId, "u5", ActivateCash(transactionId: txn), CancellationToken.None);
            Assert.IsType<OkObjectResult>(r1);
        }

        var userActionAfterFirst = sas.UserActionCallCount;

        // الاستدعاء الثاني بنفس المعرّف — 409
        using (var db2 = NewInMemoryContext(dbName, tenantA))
        {
            var ctrl2 = BuildController(db2, tenantA, UserA, sas);
            var r2 = await ctrl2.ActivateBilled(accId, "u5", ActivateCash(transactionId: txn), CancellationToken.None);

            var conflict = Assert.IsType<ConflictObjectResult>(r2);
            Assert.Equal(409, conflict.StatusCode);
        }

        // الثاني لم يُنفّذ إجراءً على الساس (رُفض قبل التنفيذ)
        Assert.Equal(userActionAfterFirst, sas.UserActionCallCount);

        // سجل واحد فقط + قيد واحد فقط
        var sysTenant = new FakeTenant { BypassTenantFilter = true, IsSuperAdmin = true };
        using var check = NewInMemoryContext(dbName, sysTenant);
        Assert.Single(check.SubscriptionLogs.Where(l => l.FtthTransactionId == txn));
        Assert.Single(check.JournalEntries.ToList());
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 5) حجب الصلاحية: بلا منح sas_agent:manage → HasPermission = false (failClosed)
    //    (RequirePermissionAttribute فلتر لا يعمل عند استدعاء الميثود مباشرة؛ نختبر منطق الصلاحية
    //     ذاته كما يفعل SasAgentIsolationTests — وهو ما تفرضه البوّابة على HTTP الحقيقي.)
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public void ActivateBilled_RequiresManage_ViewOnly_Is_Denied()
    {
        // مستخدم يملك view فقط (لا manage) — النقطة تتطلّب manage failClosed
        const string viewOnlyJson = """{"sas_agent":{"view":true,"manage":false}}""";
        Assert.False(RequirePermissionAttribute.HasPermission(viewOnlyJson, "sas_agent", "manage", failClosed: true));
        // view نفسه ممنوح (للمقارنة)
        Assert.True(RequirePermissionAttribute.HasPermission(viewOnlyJson, "sas_agent", "view", failClosed: true));
    }

    [Fact]
    public void ActivateBilled_NoPermissionsJson_FailClosed_Denies_Manage()
    {
        Assert.False(RequirePermissionAttribute.HasPermission(null, "sas_agent", "manage", failClosed: true));
        Assert.False(RequirePermissionAttribute.HasPermission("", "sas_agent", "manage", failClosed: true));
    }

    [Fact]
    public void ActivateBilled_ManageGranted_Is_Allowed()
    {
        const string manageJson = """{"sas_agent":{"view":true,"manage":true}}""";
        Assert.True(RequirePermissionAttribute.HasPermission(manageJson, "sas_agent", "manage", failClosed: true));
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 6) فشل SAS4 في UserActionAsync → 502 بلا سجل/قيد (لا محاسبة عند فشل التنفيذ)
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task ActivateBilled_SasUserActionThrows_Returns_502_No_Log_No_Journal()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);
        SeedChartOfAccounts(dbName, CompanyA);
        SeedUser(dbName, UserA, CompanyA);

        var sas     = new BilledSasClient { ThrowOnUserAction = true };
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        var txn = "txn-sasfail-001";
        var result = await ctrl.ActivateBilled(accId, "u3", ActivateCash(transactionId: txn), CancellationToken.None);

        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(502, obj.StatusCode);

        // الإجراء حاول التنفيذ لكنه رمى — لا سجل ولا قيد
        Assert.Equal(1, sas.UserActionCallCount);

        var sysTenant = new FakeTenant { BypassTenantFilter = true, IsSuperAdmin = true };
        using var check = NewInMemoryContext(dbName, sysTenant);
        Assert.Empty(check.SubscriptionLogs.Where(l => l.FtthTransactionId == txn));
        Assert.Empty(check.JournalEntries.ToList());
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 7) حجب الأسرار: الرد لا يحوي كلمة مرور (لا صريحة ولا مشفّرة)
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task ActivateBilled_Response_DoesNotContain_Password()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);
        SeedChartOfAccounts(dbName, CompanyA);
        SeedUser(dbName, UserA, CompanyA);

        var sas     = new BilledSasClient();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        var result = await ctrl.ActivateBilled(accId, "u8", ActivateCash(transactionId: "txn-secret-001"), CancellationToken.None);
        var ok = Assert.IsType<OkObjectResult>(result);
        var json = JsonSerializer.Serialize(ok.Value);

        Assert.DoesNotContain(PlainPassword, json, StringComparison.Ordinal);
        Assert.DoesNotContain("password", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("PasswordEncrypted", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("FAKE:", json, StringComparison.OrdinalIgnoreCase);

        // تأكيد جانبي: كلمة المرور المفكوكة فعلاً مُرِّرت لخدمة الساس (في الذاكرة فقط) — سلوك صحيح.
        Assert.Equal(PlainPassword, sas.LastUserActionPasswordPassed);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 8) تحقّقات المدخلات (حالات حدّية) — لا سعر يُجلب ولا إجراء يُنفّذ عند الرفض المبكّر
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task ActivateBilled_UnsupportedAction_Returns_BadRequest()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);

        var sas     = new BilledSasClient();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        var result = await ctrl.ActivateBilled(accId, "u1",
            ActivateCash(action: "delete"), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
        Assert.Equal(0, sas.UserActionCallCount);
    }

    [Fact]
    public async Task ActivateBilled_ActivateWithoutMonths_Returns_BadRequest()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);

        var sas     = new BilledSasClient();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        var result = await ctrl.ActivateBilled(accId, "u1",
            ActivateCash(action: "activate", months: null), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task ActivateBilled_AgentCollection_WithoutAgentId_Returns_BadRequest()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);

        var sas     = new BilledSasClient();
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        var req = new SasActivateBilledRequest(
            Action: "activate", Months: 1, ProfileId: null,
            CollectionType: "agent", MaintenanceFee: null, ManualDiscount: null,
            SystemDiscountEnabled: true, LinkedAgentId: null);

        var result = await ctrl.ActivateBilled(accId, "u1", req, CancellationToken.None);
        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task ActivateBilled_NullCompany_Returns_Forbid()
    {
        var dbName      = Guid.NewGuid().ToString();
        var superTenant = new FakeTenant { CompanyId = null, IsSuperAdmin = true };
        using var db    = NewInMemoryContext(dbName, superTenant);
        var ctrl        = BuildController(db, superTenant, UserA, new BilledSasClient());

        var result = await ctrl.ActivateBilled(Guid.NewGuid(), "u1",
            ActivateCash(transactionId: "txn-forbid-001"), CancellationToken.None);

        Assert.IsType<ForbidResult>(result);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 9) جلب السعر غير متاح (SasGet يرمي) → القيد يُنشأ بسعر 0 ولا يُجهَض التفعيل
    //    (سلوك موثّق في النقطة: تعذّر activationData لا يُجهض — يُسجَّل تحذير ويُكمَل بسعر 0).
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task ActivateBilled_ActivationDataUnavailable_StillActivates_WithZeroBasePrice()
    {
        var dbName = Guid.NewGuid().ToString();
        var accId  = Guid.NewGuid();
        SeedAccount(dbName, accId, CompanyA, UserA);
        SeedChartOfAccounts(dbName, CompanyA);
        SeedUser(dbName, UserA, CompanyA);

        var sas     = new BilledSasClient { ThrowOnSasGet = true };
        var tenantA = new FakeTenant { CompanyId = CompanyA };
        using var db = NewInMemoryContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA, sas);

        var txn = "txn-noprice-001";
        var result = await ctrl.ActivateBilled(accId, "u2", ActivateCash(transactionId: txn), CancellationToken.None);

        // التفعيل يُكمَل (الإجراء نُفّذ) — 200
        Assert.IsType<OkObjectResult>(result);
        Assert.Equal(1, sas.UserActionCallCount);

        var sysTenant = new FakeTenant { BypassTenantFilter = true, IsSuperAdmin = true };
        using var check = NewInMemoryContext(dbName, sysTenant);
        var log = Assert.Single(check.SubscriptionLogs.Where(l => l.FtthTransactionId == txn));
        Assert.Equal(0m, log.BasePrice);   // سعر 0 (تعذّر الجلب)
    }
}
