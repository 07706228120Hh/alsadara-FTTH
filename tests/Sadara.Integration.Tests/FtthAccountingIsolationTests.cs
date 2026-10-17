using System.Reflection;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Abstractions;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.AspNetCore.Routing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Sadara.API.Authorization;
using Sadara.API.Controllers;
using Sadara.Application.Interfaces;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;
using Sadara.Infrastructure.Data;
using Sadara.Infrastructure.Repositories;
using Sadara.Integration.Tests.Support;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// Dedicated Postgres container (Testcontainers) for the Phase 0-B FTTH accounting / zone fee
/// isolation tests — kept separate from the shared "Postgres" collection so seeded users/logs can
/// never interfere with the ServiceRequests summary tests.
/// </summary>
[CollectionDefinition("FtthIsolationPostgres")]
public sealed class FtthIsolationPostgresCollection : ICollectionFixture<PostgresFixture>
{
}

/// <summary>
/// Phase 0-B: tenant isolation + permission gates for <see cref="FtthAccountingController"/> and
/// <see cref="ZoneMaintenanceFeesController"/>.
///
/// Controllers are invoked directly (same style as the existing integration tests) on a real Postgres,
/// with a caller principal/tenant that mimics production (EnforceIsolation = false ⇒ isolation must come
/// from the controller). Framework-level attributes are verified by reflection, and the
/// <see cref="RequirePermissionAttribute"/> filter is executed for real against citizen principals.
/// </summary>
[Collection("FtthIsolationPostgres")]
public class FtthAccountingIsolationTests
{
    private readonly PostgresFixture _fx;

    public FtthAccountingIsolationTests(PostgresFixture fx) => _fx = fx;

    private const string FullFtthPerms =
        "{\"accounting\":{\"view\":true,\"add\":true,\"edit\":true,\"delete\":true}," +
        "\"accounting.ftth_operators\":{\"view\":true,\"add\":true,\"edit\":true}}";

    /// <summary>V2 JSON that is set (not fail-open) but grants nothing relevant.</summary>
    private const string UnrelatedPerms = "{\"attendance\":{\"view\":true}}";

    // ═══════════════════════════ World seeding ═══════════════════════════

    private sealed class World
    {
        public Guid CompanyA { get; init; }
        public Guid CompanyB { get; init; }
        public Guid AdminA { get; init; }        // employee of A with full FTTH accounting perms
        public Guid OperatorA { get; init; }     // operator of A
        public Guid NoPermA { get; init; }       // employee of A, both V2 columns set, no accounting/subscriptions
        public Guid ActivatorA { get; init; }    // employee of A, only Second-system "subscriptions"
        public Guid CitizenUserA { get; init; }  // Users row with Role=Citizen in A, EMPTY V2 (fail-open)
        public Guid OperatorB { get; init; }     // operator of B
        public long LogA { get; init; }          // log of A by OperatorA
        public long LogActivatorA { get; init; } // log of A created by ActivatorA
        public long LogB { get; init; }          // log of B by OperatorB
        public long LogOrphan { get; init; }     // legacy log with CompanyId = null by OperatorA
        public Guid FeeA { get; init; }
        public Guid FeeB { get; init; }
        public string ZoneName { get; init; } = "";
    }

    private static int _phoneSeq;

    private World SeedWorld()
    {
        var a = Guid.NewGuid();
        var b = Guid.NewGuid();
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);

        ctx.Set<Company>().AddRange(
            new Company { Id = a, Name = "شركة أ", Code = "A-" + a.ToString("N")[..10] },
            new Company { Id = b, Name = "شركة ب", Code = "B-" + b.ToString("N")[..10] });

        Guid AddUser(Guid company, UserRole role, string? firstPerms, string? secondPerms = null, string name = "موظف")
        {
            var id = Guid.NewGuid();
            ctx.Set<User>().Add(new User
            {
                Id = id,
                Username = "u" + id.ToString("N")[..12],
                FullName = name,
                PhoneNumber = "0770" + Interlocked.Increment(ref _phoneSeq).ToString("D7"),
                CompanyId = company,
                Role = role,
                FirstSystemPermissionsV2 = firstPerms,
                SecondSystemPermissionsV2 = secondPerms,
            });
            return id;
        }

        var adminA = AddUser(a, UserRole.Manager, FullFtthPerms, name: "مدير أ");
        var operatorA = AddUser(a, UserRole.Employee, UnrelatedPerms, name: "مشغل أ");
        // Both V2 columns set (an empty column is fail-open per system — existing RequirePermission semantics).
        var noPermA = AddUser(a, UserRole.Employee, UnrelatedPerms, UnrelatedPerms, name: "بلا صلاحية أ");
        var activatorA = AddUser(a, UserRole.Employee, UnrelatedPerms,
            "{\"subscriptions\":{\"view\":true,\"add\":true}}", name: "مفعّل أ");
        var citizenUserA = AddUser(a, UserRole.Citizen, null, name: "مواطن أ");
        var operatorB = AddUser(b, UserRole.Employee, UnrelatedPerms, name: "مشغل ب");
        ctx.SaveChanges();

        SubscriptionLog Log(Guid? company, Guid userId) => new()
        {
            CompanyId = company,
            UserId = userId,
            CustomerName = "زبون",
            PhoneNumber = "07800000000",
            PlanName = "FIBER 35",
            PlanPrice = 35000,
            CollectionType = "credit",
            ActivationDate = DateTime.UtcNow.AddDays(-1),
            OperationType = "تجديد",
        };
        var logA = Log(a, operatorA);
        var logActA = Log(a, activatorA);
        var logB = Log(b, operatorB);
        var logOrphan = Log(null, operatorA);
        ctx.Set<SubscriptionLog>().AddRange(logA, logActA, logB, logOrphan);

        var zone = "FBG-" + Guid.NewGuid().ToString("N")[..6];
        var feeA = new ZoneMaintenanceFee { Id = Guid.NewGuid(), ZoneName = zone, MaintenanceAmount = 1000, IsEnabled = true, CompanyId = a };
        var feeB = new ZoneMaintenanceFee { Id = Guid.NewGuid(), ZoneName = zone, MaintenanceAmount = 9999, IsEnabled = true, CompanyId = b };
        ctx.Set<ZoneMaintenanceFee>().AddRange(feeA, feeB);
        ctx.SaveChanges();

        return new World
        {
            CompanyA = a, CompanyB = b,
            AdminA = adminA, OperatorA = operatorA, NoPermA = noPermA, ActivatorA = activatorA,
            CitizenUserA = citizenUserA, OperatorB = operatorB,
            LogA = logA.Id, LogActivatorA = logActA.Id, LogB = logB.Id, LogOrphan = logOrphan.Id,
            FeeA = feeA.Id, FeeB = feeB.Id, ZoneName = zone,
        };
    }

    // ═══════════════════════════ Builders / helpers ═══════════════════════════

    private sealed record Caller(Guid UserId, Guid? CompanyId, string? Role, bool CitizenToken = false);

    private static ClaimsPrincipal Principal(Caller c)
    {
        var claims = new List<Claim> { new(ClaimTypes.NameIdentifier, c.UserId.ToString()) };
        if (c.Role is not null) claims.Add(new Claim(ClaimTypes.Role, c.Role));
        if (c.CompanyId.HasValue)
            claims.Add(new Claim(c.CitizenToken ? "companyId" : "company_id", c.CompanyId.Value.ToString()));
        if (c.CitizenToken) claims.Add(new Claim("type", "citizen"));
        return new ClaimsPrincipal(new ClaimsIdentity(claims, "TestAuth"));
    }

    private static TestTenant Tenant(Caller c) => new()
    {
        CompanyId = c.CompanyId,
        IsSuperAdmin = c.Role == "SuperAdmin",
        BypassTenantFilter = c.Role == "SuperAdmin",
        EnforceIsolation = false, // production default — isolation must come from the controller
    };

    private (FtthAccountingController ctrl, SadaraDbContext db) Ftth(Caller c)
    {
        var tenant = Tenant(c);
        var db = _fx.CreateContext(tenant);
        var ctrl = new FtthAccountingController(
            new UnitOfWork(db),
            NullLogger<FtthAccountingController>.Instance,
            new ConfigurationBuilder().Build(),
            tenant)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext { User = Principal(c) } }
        };
        return (ctrl, db);
    }

    private (ZoneMaintenanceFeesController ctrl, SadaraDbContext db) Zones(Caller c)
    {
        var tenant = Tenant(c);
        var db = _fx.CreateContext(tenant);
        var ctrl = new ZoneMaintenanceFeesController(new UnitOfWork(db), tenant)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext { User = Principal(c) } }
        };
        return (ctrl, db);
    }

    private static int StatusOf(IActionResult r) => r switch
    {
        ObjectResult o => o.StatusCode ?? 200,
        StatusCodeResult s => s.StatusCode,
        _ => throw new Xunit.Sdk.XunitException($"Unexpected result {r.GetType().Name}")
    };

    private static JsonElement BodyOf(IActionResult r) =>
        JsonSerializer.SerializeToElement(((ObjectResult)r).Value);

    private static void AssertDenied(IActionResult r, params int[] allowed)
    {
        var status = StatusOf(r);
        Assert.Contains(status, allowed.Length == 0 ? new[] { 403, 404 } : allowed);
        var body = BodyOf(r);
        Assert.False(body.GetProperty("success").GetBoolean());
        Assert.False(string.IsNullOrWhiteSpace(body.GetProperty("message").GetString()));
    }

    private SubscriptionLog ReadLog(long id)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        return ctx.Set<SubscriptionLog>().IgnoreQueryFilters().AsNoTracking().Single(l => l.Id == id);
    }

    private int JournalCount(Guid companyId)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        return ctx.Set<JournalEntry>().IgnoreQueryFilters().Count(j => j.CompanyId == companyId);
    }

    // ═══════════════════════════ Metadata (no DB) ═══════════════════════════

    [Fact]
    public void Controllers_Require_CompanyEmployee_Policy_At_Class_Level()
    {
        foreach (var type in new[] { typeof(FtthAccountingController), typeof(ZoneMaintenanceFeesController) })
        {
            var attrs = type.GetCustomAttributes<AuthorizeAttribute>(inherit: true).ToList();
            Assert.Contains(attrs, a => a.Policy == "CompanyEmployee");
            // no bare [Authorize] left on actions (would not add anything but hides intent)
            foreach (var m in type.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly))
                Assert.DoesNotContain(m.GetCustomAttributes<AuthorizeAttribute>(), a => a.Policy is null && a.Roles is null);
        }
    }

    /// <summary>Actions whose permission gate lives in code (OR-keys / self-access) — covered by behaviour tests below.</summary>
    private static readonly HashSet<string> InActionGated = new()
    {
        nameof(FtthAccountingController.GetOperatorSummary),
        nameof(FtthAccountingController.UpdateSubscriptionLog),
        nameof(FtthAccountingController.LinkFtthAccount),
        nameof(FtthAccountingController.GetFtthCredentials),
        nameof(FtthAccountingController.GetAgentsList),
        nameof(FtthAccountingController.GetTechniciansList),
        nameof(FtthAccountingController.GetOperatorsLinking),
        nameof(FtthAccountingController.GetFundsOverview),
        nameof(ZoneMaintenanceFeesController.CheckZone),
    };

    /// <summary>Known exception (Phase 0-A / deferred P0-3): API-key guarded, left unchanged here.</summary>
    private static readonly HashSet<string> AnonymousAllowList = new()
    {
        nameof(FtthAccountingController.RecalculateSyncRevenues),
    };

    [Fact]
    public void Every_Action_Has_A_Permission_Gate()
    {
        foreach (var type in new[] { typeof(FtthAccountingController), typeof(ZoneMaintenanceFeesController) })
        {
            var actions = type.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly)
                .Where(m => m.GetCustomAttributes().Any(a => a is Microsoft.AspNetCore.Mvc.Routing.HttpMethodAttribute));
            foreach (var m in actions)
            {
                var anonymous = m.GetCustomAttributes<AllowAnonymousAttribute>().Any();
                if (anonymous)
                {
                    Assert.Contains(m.Name, AnonymousAllowList);
                    continue;
                }
                var gated = m.GetCustomAttributes<RequirePermissionAttribute>().Any()
                            || m.GetCustomAttributes<AuthorizeAttribute>().Any(a => a.Policy == "SuperAdmin")
                            || InActionGated.Contains(m.Name);
                Assert.True(gated, $"{type.Name}.{m.Name} has no permission gate");
            }
        }
    }

    // ═══════════════════════════ Citizen tokens ═══════════════════════════

    [SkippableFact]
    public async Task RequirePermission_Filter_Rejects_Citizen_Token()
    {
        _fx.SkipIfUnavailable();
        var w = SeedWorld();
        // Citizen JWT: NameIdentifier = Citizens.Id (no Users row), claim type=citizen, no role.
        var citizen = new Caller(Guid.NewGuid(), w.CompanyA, Role: null, CitizenToken: true);

        var attr = typeof(FtthAccountingController)
            .GetMethod(nameof(FtthAccountingController.GetOperatorsDashboard))!
            .GetCustomAttribute<RequirePermissionAttribute>()!;

        using var db = _fx.CreateContext(Tenant(citizen));
        var services = new ServiceCollection().AddSingleton<IUnitOfWork>(new UnitOfWork(db)).BuildServiceProvider();
        var http = new DefaultHttpContext { User = Principal(citizen), RequestServices = services };
        var ctx = new AuthorizationFilterContext(
            new ActionContext(http, new RouteData(), new ActionDescriptor { EndpointMetadata = new List<object>() }),
            new List<IFilterMetadata>());

        await attr.OnAuthorizationAsync(ctx);

        Assert.NotNull(ctx.Result);
        Assert.True(ctx.Result is ForbidResult || (ctx.Result is ObjectResult o && o.StatusCode == 403));
    }

    [SkippableFact]
    public async Task InAction_Gates_Reject_Citizen_Tokens_And_Citizen_User_Rows()
    {
        _fx.SkipIfUnavailable();
        var w = SeedWorld();
        var citizenJwt = new Caller(Guid.NewGuid(), w.CompanyA, Role: null, CitizenToken: true);
        // Users row with Role=Citizen and EMPTY V2 JSON: RequirePermission alone is fail-open for it.
        var citizenRow = new Caller(w.CitizenUserA, w.CompanyA, Role: "Citizen");

        foreach (var c in new[] { citizenJwt, citizenRow })
        {
            var (ctrl, db) = Ftth(c);
            using (db)
            {
                AssertDenied(await ctrl.GetTechniciansList(null), 403);
                AssertDenied(await ctrl.GetAgentsList(null), 403);
                AssertDenied(await ctrl.GetOperatorSummary(w.OperatorA), 403);
                AssertDenied(await ctrl.GetFundsOverview(null), 403);
                AssertDenied(await ctrl.GetOperatorsLinking(null), 403);
                AssertDenied(await ctrl.GetFtthCredentials(w.OperatorA), 403);
                AssertDenied(await ctrl.UpdateSubscriptionLog(w.LogA,
                    JsonSerializer.SerializeToElement(new { PlanPrice = 1 })), 403, 404);
            }

            var (zones, zdb) = Zones(c);
            using (zdb)
                AssertDenied(await zones.CheckZone(w.ZoneName, null), 403);
        }
    }

    // ═══════════════════════════ Read isolation ═══════════════════════════

    [SkippableFact]
    public async Task OperatorsDashboard_Ignores_Client_CompanyId_And_Excludes_Orphans()
    {
        _fx.SkipIfUnavailable();
        var w = SeedWorld();
        var (ctrl, db) = Ftth(new Caller(w.AdminA, w.CompanyA, "Manager"));
        using var _ = db;

        // Client asks for company B — server must answer with company A only.
        var res = await ctrl.GetOperatorsDashboard(companyId: w.CompanyB);
        Assert.Equal(200, StatusOf(res));
        var body = BodyOf(res);

        var userIds = body.GetProperty("data").EnumerateArray()
            .Select(r => r.GetProperty("userId").GetString()).ToList();
        Assert.DoesNotContain(w.OperatorB.ToString(), userIds);
        Assert.Contains(w.OperatorA.ToString(), userIds);
        // A has exactly 2 internet logs (LogA + LogActivatorA); the orphan and B's log are excluded.
        Assert.Equal(2, body.GetProperty("summary").GetProperty("totalActivations").GetInt32());
    }

    [SkippableFact]
    public async Task SuperAdmin_Keeps_CrossCompany_Capability()
    {
        _fx.SkipIfUnavailable();
        var w = SeedWorld();
        var (ctrl, db) = Ftth(new Caller(Guid.NewGuid(), null, "SuperAdmin"));
        using var _ = db;

        var res = await ctrl.GetOperatorsDashboard(companyId: w.CompanyB);
        Assert.Equal(200, StatusOf(res));
        var userIds = BodyOf(res).GetProperty("data").EnumerateArray()
            .Select(r => r.GetProperty("userId").GetString()).ToList();
        Assert.Contains(w.OperatorB.ToString(), userIds);
        Assert.DoesNotContain(w.OperatorA.ToString(), userIds);
    }

    [SkippableFact]
    public async Task OperatorSummary_CrossCompany_404_Self_200_OtherWithoutPerm_403()
    {
        _fx.SkipIfUnavailable();
        var w = SeedWorld();

        var (admin, db1) = Ftth(new Caller(w.AdminA, w.CompanyA, "Manager"));
        using (db1)
        {
            AssertDenied(await admin.GetOperatorSummary(w.OperatorB, companyId: w.CompanyB), 404);

            var ok = await admin.GetOperatorSummary(w.OperatorA, companyId: w.CompanyB);
            Assert.Equal(200, StatusOf(ok));
            // orphan log of the same operator is no longer pulled into the company report
            var ids = BodyOf(ok).GetProperty("data").GetProperty("transactions").EnumerateArray()
                .Select(t => t.GetProperty("Id").GetInt64()).ToList();
            Assert.Contains(w.LogA, ids);
            Assert.DoesNotContain(w.LogOrphan, ids);
        }

        var (op, db2) = Ftth(new Caller(w.OperatorA, w.CompanyA, "Employee"));
        using (db2)
        {
            Assert.Equal(200, StatusOf(await op.GetOperatorSummary(w.OperatorA)));         // self
            AssertDenied(await op.GetOperatorSummary(w.NoPermA), 403);                     // colleague, no perm
        }
    }

    [SkippableFact]
    public async Task TechniciansList_Is_Company_Scoped_And_Staff_Only()
    {
        _fx.SkipIfUnavailable();
        var w = SeedWorld();

        // Activation-screen user (Second-system "subscriptions" only) must keep working.
        var (ctrl, db) = Ftth(new Caller(w.ActivatorA, w.CompanyA, "Employee"));
        using var _ = db;

        var res = await ctrl.GetTechniciansList(companyId: null);
        Assert.Equal(200, StatusOf(res));
        var ids = BodyOf(res).GetProperty("data").EnumerateArray()
            .Select(u => u.GetProperty("Id").GetGuid()).ToList();

        Assert.Contains(w.OperatorA, ids);
        Assert.DoesNotContain(w.OperatorB, ids);      // other company
        Assert.DoesNotContain(w.CitizenUserA, ids);   // citizen row in same company

        var res2 = await ctrl.GetTechniciansList(companyId: w.CompanyB);
        var ids2 = BodyOf(res2).GetProperty("data").EnumerateArray()
            .Select(u => u.GetProperty("Id").GetGuid()).ToList();
        Assert.DoesNotContain(w.OperatorB, ids2);     // client companyId ignored
    }

    [SkippableFact]
    public async Task FtthCredentials_Self_Allowed_Other_Company_404()
    {
        _fx.SkipIfUnavailable();
        var w = SeedWorld();

        var (self, db1) = Ftth(new Caller(w.NoPermA, w.CompanyA, "Employee"));
        using (db1)
        {
            Assert.Equal(200, StatusOf(await self.GetFtthCredentials(w.NoPermA)));
            AssertDenied(await self.GetFtthCredentials(w.OperatorA), 403);
        }

        var (admin, db2) = Ftth(new Caller(w.AdminA, w.CompanyA, "Manager"));
        using (db2)
            AssertDenied(await admin.GetFtthCredentials(w.OperatorB), 404);
    }

    // ═══════════════════════════ Write isolation ═══════════════════════════

    [SkippableFact]
    public async Task Cash_And_Collection_Writes_Reject_Other_Company_Operator_And_Logs()
    {
        _fx.SkipIfUnavailable();
        var w = SeedWorld();
        var (ctrl, db) = Ftth(new Caller(w.AdminA, w.CompanyA, "Manager"));
        using var _ = db;
        var journalsB = JournalCount(w.CompanyB);

        // Client claims company B + B's operator → denied (company comes from the token).
        AssertDenied(await ctrl.DeliverCash(new OperatorCashDeliveryDto(w.OperatorB, 1000, w.CompanyB, null, null, null)), 404);
        AssertDenied(await ctrl.QuickDeliver(new QuickDeliverDto(w.OperatorB, 1000, w.CompanyB, null)), 404);
        AssertDenied(await ctrl.QuickCollect(new QuickCollectDto(w.OperatorB, 1000, w.CompanyB, null)), 404);
        AssertDenied(await ctrl.CollectCredit(new OperatorCreditCollectionDto(w.OperatorB, 1000, w.CompanyB, null, null, null)), 404);

        // Own operator but another company's log ids → denied before any journal entry.
        AssertDenied(await ctrl.QuickCollect(new QuickCollectDto(w.OperatorA, 1000, w.CompanyA, null,
            new List<long> { w.LogB })), 404);
        AssertDenied(await ctrl.CollectCredit(new OperatorCreditCollectionDto(w.OperatorA, 1000, w.CompanyA, w.LogB, null, null)), 404);
        AssertDenied(await ctrl.CollectRenewalMonth(new CollectRenewalMonthDto(w.LogB, w.CompanyB)), 404);

        Assert.Equal(journalsB, JournalCount(w.CompanyB));
        Assert.NotEqual("مسدد", ReadLog(w.LogB).PaymentStatus);
    }

    [SkippableFact]
    public async Task Log_Edits_Reject_Other_Company_Logs()
    {
        _fx.SkipIfUnavailable();
        var w = SeedWorld();
        var (ctrl, db) = Ftth(new Caller(w.AdminA, w.CompanyA, "Manager"));
        using var _ = db;

        AssertDenied(await ctrl.SetRenewalCycle(new SetRenewalCycleDto(w.LogB, 6, 1)), 404);
        AssertDenied(await ctrl.UpdateSubscriptionLog(w.LogB,
            JsonSerializer.SerializeToElement(new { PlanPrice = 1, CustomerName = "x" })), 404);
        AssertDenied(await ctrl.SetRenewalCycle(new SetRenewalCycleDto(w.LogOrphan, 6, 1)), 404);

        var logB = ReadLog(w.LogB);
        Assert.Null(logB.RenewalCycleMonths);
        Assert.Equal(35000, logB.PlanPrice);

        // Same-company edit still works for the legitimate caller.
        Assert.Equal(200, StatusOf(await ctrl.SetRenewalCycle(new SetRenewalCycleDto(w.LogA, 3, 1))));
        Assert.Equal(3, ReadLog(w.LogA).RenewalCycleMonths);
    }

    [SkippableFact]
    public async Task UpdateSubscriptionLog_Activation_Screen_Narrow_Path()
    {
        _fx.SkipIfUnavailable();
        var w = SeedWorld();
        var (ctrl, db) = Ftth(new Caller(w.ActivatorA, w.CompanyA, "Employee"));
        using var _ = db;

        // Exactly what subscription_details_page sends for its own just-saved log → allowed.
        var mark = JsonSerializer.SerializeToElement(new
        {
            IsReconciled = false,
            ReconciliationNotes = "⚠️ بحاجة للتحقق: timeout",
            PaymentStatus = "pending_verification",
        });
        Assert.Equal(200, StatusOf(await ctrl.UpdateSubscriptionLog(w.LogActivatorA, mark)));
        Assert.Equal("pending_verification", ReadLog(w.LogActivatorA).PaymentStatus);

        // Any financial field → forbidden without accounting edit.
        AssertDenied(await ctrl.UpdateSubscriptionLog(w.LogActivatorA,
            JsonSerializer.SerializeToElement(new { PlanPrice = 1 })), 403);
        // Marking somebody else's log → forbidden.
        AssertDenied(await ctrl.UpdateSubscriptionLog(w.LogA, mark), 403);
        // Self-reconciling / marking as paid → forbidden.
        AssertDenied(await ctrl.UpdateSubscriptionLog(w.LogActivatorA,
            JsonSerializer.SerializeToElement(new { PaymentStatus = "مسدد" })), 403);
    }

    [SkippableFact]
    public async Task LogWithAccounting_Stamps_Token_Company_And_Rejects_Foreign_Operator()
    {
        _fx.SkipIfUnavailable();
        var w = SeedWorld();
        var (ctrl, db) = Ftth(new Caller(w.AdminA, w.CompanyA, "Manager"));
        using var _ = db;

        FtthLogWithAccountingDto Dto(Guid? userId) => new(
            "C1", "زبون", null, null, "FIBER 35", 0m, null, null, null, null, "renew", null,
            DateTime.UtcNow, null, null, w.ZoneName, null, null, null, null, null, null, null, null,
            null, null, null, null, userId, w.CompanyB, false, false, null, null, null, null, null,
            "cash", null, null, null, null, null, null, null, null);

        AssertDenied(await ctrl.LogWithAccounting(Dto(w.OperatorB)), 404);

        var ok = await ctrl.LogWithAccounting(Dto(null));
        Assert.Equal(200, StatusOf(ok));
        var logId = BodyOf(ok).GetProperty("logId").GetInt64();
        var log = ReadLog(logId);
        Assert.Equal(w.CompanyA, log.CompanyId);       // client sent B
        Assert.Equal(1000, log.MaintenanceFee);        // A's zone fee, not B's 9999
    }

    // ═══════════════════════════ Zone maintenance fees ═══════════════════════════

    [SkippableFact]
    public async Task ZoneFees_Are_Company_Isolated()
    {
        _fx.SkipIfUnavailable();
        var w = SeedWorld();
        var (ctrl, db) = Zones(new Caller(w.AdminA, w.CompanyA, "Manager"));
        using var _ = db;

        // GetAll with B → only A's fees
        var all = BodyOf(await ctrl.GetAll(w.CompanyB)).GetProperty("data").EnumerateArray()
            .Select(f => f.GetProperty("Id").GetGuid()).ToList();
        Assert.Contains(w.FeeA, all);
        Assert.DoesNotContain(w.FeeB, all);

        // check with B → A's amount
        var check = BodyOf(await ctrl.CheckZone(w.ZoneName, w.CompanyB));
        Assert.Equal(1000, check.GetProperty("amount").GetDecimal());

        // Update / Delete B's record → 404, untouched
        AssertDenied(await ctrl.Update(w.FeeB, new UpdateZoneMaintenanceFeeDto(null, 1, null, null)), 404);
        AssertDenied(await ctrl.Delete(w.FeeB), 404);

        // Create with client CompanyId=B → stored under A
        var newZone = "Z-" + Guid.NewGuid().ToString("N")[..6];
        Assert.Equal(200, StatusOf(await ctrl.Create(new CreateZoneMaintenanceFeeDto(newZone, null, 500, null, true, w.CompanyB))));
        Assert.Equal(200, StatusOf(await ctrl.BulkCreate(new BulkZoneMaintenanceFeeDto(w.CompanyB,
            new List<BulkZoneItem> { new(newZone + "-b", null, 600, null) }))));

        using var check2 = _fx.CreateContext(PostgresFixture.SystemTenant);
        var feeB = check2.Set<ZoneMaintenanceFee>().AsNoTracking().Single(f => f.Id == w.FeeB);
        Assert.Equal(9999, feeB.MaintenanceAmount);
        Assert.False(feeB.IsDeleted);
        var created = check2.Set<ZoneMaintenanceFee>().AsNoTracking()
            .Where(f => f.ZoneName == newZone || f.ZoneName == newZone + "-b").ToList();
        Assert.Equal(2, created.Count);
        Assert.All(created, f => Assert.Equal(w.CompanyA, f.CompanyId));
    }

    [SkippableFact]
    public async Task ZoneCheck_Allows_Activation_Screen_User()
    {
        _fx.SkipIfUnavailable();
        var w = SeedWorld();
        var (ctrl, db) = Zones(new Caller(w.ActivatorA, w.CompanyA, "Employee"));
        using var _ = db;

        var res = await ctrl.CheckZone(w.ZoneName, null);
        Assert.Equal(200, StatusOf(res));
        Assert.True(BodyOf(res).GetProperty("hasMaintenanceFee").GetBoolean());

        // An employee with V2 set but none of the accepted keys is rejected.
        var (noPerm, db2) = Zones(new Caller(w.NoPermA, w.CompanyA, "Employee"));
        using (db2)
            AssertDenied(await noPerm.CheckZone(w.ZoneName, null), 403);
    }
}
