using System.IdentityModel.Tokens.Jwt;
using System.Reflection;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Abstractions;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using Sadara.API.Controllers;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;
using Sadara.Infrastructure.Repositories;
using Sadara.Integration.Tests.Support;
using Xunit;
using static Sadara.Integration.Tests.Support.TasksIsolationHarness;

namespace Sadara.Integration.Tests;

/// <summary>
/// Phase 0-D remediation round:
///  C1  agent / citizen JWTs rejected by the task controllers (CompanyEmployee policy + DB employee gate);
///  S3  technician /summary uses the same scope as the list (TechnicianId-only task counted in both);
///  S5  completion fee trusts TechnicianId on name mismatch; unresolved rename detaches the old technician;
///  S6  all-dues lists unlinked 1140 accounts instead of dropping them;
///  S12 SubscriptionLogs ActivatedBy resolution restricted to the caller company.
/// </summary>
[Collection("PostgresTasksIsolation")]
public class TasksRemediationTests
{
    private readonly PostgresFixture _fx;

    public TasksRemediationTests(PostgresFixture fx) => _fx = fx;

    private static readonly Type[] GatedControllers =
    {
        typeof(ServiceRequestsController), typeof(SubscriptionLogsController), typeof(TaskAuditsController)
    };

    // ══════════════════════════════════════════════════════════════════════
    // C1 — real tokens (same claims as AgentsController / CitizenAuthController / UnifiedAuthController)
    // ══════════════════════════════════════════════════════════════════════

    private const string SigningKey = "phase0-d-remediation-test-signing-key-0123456789abcdef";

    /// <summary>Issues and validates a real HS256 JWT ⇒ the principal has the same inbound claim mapping as the API.</summary>
    private static ClaimsPrincipal RealToken(IEnumerable<Claim> claims)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(SigningKey));
        var handler = new JwtSecurityTokenHandler();
        var jwt = handler.WriteToken(new JwtSecurityToken(
            issuer: "SadaraPlatform", audience: "SadaraClients", claims: claims,
            expires: DateTime.UtcNow.AddHours(1),
            signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256)));
        return handler.ValidateToken(jwt, new TokenValidationParameters
        {
            ValidIssuer = "SadaraPlatform",
            ValidAudience = "SadaraClients",
            IssuerSigningKey = key,
        }, out _);
    }

    /// <summary>AgentsController.GenerateAgentToken claims.</summary>
    private static ClaimsPrincipal AgentToken(Guid agentId, Guid companyId) => RealToken(new[]
    {
        new Claim(ClaimTypes.NameIdentifier, agentId.ToString()),
        new Claim(ClaimTypes.Name, "وكيل"),
        new Claim(ClaimTypes.MobilePhone, "07711111111"),
        new Claim("agent_code", "AG-1"),
        new Claim("company_id", companyId.ToString()),
        new Claim("role", "Agent"),
        new Claim("user_type", "agent"),
    });

    /// <summary>CitizenAuthController token claims.</summary>
    private static ClaimsPrincipal CitizenToken(Guid citizenId, Guid companyId) => RealToken(new[]
    {
        new Claim(ClaimTypes.NameIdentifier, citizenId.ToString()),
        new Claim(ClaimTypes.MobilePhone, "07722222222"),
        new Claim(ClaimTypes.Name, "مواطن"),
        new Claim("type", "citizen"),
        new Claim("companyId", companyId.ToString()),
    });

    /// <summary>UnifiedAuthController employee token claims.</summary>
    private static ClaimsPrincipal EmployeeToken(Guid userId, UserRole role, Guid companyId) => RealToken(new[]
    {
        new Claim(ClaimTypes.NameIdentifier, userId.ToString()),
        new Claim(ClaimTypes.Name, "موظف"),
        new Claim(ClaimTypes.MobilePhone, "07733333333"),
        new Claim(ClaimTypes.Role, role.ToString()),
        new Claim("role_id", ((int)role).ToString()),
        new Claim("company_id", companyId.ToString()),
    });

    /// <summary>Evaluates the "CompanyEmployee" policy exactly as registered in Program.cs.</summary>
    private static async Task<bool> PassesCompanyEmployeePolicy(ClaimsPrincipal principal)
    {
        var services = new ServiceCollection().AddLogging().AddAuthorization(o =>
            o.AddPolicy("CompanyEmployee", p =>
                p.RequireRole("SuperAdmin", "CompanyAdmin", "Manager", "TechnicalLeader", "Technician", "Employee", "Viewer")));
        var sp = services.BuildServiceProvider();
        var result = await sp.GetRequiredService<IAuthorizationService>().AuthorizeAsync(principal, "CompanyEmployee");
        return result.Succeeded;
    }

    private async Task<IActionResult?> RunEmployeeGate(ClaimsPrincipal principal)
    {
        await using var db = _fx.CreateContext(PostgresFixture.SystemTenant);
        var services = new ServiceCollection().AddSingleton<IUnitOfWork>(new UnitOfWork(db)).BuildServiceProvider();
        var http = new DefaultHttpContext { User = principal, RequestServices = services };
        var ctx = new AuthorizationFilterContext(
            new ActionContext(http, new RouteData(), new ActionDescriptor { EndpointMetadata = new List<object>() }),
            new List<IFilterMetadata>());
        await new RequireEmployeeUserAttribute().OnAuthorizationAsync(ctx);
        return ctx.Result;
    }

    [Fact]
    public void Controllers_Have_ClassLevel_CompanyEmployee_And_DbGate_NoBareActionAuthorize()
    {
        foreach (var type in GatedControllers)
        {
            Assert.Contains(type.GetCustomAttributes<AuthorizeAttribute>(), a => a.Policy == "CompanyEmployee");
            Assert.NotNull(type.GetCustomAttribute<RequireEmployeeUserAttribute>());
            foreach (var m in type.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly))
            {
                Assert.DoesNotContain(m.GetCustomAttributes<AuthorizeAttribute>(), a => a.Policy is null && a.Roles is null);
                if (m.GetCustomAttributes<AllowAnonymousAttribute>().Any())
                    Assert.Equal(nameof(ServiceRequestsController.GetServices), m.Name); // public catalogue only
            }
        }
    }

    [Fact]
    public async Task Agent_And_Citizen_Jwts_Fail_CompanyEmployee_Policy_Employee_Passes()
    {
        // Without the policy these tokens WOULD be scoped: CurrentTenant reads both company claims.
        var agent = AgentToken(Guid.NewGuid(), CompanyA);
        var citizen = CitizenToken(Guid.NewGuid(), CompanyA);
        Assert.Equal(CompanyA, new Sadara.API.Services.CurrentTenant(
            new HttpContextAccessor { HttpContext = new DefaultHttpContext { User = agent } },
            new ConfigurationBuilder().Build()).CompanyId);
        Assert.Equal(CompanyA, new Sadara.API.Services.CurrentTenant(
            new HttpContextAccessor { HttpContext = new DefaultHttpContext { User = citizen } },
            new ConfigurationBuilder().Build()).CompanyId);

        Assert.False(await PassesCompanyEmployeePolicy(agent));
        Assert.False(await PassesCompanyEmployeePolicy(citizen));
        Assert.True(await PassesCompanyEmployeePolicy(EmployeeToken(Guid.NewGuid(), UserRole.Technician, CompanyA)));
    }

    [SkippableFact]
    public async Task EmployeeGate_Rejects_Agent_Citizen_CitizenRow_Inactive_And_Accepts_Employee_SuperAdmin()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var employee = SeedUser(_fx, CompanyA, UserRole.Technician, "علي");
        var citizenRow = SeedUser(_fx, CompanyA, UserRole.Citizen, "مواطن بصف مستخدم");
        var inactive = SeedUser(_fx, CompanyA, UserRole.Employee, "موظف معطّل");
        using (var ctx = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            ctx.Set<User>().Single(u => u.Id == inactive).IsActive = false;
            ctx.SaveChanges();
        }

        static void AssertDenied(IActionResult? r)
        {
            var o = Assert.IsType<ObjectResult>(r);
            Assert.Equal(403, o.StatusCode);
            Assert.False(JsonSerializer.SerializeToElement(o.Value).GetProperty("success").GetBoolean());
        }

        AssertDenied(await RunEmployeeGate(AgentToken(Guid.NewGuid(), CompanyA)));
        AssertDenied(await RunEmployeeGate(CitizenToken(Guid.NewGuid(), CompanyA)));
        // A forged role claim does not help: the Users row decides.
        AssertDenied(await RunEmployeeGate(EmployeeToken(citizenRow, UserRole.Employee, CompanyA)));
        AssertDenied(await RunEmployeeGate(EmployeeToken(inactive, UserRole.Employee, CompanyA)));

        Assert.Null(await RunEmployeeGate(EmployeeToken(employee, UserRole.Technician, CompanyA)));
        Assert.Null(await RunEmployeeGate(RealToken(new[]
        {
            new Claim(ClaimTypes.NameIdentifier, Guid.NewGuid().ToString()),
            new Claim(ClaimTypes.Role, "SuperAdmin"),
        })));
    }

    // ══════════════════════════════════════════════════════════════════════
    // S3 — /summary uses the list scope for technicians
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task Technician_TaskAssignedByIdOnly_AppearsInListAndSummary()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var ali = SeedUser(_fx, CompanyA, UserRole.Technician, "علي");
        var hassan = SeedUser(_fx, CompanyA, UserRole.Technician, "حسن");

        var byIdOnly = SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA, TechnicianId = ali });
        var spacedCreator = SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA });
        using (var ctx = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            ctx.Set<ServiceRequest>().Single(r => r.Id == spacedCreator).Details =
                "{\"technician\": \"حسن\", \"createdById\": \"" + ali + "\"}";
            ctx.SaveChanges();
        }
        // Not his: stale AssignedToId and another technician's task.
        SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA, TechnicianId = hassan, AssignedToId = ali, Details = new() { ["technician"] = "حسن" } });
        SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA, TechnicianNameColumn = "حسن", Details = new() { ["technician"] = "حسن" } });

        await using var db = _fx.CreateContext(TenantOf(CompanyA));
        var c = ServiceRequests(db, TenantOf(CompanyA), ali, "Technician");

        var list = Json(await c.GetAll(pageSize: 100));
        var ids = list.GetProperty("data").EnumerateArray().Select(e => e.GetProperty("Id").GetGuid()).ToHashSet();
        Assert.Equal(new HashSet<Guid> { byIdOnly, spacedCreator }, ids);

        // Summary agrees with the list, and the client assignee cannot change it.
        Assert.Equal(2, SummaryTestHarness.Unwrap(await c.GetSummary()).Total);
        Assert.Equal(2, SummaryTestHarness.Unwrap(await c.GetSummary(assignee: "حسن")).Total);
    }

    // ══════════════════════════════════════════════════════════════════════
    // S5 — fees and reassignment
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task CompletionFee_TrustsSameCompanyTechnicianId_WhenNameDiffers()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var admin = SeedUser(_fx, CompanyA, UserRole.CompanyAdmin, "مدير شركة أ");
        var ali = SeedUser(_fx, CompanyA, UserRole.Technician, "علي محمد");
        var task = SeedTask(_fx, svc, op, new TaskSpec
        {
            CompanyId = CompanyA,
            Status = ServiceRequestStatus.InProgress,
            TechnicianId = ali,
            // Details name is an old/short spelling that does not equal the user's FullName.
            Details = new() { ["technician"] = "علي", ["taskType"] = "صيانة", ["deliveryFee"] = 5000 },
        });

        await using (var db = _fx.CreateContext(TenantOf(CompanyA)))
            Assert.Equal(200, StatusOf(await ServiceRequests(db, TenantOf(CompanyA), admin, "CompanyAdmin")
                .UpdateStatus(task, new UpdateStatusDto { Status = "Completed" })));

        using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        var tx = Assert.Single(check.Set<TechnicianTransaction>().Where(t => t.ServiceRequestId == task).ToList());
        Assert.Equal(ali, tx.TechnicianId);
        Assert.Equal(5000m, tx.Amount);
    }

    [SkippableFact]
    public async Task UnresolvedRename_DetachesOldTechnician_In_UpdateTask_And_AssignTask()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var admin = SeedUser(_fx, CompanyA, UserRole.CompanyAdmin, "مدير شركة أ");
        var ali = SeedUser(_fx, CompanyA, UserRole.Technician, "علي");
        SeedUser(_fx, CompanyB, UserRole.Technician, "سالم"); // new name exists only in company B
        SeedUser(_fx, CompanyA, UserRole.Technician, "كرار");
        SeedUser(_fx, CompanyA, UserRole.Technician, "كرار"); // ambiguous in company A

        var t1 = SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA, TechnicianId = ali, AssignedToId = ali, TechnicianNameColumn = "علي", Details = new() { ["technician"] = "علي" } });
        var t2 = SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA, TechnicianId = ali, AssignedToId = ali, TechnicianNameColumn = "علي", Details = new() { ["technician"] = "علي" } });
        var t3 = SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA, TechnicianId = ali, AssignedToId = ali, TechnicianNameColumn = "علي", Details = new() { ["technician"] = "علي" } });

        await using (var db = _fx.CreateContext(TenantOf(CompanyA)))
            Assert.Equal(200, StatusOf(await ServiceRequests(db, TenantOf(CompanyA), admin, "CompanyAdmin")
                .UpdateTask(t1, new UpdateTaskDto { Technician = "سالم" })));
        await using (var db = _fx.CreateContext(TenantOf(CompanyA)))
            Assert.Equal(200, StatusOf(await ServiceRequests(db, TenantOf(CompanyA), admin, "CompanyAdmin")
                .AssignTask(t2, new AssignTaskDto { Technician = "كرار" })));
        // Same person re-sent (unchanged name) ⇒ kept.
        await using (var db = _fx.CreateContext(TenantOf(CompanyA)))
            Assert.Equal(200, StatusOf(await ServiceRequests(db, TenantOf(CompanyA), admin, "CompanyAdmin")
                .UpdateTask(t3, new UpdateTaskDto { Technician = "علي", Notes = "x" })));

        using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        var r1 = check.Set<ServiceRequest>().Single(r => r.Id == t1);
        var r2 = check.Set<ServiceRequest>().Single(r => r.Id == t2);
        var r3 = check.Set<ServiceRequest>().Single(r => r.Id == t3);
        Assert.Null(r1.TechnicianId);
        Assert.Null(r1.AssignedToId);
        Assert.Equal("سالم", r1.TechnicianName);
        Assert.Null(r2.TechnicianId);
        Assert.Null(r2.AssignedToId);
        Assert.Equal(ali, r3.TechnicianId);
        Assert.Equal(ali, r3.AssignedToId);
    }

    // ══════════════════════════════════════════════════════════════════════
    // S6 — all-dues keeps unlinked accounts
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task AllDues_ListsUnlinkedAccounts_SoTotalsStayComplete()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var admin = SeedUser(_fx, CompanyA, UserRole.CompanyAdmin, "مدير شركة أ");
        var ali = SeedUser(_fx, CompanyA, UserRole.Technician, "علي");
        SeedUser(_fx, CompanyA, UserRole.Technician, "كرار");
        SeedUser(_fx, CompanyA, UserRole.Technician, "كرار");

        await using (var ctx = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            var uow = new UnitOfWork(ctx);
            await ServiceRequestAccountingHelper.EnsureFixedParentAccount(uow, "1140", "ذمم الفنيين", AccountType.Assets, CompanyA);
            var revenue = await ServiceRequestAccountingHelper.EnsureFixedParentAccount(uow, "4110", "ايراد صيانة", AccountType.Revenue, CompanyA);
            var linked = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(uow, "1140", ali, "علي", CompanyA);
            // Legacy accounts: no Description (ambiguous name / unknown person).
            var dupName = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(uow, "1140", Guid.NewGuid(), "كرار", CompanyA);
            var orphan = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(uow, "1140", Guid.NewGuid(), "فني محذوف", CompanyA);
            dupName.Description = null;
            orphan.Description = null;
            await uow.SaveChangesAsync();

            foreach (var (acct, amount) in new[] { (linked, 100m), (dupName, 30m), (orphan, 50m) })
                await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(uow, CompanyA, admin, "أجور",
                    JournalReferenceType.Manual, null,
                    new() { (acct.Id, amount, 0m, "مدين"), (revenue.Id, 0m, amount, "دائن") });
        }

        await using var db = _fx.CreateContext(TenantOf(CompanyA));
        var res = Json(await TechTx(db, TenantOf(CompanyA), admin, "CompanyAdmin").GetAllTechnicianDues(null, null));
        var rows = res.GetProperty("technicians").EnumerateArray().ToList();

        Assert.Equal(3, rows.Count);
        Assert.Single(rows, r => r.GetProperty("linked").GetBoolean() && r.GetProperty("id").GetGuid() == ali);
        var unlinked = rows.Where(r => !r.GetProperty("linked").GetBoolean()).ToList();
        Assert.Equal(2, unlinked.Count);
        Assert.All(unlinked, r =>
        {
            Assert.Equal(JsonValueKind.Null, r.GetProperty("id").ValueKind);
            Assert.Equal("غير مرتبط", r.GetProperty("linkStatus").GetString());
        });
        Assert.Equal(180m, res.GetProperty("summary").GetProperty("totalCharges").GetDecimal());
        Assert.Equal(1, res.GetProperty("summary").GetProperty("technicianCount").GetInt32());
        Assert.Equal(2, res.GetProperty("summary").GetProperty("unlinkedAccountCount").GetInt32());
    }

    // ══════════════════════════════════════════════════════════════════════
    // S12 — ActivatedBy resolution inside the caller company
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task SubscriptionLog_ActivatedBy_ResolvesOnlyInsideCallerCompany()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var caller = SeedUser(_fx, CompanyA, UserRole.Employee, "موظف أ");
        var opA = SeedUser(_fx, CompanyA, UserRole.Employee, "مشغل أ");
        var opB = SeedUser(_fx, CompanyB, UserRole.Employee, "مشغل ب");
        using (var ctx = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            ctx.Set<User>().Single(u => u.Id == opA).Username = "op-a";
            ctx.Set<User>().Single(u => u.Id == opB).Username = "op-b";
            ctx.SaveChanges();
        }

        await using (var db = _fx.CreateContext(TenantOf(CompanyA)))
        {
            var c = SubLogs(db, TenantOf(CompanyA), caller, "Employee");
            Assert.Equal(201, StatusOf(await c.Create(new CreateSubscriptionLogRequest { ActivatedBy = "op-a", SessionId = "s-1" })));
            Assert.Equal(201, StatusOf(await c.Create(new CreateSubscriptionLogRequest { ActivatedBy = "op-b", SessionId = "s-2" })));
        }

        using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        Assert.Equal("مشغل أ", check.Set<SubscriptionLog>().Single(l => l.SessionId == "s-1").ActivatedBy);
        Assert.Equal("op-b", check.Set<SubscriptionLog>().Single(l => l.SessionId == "s-2").ActivatedBy); // B's name never leaks
    }
}
