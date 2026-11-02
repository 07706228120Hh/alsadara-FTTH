using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Sadara.API.Controllers;
using Sadara.Application.Interfaces;
using Sadara.Domain.Entities;
using Sadara.Infrastructure.Data;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// اختبارات «حارس تحويل العمولة» على <b>المسار الحيّ</b> لـ FTTH
/// (<c>POST /api/linked-accounts/ftth/{id}/transfer-commission</c>) — الجزء الذي كان غير قابل للاختبار قبل
/// استخراج نداءات FTTH خلف <see cref="IFtthCommissionClient"/>.
///
/// تُزيّف الواجهة بعميل مبرمَج (<see cref="ScriptedFtthClient"/>) يعدّ النداءات ويعيد قيماً مُحدّدة — دون أي
/// شبكة فعلية — فيصبح بالإمكان تغطية:
///  - الحارس المالي: <c>amount &gt; الرصيد الحيّ ⇒ 400</c> بصفر نداء تحويل، والسجلّ ليس Succeeded.
///  - المسار الناجح: <c>amount ≤ الرصيد ⇒ تنفيذ التحويل + Succeeded + 200</c>.
///  - فشل التحويل لدى FTTH ⇒ السجلّ Failed بالرمز الوارد.
///  - فشل الدخول ⇒ لا جلب رصيد ولا تحويل.
///  - idempotency مع عميل مُزيّف: إعادة طلب Succeeded ⇒ لا نداء تحويل ثانٍ.
///
/// EF InMemory معزول (dbName فريد) + استدعاء الأكشن مباشرةً. لا قاعدة حقيقية ولا Docker.
/// </summary>
public class FtthCommissionTransferClientGuardTests
{
    private static readonly Guid CompanyA = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid UserA1 = Guid.Parse("a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1");

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

    private sealed class ThrowingHttpClientFactory : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) =>
            throw new InvalidOperationException("لا يُستخدم IHttpClientFactory — FTTH عبر الواجهة المُزيّفة");
    }

    /// <summary>عميل FTTH مبرمَج: يعدّ النداءات ويعيد نتائج مُحدّدة سلفاً دون أي شبكة.</summary>
    private sealed class ScriptedFtthClient : IFtthCommissionClient
    {
        public FtthLoginResult LoginResult { get; set; } = new(true, "access-token", "refresh-token", null);
        public string? PartnerId { get; set; } = "P-123";
        public decimal? CommissionBalance { get; set; } = 10000m;
        public FtthTransferResult TransferResult { get; set; } = new(true, 200, null);

        public int LoginCalls { get; private set; }
        public int PartnerIdCalls { get; private set; }
        public int BalanceCalls { get; private set; }
        public int TransferCalls { get; private set; }
        public long? LastTransferAmount { get; private set; }

        public Task<FtthLoginResult> LoginAsync(string serverUrl, string username, string password, CancellationToken ct)
        {
            LoginCalls++;
            return Task.FromResult(LoginResult);
        }

        public Task<string?> GetPartnerIdAsync(string serverUrl, string accessToken, CancellationToken ct)
        {
            PartnerIdCalls++;
            return Task.FromResult(PartnerId);
        }

        public Task<decimal?> GetCommissionBalanceAsync(string serverUrl, string accessToken, string partnerId, CancellationToken ct)
        {
            BalanceCalls++;
            return Task.FromResult(CommissionBalance);
        }

        public Task<FtthTransferResult> TransferAsync(string serverUrl, string accessToken, string partnerId, long amount, string requestId, CancellationToken ct)
        {
            TransferCalls++;
            LastTransferAmount = amount;
            return Task.FromResult(TransferResult);
        }
    }

    // ── بناة ─────────────────────────────────────────────────────────────────

    private static SadaraDbContext NewContext(string dbName, ICurrentTenant tenant)
        => new(new DbContextOptionsBuilder<SadaraDbContext>()
            .UseInMemoryDatabase(dbName).Options, tenant);

    private static IConfiguration EmptyConfig() => new ConfigurationBuilder().Build();

    private static LinkedAccountsController BuildController(
        SadaraDbContext db, ICurrentTenant tenant, IFtthCommissionClient ftthClient, Guid currentUserId)
    {
        var ctrl = new LinkedAccountsController(
            db, tenant,
            new FakeSecretProtector(),
            ftthClient,
            new ThrowingHttpClientFactory(),
            EmptyConfig(),
            NullLogger<LinkedAccountsController>.Instance);

        var claims = new List<Claim> { new(ClaimTypes.NameIdentifier, currentUserId.ToString()) };
        var identity = new ClaimsIdentity(claims, "TestScheme");
        ctrl.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext { User = new ClaimsPrincipal(identity) }
        };
        return ctrl;
    }

    private static void SeedAccount(string dbName, Guid accountId, Guid companyId, Guid ownerUserId)
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
        });
        seed.SaveChanges();
    }

    private static void SeedTransfer(
        string dbName, Guid companyId, Guid ownerUserId, Guid accountId,
        string requestId, string status, int? ftthCode = null, string? message = null)
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
        });
        seed.SaveChanges();
    }

    private static FtthCommissionTransfer GetTransfer(string dbName, string requestId)
    {
        var sys = new FakeTenant { BypassTenantFilter = true, IsSuperAdmin = true };
        using var check = NewContext(dbName, sys);
        return check.FtthCommissionTransfers.IgnoreQueryFilters().Single(x => x.RequestId == requestId);
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
    // 1) الحارس المالي: amount > الرصيد الحيّ ⇒ 400 بصفر نداء تحويل
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task Amount_Exceeds_Live_Balance_Returns_400_And_No_Transfer_Call()
    {
        var dbName = Guid.NewGuid().ToString();
        var accountId = Guid.NewGuid();
        SeedAccount(dbName, accountId, CompanyA, UserA1);

        var ftth = new ScriptedFtthClient { CommissionBalance = 5000m }; // رصيد حيّ 5000
        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, ftth, UserA1);

        var result = await ctrl.TransferCommission(
            accountId, new TransferCommissionRequest(6000, "req-over"), CancellationToken.None); // 6000 > 5000

        Assert.Equal(400, StatusCodeOf(result));
        Assert.Equal(0, ftth.TransferCalls);                 // صفر نداء تحويل
        Assert.Equal(1, ftth.BalanceCalls);                  // جُلب الرصيد أولاً

        var rec = GetTransfer(dbName, "req-over");
        Assert.Equal(FtthCommissionTransferStatus.Failed, rec.Status); // مُحسَم فشلاً، ليس Succeeded
        Assert.NotEqual(FtthCommissionTransferStatus.Succeeded, rec.Status);
        Assert.Equal(400, rec.FtthResponseCode);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 2) المسار الناجح: amount ≤ الرصيد ⇒ تنفيذ التحويل + Succeeded + 200
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task Amount_Within_Balance_Executes_Transfer_And_Records_Succeeded()
    {
        var dbName = Guid.NewGuid().ToString();
        var accountId = Guid.NewGuid();
        SeedAccount(dbName, accountId, CompanyA, UserA1);

        var ftth = new ScriptedFtthClient
        {
            CommissionBalance = 10000m,
            TransferResult = new FtthTransferResult(true, 200, null)
        };
        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, ftth, UserA1);

        var result = await ctrl.TransferCommission(
            accountId, new TransferCommissionRequest(5000, "req-ok"), CancellationToken.None);

        Assert.IsType<OkObjectResult>(result);
        Assert.Equal(200, StatusCodeOf(result));
        Assert.Equal(1, ftth.TransferCalls);
        Assert.Equal(5000, ftth.LastTransferAmount);         // المبلغ مُمرَّر كما هو

        var rec = GetTransfer(dbName, "req-ok");
        Assert.Equal(FtthCommissionTransferStatus.Succeeded, rec.Status);
        Assert.Equal(200, rec.FtthResponseCode);
        Assert.Equal("P-123", rec.PartnerId);                // partnerId الحيّ مُثبَّت في السجلّ
    }

    [Fact]
    public async Task Amount_Equal_To_Balance_Is_Allowed_And_Succeeds()
    {
        var dbName = Guid.NewGuid().ToString();
        var accountId = Guid.NewGuid();
        SeedAccount(dbName, accountId, CompanyA, UserA1);

        var ftth = new ScriptedFtthClient { CommissionBalance = 7000m };
        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, ftth, UserA1);

        var result = await ctrl.TransferCommission(
            accountId, new TransferCommissionRequest(7000, "req-eq"), CancellationToken.None); // == الرصيد

        Assert.Equal(200, StatusCodeOf(result));
        Assert.Equal(1, ftth.TransferCalls);
        Assert.Equal(FtthCommissionTransferStatus.Succeeded, GetTransfer(dbName, "req-eq").Status);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 3) فشل التحويل لدى FTTH ⇒ السجلّ Failed بالرمز الوارد
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task Transfer_Fails_At_Ftth_Records_Failed_With_Returned_Code()
    {
        var dbName = Guid.NewGuid().ToString();
        var accountId = Guid.NewGuid();
        SeedAccount(dbName, accountId, CompanyA, UserA1);

        var ftth = new ScriptedFtthClient
        {
            CommissionBalance = 10000m,
            TransferResult = new FtthTransferResult(false, 409, "فشل تحويل العمولة لدى نظام FTTH: 409")
        };
        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, ftth, UserA1);

        var result = await ctrl.TransferCommission(
            accountId, new TransferCommissionRequest(5000, "req-fail"), CancellationToken.None);

        Assert.Equal(409, StatusCodeOf(result));             // الرمز الوارد من FTTH يُمرَّر
        Assert.Equal(1, ftth.TransferCalls);                 // جرى النداء فعلاً ثم فشل

        var rec = GetTransfer(dbName, "req-fail");
        Assert.Equal(FtthCommissionTransferStatus.Failed, rec.Status);
        Assert.Equal(409, rec.FtthResponseCode);
    }

    [Fact]
    public async Task Transfer_Ftth_Network_Error_Maps_To_502()
    {
        var dbName = Guid.NewGuid().ToString();
        var accountId = Guid.NewGuid();
        SeedAccount(dbName, accountId, CompanyA, UserA1);

        // عند خطأ شبكة يعيد التنفيذ الحقيقي StatusCode=0 ⇒ FinalizeTransferAsync يربطه إلى 502.
        var ftth = new ScriptedFtthClient
        {
            CommissionBalance = 10000m,
            TransferResult = new FtthTransferResult(false, 0, "تعذّر الاتصال بنظام FTTH")
        };
        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, ftth, UserA1);

        var result = await ctrl.TransferCommission(
            accountId, new TransferCommissionRequest(5000, "req-neterr"), CancellationToken.None);

        Assert.Equal(502, StatusCodeOf(result));             // رمز غير صالح (0) ⇒ 502
        Assert.Equal(FtthCommissionTransferStatus.Failed, GetTransfer(dbName, "req-neterr").Status);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 4) فشل الدخول ⇒ لا جلب رصيد ولا تحويل
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task Login_Fails_No_Balance_Fetch_No_Transfer()
    {
        var dbName = Guid.NewGuid().ToString();
        var accountId = Guid.NewGuid();
        SeedAccount(dbName, accountId, CompanyA, UserA1);

        var ftth = new ScriptedFtthClient { LoginResult = new FtthLoginResult(false, null, null, "فشل الدخول") };
        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, ftth, UserA1);

        var result = await ctrl.TransferCommission(
            accountId, new TransferCommissionRequest(5000, "req-nologin"), CancellationToken.None);

        Assert.Equal(502, StatusCodeOf(result));
        Assert.Equal(1, ftth.LoginCalls);
        Assert.Equal(0, ftth.PartnerIdCalls);                // لم يُجلب partnerId
        Assert.Equal(0, ftth.BalanceCalls);                  // ولا الرصيد
        Assert.Equal(0, ftth.TransferCalls);                 // ولا تحويل
        Assert.Equal(FtthCommissionTransferStatus.Failed, GetTransfer(dbName, "req-nologin").Status);
    }

    [Fact]
    public async Task PartnerId_Resolution_Fails_No_Balance_No_Transfer()
    {
        var dbName = Guid.NewGuid().ToString();
        var accountId = Guid.NewGuid();
        SeedAccount(dbName, accountId, CompanyA, UserA1);

        var ftth = new ScriptedFtthClient { PartnerId = null }; // تعذّر تحديد الشريك
        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, ftth, UserA1);

        var result = await ctrl.TransferCommission(
            accountId, new TransferCommissionRequest(5000, "req-nopartner"), CancellationToken.None);

        Assert.Equal(502, StatusCodeOf(result));
        Assert.Equal(1, ftth.PartnerIdCalls);
        Assert.Equal(0, ftth.BalanceCalls);
        Assert.Equal(0, ftth.TransferCalls);
        Assert.Equal(FtthCommissionTransferStatus.Failed, GetTransfer(dbName, "req-nopartner").Status);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 5) idempotency مع عميل مُزيّف: إعادة طلب Succeeded ⇒ لا نداء تحويل ثانٍ
    // ══════════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task Replay_Succeeded_RequestId_Does_Not_Call_Ftth_Again()
    {
        var dbName = Guid.NewGuid().ToString();
        var accountId = Guid.NewGuid();
        SeedAccount(dbName, accountId, CompanyA, UserA1);
        SeedTransfer(dbName, CompanyA, UserA1, accountId, "req-replay",
            FtthCommissionTransferStatus.Succeeded, 200, "تم بنجاح");

        var ftth = new ScriptedFtthClient(); // سينفّذ لو وصل إليه — ونتأكّد أنّه لم يصل
        var tenantA = new FakeTenant { CompanyId = CompanyA, BypassTenantFilter = false };
        using var db = NewContext(dbName, tenantA);
        var ctrl = BuildController(db, tenantA, ftth, UserA1);

        var result = await ctrl.TransferCommission(
            accountId, new TransferCommissionRequest(5000, "req-replay"), CancellationToken.None);

        Assert.IsType<OkObjectResult>(result);               // تُعاد نتيجة النجاح المسجّلة
        Assert.Equal(0, ftth.LoginCalls);                    // لا دخول
        Assert.Equal(0, ftth.TransferCalls);                 // ولا تحويل ثانٍ (replay)
        Assert.Equal(1, CountTransfers(dbName));             // لم يُنشأ سجلّ جديد
    }
}
