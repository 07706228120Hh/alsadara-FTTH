using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Sadara.API.Authorization;
using Sadara.API.Controllers;
using Sadara.Application.Interfaces;
using Sadara.Domain.Entities;
using Sadara.Infrastructure.Data;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// اختبارات «حارس تحويل العمولة» (<c>POST /api/linked-accounts/ftth/{id}/transfer-commission</c>)
/// — الجزء القابل للاختبار <b>بلا نداء FTTH حقيقي</b>.
///
/// تستخدم EF InMemory معزولاً (dbName فريد) + استدعاء الأكشن مباشرةً. لا قاعدة حقيقية ولا Docker.
/// حقن <see cref="IHttpClientFactory"/> يُطلق استثناءً إن استُدعي ⇒ أي اختبار هنا لا يبلغ طبقة FTTH؛
/// وإلّا لفشل بوضوح (دليل عملي أنّ المسار المُختبَر يسبق أي نداء خارجي).
///
/// ما يُغطّى هنا (قبل/حول نداء FTTH):
///  1) العزل: حساب FTTH لشركة أخرى ⇒ NotFound بلا إنشاء سجلّ تحويل.
///  2) الملكية: نفس الشركة/مالك مختلف (غير أدمن) ⇒ NotFound بلا سجلّ.
///  3) حارس النطاق: CompanyId == null (سياق نظام) ⇒ Forbid.
///  4) تحقّق الإدخال (قبل الحساب وقبل FTTH): amount ≤ 0، RequestId فارغ/charset غير صالح ⇒ 400.
///  5) idempotency (مستوى التطبيق): سجلّ سابق Succeeded يُعاد كما هو؛ Failed يُعاد برمزه؛ Pending ⇒ 409.
///     كلّها بلا إعادة تنفيذ وبلا نداء FTTH.
///  6) الصلاحية <c>transfer_commission</c>: اختبارات وحدة على <see cref="RequirePermissionAttribute.HasPermission"/>
///     (الفلتر لا يعمل عند الاستدعاء المباشر للأكشن — راجع ملاحظة الفجوات).
///
/// ما لا يُغطّى هنا (مسار FTTH الحيّ): تسجيل الدخول/جلب partnerId/رصيد العمولة/تنفيذ التحويل،
/// وبالتبعية الحارس المالي <c>amount &gt; الرصيد الحيّ ⇒ 400</c> (يتطلّب رصيداً حيّاً من FTTH).
/// المتحكّم ينادي FTTH عبر <c>IHttpClientFactory</c> مباشرةً بلا واجهة عميل قابلة للحقن ⇒ لا يمكن
/// تزييفه دون اعتراض طبقة HTTP الفعلية. راجع قسم الفجوات في تقرير المهمة.
/// </summary>
public class FtthCommissionTransferGuardTests
{
    // ── ثوابت ────────────────────────────────────────────────────────────────
    private static readonly Guid CompanyA = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid CompanyB = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid UserA1 = Guid.Parse("a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1");
    private static readonly Guid UserA2 = Guid.Parse("a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2");

    // ── Fakes ────────────────────────────────────────────────────────────────

    private sealed class FakeTenant : ICurrentTenant
    {
        public Guid? CompanyId { get; init; }
        public bool IsSuperAdmin { get; init; }
        public bool BypassTenantFilter { get; init; }
        public Guid? DefaultCompanyId { get; init; }
        public bool EnforceIsolation { get; init; }
    }

    private sealed class FakeSecretProtector : ISecretProtector
    {
        public string Protect(string plaintext) =>
            string.IsNullOrEmpty(plaintext) ? string.Empty
            : "FAKE:" + Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(plaintext));

        public string Unprotect(string ciphertext)
        {
            if (string.IsNullOrEmpty(ciphertext)) return string.Empty;
            if (!ciphertext.StartsWith("FAKE:", StringComparison.Ordinal))
                throw new InvalidOperationException("قيمة ليست من FakeSecretProtector");
            return System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(ciphertext[5..]));
        }
    }

    /// <summary>IHttpClientFactory يطلق استثناءً إن استُدعي — يثبت أنّ المسار المُختبَر لا يبلغ FTTH.</summary>
    private sealed class UnreachableHttpClientFactory : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) =>
            throw new InvalidOperationException("FTTH لا يجب أن يُنادى في هذا الاختبار");
    }

    /// <summary>
    /// عميل FTTH مُزيّف يفشل تسجيل الدخول دائماً — يحاكي دلالة «FTTH غير قابل للوصول» للاختبارات التي
    /// لا يُفترَض أن تبلغ طبقة FTTH (أو تبلغها فتفشل عند الدخول). الاختبارات التي تغطّي المسار الحيّ
    /// تستخدم عميلاً قابلاً للبرمجة في ملف اختبارات منفصل.
    /// </summary>
    private sealed class LoginFailsFtthClient : IFtthCommissionClient
    {
        public Task<FtthLoginResult> LoginAsync(string serverUrl, string username, string password, CancellationToken ct)
            => Task.FromResult(new FtthLoginResult(false, null, null, "تعذّر الاتصال بنظام FTTH"));

        public Task<string?> GetPartnerIdAsync(string serverUrl, string accessToken, CancellationToken ct)
            => throw new InvalidOperationException("لا يجب جلب partnerId بعد فشل الدخول");

        public Task<decimal?> GetCommissionBalanceAsync(string serverUrl, string accessToken, string partnerId, CancellationToken ct)
            => throw new InvalidOperationException("لا يجب جلب الرصيد بعد فشل الدخول");

        public Task<FtthTransferResult> TransferAsync(string serverUrl, string accessToken, string partnerId, long amount, string requestId, CancellationToken ct)
            => throw new InvalidOperationException("لا يجب تنفيذ التحويل بعد فشل الدخول");
    }

    // ── بناة ─────────────────────────────────────────────────────────────────

    private static SadaraDbContext NewContext(string dbName, ICurrentTenant tenant)
        => new(new DbContextOptionsBuilder<SadaraDbContext>()
            .UseInMemoryDatabase(dbName).Options, tenant);

    private static IConfiguration EmptyConfig() =>
        new ConfigurationBuilder().Build();

    private static LinkedAccountsController BuildController(
        SadaraDbContext db, ICurrentTenant tenant, Guid currentUserId, string? role = null)
    {
        var ctrl = new LinkedAccountsController(
            db, tenant,
            new FakeSecretProtector(),
            new LoginFailsFtthClient(),
            new UnreachableHttpClientFactory(),
            EmptyConfig(),
            NullLogger<LinkedAccountsController>.Instance);

        var claims = new List<Claim> { new(ClaimTypes.NameIdentifier, currentUserId.ToString()) };
        if (role != null) claims.Add(new Claim(ClaimTypes.Role, role));
        var identity = new ClaimsIdentity(claims, "TestScheme");
        ctrl.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext { User = new ClaimsPrincipal(identity) }
        };
        return ctrl;
    }

    private static void SeedAccount(string dbName, Guid accountId, Guid companyId, Guid ownerUserId, bool isDeleted = false)
    {
        var sys = new FakeTenant { BypassTenantFilter = true, IsSuperAdmin = true };
        using var seed = NewContext(dbName, sys);
        seed.FtthAccounts.Add(new FtthAccount
        {
            Id = accountId,
            CompanyId = companyId,
            OwnerUserId = ownerUserId,
            Label = "حساب اختبار",
            ServerUrl = "https://admin.ftth.iq",
            Username = "ftthuser",
            PasswordEncrypted = "FAKE:dGVzdHBhc3M=",
            IsActive = true,
            IsDeleted = isDeleted,
        });
        seed.SaveChanges();
    }

    private static void SeedTransfer(
        string dbName, Guid companyId, Guid ownerUserId, Guid accountId,
        string requestId, string status, int? ftthCode = null, string? message = null, bool isDeleted = false)
    {
        var sys = new FakeTenant { BypassTenantFilter = true, IsSuperAdmin = true };
        using var seed = NewContext(dbName, sys);
        seed.FtthCommissionTransfers.Add(new FtthCommissionTransfer
        {
            Id = Guid.NewGuid(),
            CompanyId = companyId,
            OwnerUserId = ownerUserId,
            FtthAccountId = accountId,
            PartnerId = "P-123",
            Amount = 5000,
            RequestId = requestId,
            Status = status,
            FtthResponseCode = ftthCode,
            FtthMessage = message,
            IsDeleted = isDeleted,
        });
        seed.SaveChanges();
    }

    private static int CountTransfers(string dbName)
    {
        var sys = new FakeTenant { BypassTenantFilter = true, IsSuperAdmin = true };
        using var check = NewContext(dbName, sys);
        return check.FtthCommissionTransfers.IgnoreQueryFilters().Count();
    }

    private static int StatusCodeOf(IActionResult result) => result switch
    {
        ObjectResult o => o.StatusCode ?? 0,
        StatusCodeResult s => s.StatusCode,
        _ => 0
    };

    // ══════════════════════════════════════════════════════════════════════════
    // 1) العزل بين الشركات
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task Transfer_On_OtherCompany_Account_Returns_NotFound_And_No_Record()
    {
        var dbName = Guid.NewGuid().ToString();
        var accountId = Guid.NewGuid();
        SeedAccount(dbName, accountId, CompanyB, UserA2); // حساب شركة ب

        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA1);

        var result = await ctrl.TransferCommission(
            accountId, new TransferCommissionRequest(1000, "req-iso-1"), CancellationToken.None);

        Assert.IsType<NotFoundObjectResult>(result);
        Assert.Equal(0, CountTransfers(dbName)); // صفر سجلّ تحويل
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 2) الملكية — نفس الشركة، مالك مختلف، مستخدم غير أدمن
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task Transfer_SameCompany_DifferentOwner_NonAdmin_Returns_NotFound_And_No_Record()
    {
        var dbName = Guid.NewGuid().ToString();
        var accountId = Guid.NewGuid();
        SeedAccount(dbName, accountId, CompanyA, UserA2); // مالكه UserA2

        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA1, role: "Employee"); // غير أدمن

        var result = await ctrl.TransferCommission(
            accountId, new TransferCommissionRequest(1000, "req-own-1"), CancellationToken.None);

        Assert.IsType<NotFoundObjectResult>(result);
        Assert.Equal(0, CountTransfers(dbName));
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 3) حارس النطاق — سياق نظام بلا CompanyId
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task Transfer_NullCompanyId_Returns_Forbid()
    {
        var dbName = Guid.NewGuid().ToString();
        var sysTenant = new FakeTenant { CompanyId = null, IsSuperAdmin = true, BypassTenantFilter = true };
        using var db = NewContext(dbName, sysTenant);
        var ctrl = BuildController(db, sysTenant, UserA1);

        var result = await ctrl.TransferCommission(
            Guid.NewGuid(), new TransferCommissionRequest(1000, "req-scope-1"), CancellationToken.None);

        Assert.IsType<ForbidResult>(result);
        Assert.Equal(0, CountTransfers(dbName));
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 4) تحقّق الإدخال — قبل أي نداء FTTH وقبل جلب الحساب
    // ══════════════════════════════════════════════════════════════════════════

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(-100000)]
    public async Task Transfer_NonPositive_Amount_Returns_BadRequest_No_Record(long amount)
    {
        var dbName = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA1);

        var result = await ctrl.TransferCommission(
            Guid.NewGuid(), new TransferCommissionRequest(amount, "req-amt-1"), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
        Assert.Equal(0, CountTransfers(dbName));
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public async Task Transfer_Empty_RequestId_Returns_BadRequest(string requestId)
    {
        var dbName = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA1);

        var result = await ctrl.TransferCommission(
            Guid.NewGuid(), new TransferCommissionRequest(1000, requestId), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
        Assert.Equal(0, CountTransfers(dbName));
    }

    // ملاحظة: الحارس يسمح بـ letters/digits + [-_.] عبر char.IsLetterOrDigit — وهذا يقبل حروف
    // Unicode (مثل "é") كأحرف صالحة، لكنه يرفض الفراغات/الأسطر الجديدة/الرموز (حقن ترويسة). القيم أدناه
    // كلّها charset غير صالح ⇒ 400 قبل جلب الحساب وقبل أي نداء FTTH.
    [Theory]
    [InlineData("has space")]
    [InlineData("new\nline")]
    [InlineData("semi;colon")]
    [InlineData("slash/here")]
    [InlineData("at@sign")]
    public async Task Transfer_Invalid_RequestId_Charset_Returns_BadRequest(string requestId)
    {
        var dbName = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA1);

        var result = await ctrl.TransferCommission(
            Guid.NewGuid(), new TransferCommissionRequest(1000, requestId), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
        Assert.Equal(0, CountTransfers(dbName));
    }

    [Fact]
    public async Task Transfer_TooLong_RequestId_Returns_BadRequest()
    {
        var dbName = Guid.NewGuid().ToString();
        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA1);

        var result = await ctrl.TransferCommission(
            Guid.NewGuid(), new TransferCommissionRequest(1000, new string('a', 129)), CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
        Assert.Equal(0, CountTransfers(dbName));
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 5) idempotency (مستوى التطبيق) — إعادة نتيجة سجلّ موجود بلا نداء FTTH
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task Transfer_Replay_Succeeded_Returns_Ok_Without_Ftth()
    {
        var dbName = Guid.NewGuid().ToString();
        var accountId = Guid.NewGuid();
        SeedAccount(dbName, accountId, CompanyA, UserA1);
        SeedTransfer(dbName, CompanyA, UserA1, accountId, "req-dup-ok",
            FtthCommissionTransferStatus.Succeeded, 200, "تم بنجاح");

        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA1);

        var result = await ctrl.TransferCommission(
            accountId, new TransferCommissionRequest(5000, "req-dup-ok"), CancellationToken.None);

        Assert.IsType<OkObjectResult>(result);
        Assert.Equal(1, CountTransfers(dbName)); // لم يُنشأ سجلّ جديد
    }

    [Fact]
    public async Task Transfer_Replay_Failed_Returns_Same_Error_Code_Without_Ftth()
    {
        var dbName = Guid.NewGuid().ToString();
        var accountId = Guid.NewGuid();
        SeedAccount(dbName, accountId, CompanyA, UserA1);
        SeedTransfer(dbName, CompanyA, UserA1, accountId, "req-dup-fail",
            FtthCommissionTransferStatus.Failed, 400, "المبلغ يتجاوز رصيد العمولة");

        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA1);

        var result = await ctrl.TransferCommission(
            accountId, new TransferCommissionRequest(5000, "req-dup-fail"), CancellationToken.None);

        Assert.Equal(400, StatusCodeOf(result)); // نفس رمز الفشل المسجّل
        Assert.Equal(1, CountTransfers(dbName));
    }

    [Fact]
    public async Task Transfer_Replay_Pending_Returns_409_Without_Ftth()
    {
        var dbName = Guid.NewGuid().ToString();
        var accountId = Guid.NewGuid();
        SeedAccount(dbName, accountId, CompanyA, UserA1);
        SeedTransfer(dbName, CompanyA, UserA1, accountId, "req-dup-pending",
            FtthCommissionTransferStatus.Pending);

        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA1);

        var result = await ctrl.TransferCommission(
            accountId, new TransferCommissionRequest(5000, "req-dup-pending"), CancellationToken.None);

        Assert.Equal(409, StatusCodeOf(result));
        Assert.Equal(1, CountTransfers(dbName));
    }

    [Fact]
    public async Task Transfer_Replay_Is_Scoped_By_Company_RequestId_Of_Other_Company_Does_Not_Match()
    {
        // سجلّ ناجح بنفس RequestId لكن لشركة أخرى (ب) يجب ألّا يُعامَل كتكرار لشركة أ.
        // (الحساب نفسه يخصّ شركة أ؛ هنا نثبت أنّ مفتاح idempotency يشمل CompanyId.)
        var dbName = Guid.NewGuid().ToString();
        var accountId = Guid.NewGuid();
        SeedAccount(dbName, accountId, CompanyA, UserA1);
        SeedTransfer(dbName, CompanyB, UserA2, accountId, "shared-req",
            FtthCommissionTransferStatus.Succeeded, 200, "تم");

        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, UserA1);

        // لا يوجد سجلّ لشركة أ بهذا المعرّف ⇒ يتجاوز idempotency ويُنشئ سجلّاً جديداً لشركة أ ثم يبلغ طبقة FTTH
        // (تسجيل الدخول يفشل لأنّ IHttpClientFactory غير قابل للنداء ⇒ 502). الدليل القاطع على عدم اعتباره
        // تكراراً: إنشاء سجلّ جديد ثانٍ (شركة أ) ⇒ المجموع 2 (سجلّ شركة ب + سجلّ شركة أ الجديد).
        var result = await ctrl.TransferCommission(
            accountId, new TransferCommissionRequest(1000, "shared-req"), CancellationToken.None);

        Assert.NotEqual(200, StatusCodeOf(result));            // ليست إعادة نجاح (لم يُعامَل كتكرار)
        Assert.IsNotType<OkObjectResult>(result);
        Assert.Equal(2, CountTransfers(dbName));               // أُنشئ سجلّ جديد لشركة أ
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 6) الصلاحية transfer_commission — اختبار وحدة على HasPermission
    //    ملاحظة: [RequirePermission(..., failClosed:true)] فلتر تفويض يعمل في خط أنابيب MVC،
    //    ولا ينفّذ عند استدعاء الأكشن مباشرةً كما في الاختبارات أعلاه. لذا نختبر قرار الصلاحية
    //    عبر الدالة الثابتة HasPermission (نفس نمط اختبارات sas_agent). SuperAdmin يتجاوز داخل
    //    الفلتر نفسه (OnAuthorizationAsync)، ولا يوجد منح تلقائي لأدمن الشركة لهذا المفتاح
    //    (المنح التلقائي محصور بمفتاح linked_accounts فقط في الفلتر).
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public void Permission_NullPermissions_FailClosed_Denies()
        => Assert.False(RequirePermissionAttribute.HasPermission(null, "transfer_commission", "view", failClosed: true));

    [Fact]
    public void Permission_EmptyPermissions_FailClosed_Denies()
        => Assert.False(RequirePermissionAttribute.HasPermission("", "transfer_commission", "view", failClosed: true));

    [Fact]
    public void Permission_ExplicitGrant_Allows()
    {
        const string json = """{"transfer_commission":{"view":true}}""";
        Assert.True(RequirePermissionAttribute.HasPermission(json, "transfer_commission", "view", failClosed: true));
    }

    [Fact]
    public void Permission_ExplicitDeny_Denies_Regardless_Of_FailClosed()
    {
        const string json = """{"transfer_commission":{"view":false}}""";
        Assert.False(RequirePermissionAttribute.HasPermission(json, "transfer_commission", "view", failClosed: true));
        Assert.False(RequirePermissionAttribute.HasPermission(json, "transfer_commission", "view", failClosed: false));
    }

    [Fact]
    public void Permission_Other_Keys_Do_Not_Grant_Transfer()
    {
        // امتلاك صلاحيات أخرى (مثل linked_accounts) لا يمنح transfer_commission.
        const string json = """{"linked_accounts":{"view":true,"edit":true}}""";
        Assert.False(RequirePermissionAttribute.HasPermission(json, "transfer_commission", "view", failClosed: true));
    }
}
