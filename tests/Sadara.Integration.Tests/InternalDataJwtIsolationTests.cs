using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Sadara.API.Controllers;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Data;
using Sadara.Integration.Tests.Support;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// المرحلة 0-أ: مسار JWT في <see cref="InternalDataController"/> (/api/internal/*).
/// يثبت أن:
///   - الشركة والمستخدم يُؤخذان من التوكن/قاعدة البيانات لا من الجسم/الاستعلام.
///   - الفني/الوكيل/السجل المُشار إليه من شركة أخرى يُرفض.
///   - نقاط SuperAdmin مغلقة أمام مستخدم شركة، وطلب بلا اعتماد = 401.
///   - مسار X-Api-Key القديم يبقى بسلوكه دون تغيير (للنسخ المثبّتة) — بمفتاح اختبار عشوائي لا بالمفتاح الحقيقي.
/// Postgres حقيقي عبر Testcontainers (يُتخطّى بوضوح إن لم يتوفّر Docker).
/// </summary>
[Collection("Postgres")]
public sealed class InternalDataJwtIsolationTests
{
    private readonly PostgresFixture _fx;

    // مفتاح اختبار عشوائي لكل تشغيل — ليس مفتاح الإنتاج إطلاقاً.
    private static readonly string TestApiKey = "test-" + Guid.NewGuid().ToString("N");

    public InternalDataJwtIsolationTests(PostgresFixture fx) => _fx = fx;

    // ═══════ بنية تحتية ═══════

    private sealed record Seed(
        Guid CompanyA, Guid CompanyB,
        Guid UserA, Guid UserA2, Guid UserB,
        Guid TechA, Guid TechB,
        Guid AgentA, Guid AgentB,
        long LogA, long LogB);

    private Seed SeedData()
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        var suffix = Guid.NewGuid().ToString("N")[..8];

        var companyA = new Company { Id = Guid.NewGuid(), Name = "شركة أ " + suffix, Code = "IA-" + suffix };
        var companyB = new Company { Id = Guid.NewGuid(), Name = "شركة ب " + suffix, Code = "IB-" + suffix };
        ctx.Set<Company>().AddRange(companyA, companyB);

        User NewUser(Guid companyId, UserRole role, string tag) => new()
        {
            Id = Guid.NewGuid(),
            Username = $"{tag}-{suffix}",
            FullName = $"{tag} {suffix}",
            PhoneNumber = $"07{Random.Shared.Next(100000000, 999999999)}",
            CompanyId = companyId,
            Role = role,
            IsActive = true,
        };

        var userA = NewUser(companyA.Id, UserRole.Employee, "opA");
        // S9: مشغّل التفعيل يملك منحاً صريحاً لإضافة الاشتراكات (النظام الثاني) كما في التطبيق
        userA.SecondSystemPermissionsV2 = "{\"subscriptions\":{\"view\":true,\"add\":true}}";
        var userA2 = NewUser(companyA.Id, UserRole.Employee, "opA2");
        var userB = NewUser(companyB.Id, UserRole.Employee, "opB");
        var techA = NewUser(companyA.Id, UserRole.Technician, "techA");
        var techB = NewUser(companyB.Id, UserRole.Technician, "techB");
        ctx.Set<User>().AddRange(userA, userA2, userB, techA, techB);

        Agent NewAgent(Guid companyId, string tag) => new()
        {
            Id = Guid.NewGuid(),
            AgentCode = $"{tag}-{suffix}",
            Name = $"{tag} {suffix}",
            PhoneNumber = $"07{Random.Shared.Next(100000000, 999999999)}",
            PasswordHash = "x",
            CompanyId = companyId,
        };
        var agentA = NewAgent(companyA.Id, "agA");
        var agentB = NewAgent(companyB.Id, "agB");
        ctx.Set<Agent>().AddRange(agentA, agentB);

        var logA = new SubscriptionLog
        {
            CustomerName = "زبون أ", CompanyId = companyA.Id, UserId = userA.Id,
            ActivationDate = DateTime.UtcNow, PlanPrice = 0,
        };
        var logB = new SubscriptionLog
        {
            CustomerName = "زبون ب", CompanyId = companyB.Id, UserId = userB.Id,
            ActivationDate = DateTime.UtcNow, PlanPrice = 0,
        };
        ctx.Set<SubscriptionLog>().AddRange(logA, logB);
        ctx.SaveChanges();

        return new Seed(companyA.Id, companyB.Id, userA.Id, userA2.Id, userB.Id,
            techA.Id, techB.Id, agentA.Id, agentB.Id, logA.Id, logB.Id);
    }

    /// <summary>يبني الكونترولر الحقيقي. jwtUserId ⇒ مستخدم مُصادَق بتوكن؛ withApiKey ⇒ ترويسة المفتاح القديم.</summary>
    private (InternalDataController Controller, SadaraDbContext Db) Build(
        Guid? jwtUserId = null, Guid? tokenCompanyId = null, string role = "Employee", bool withApiKey = false)
    {
        var db = _fx.CreateContext(PostgresFixture.SystemTenant);
        var uow = new Sadara.Infrastructure.Repositories.UnitOfWork(db);
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { ["Security:InternalApiKey"] = TestApiKey })
            .Build();

        var controller = new InternalDataController(uow, config, db, NullLogger<InternalDataController>.Instance);

        ClaimsPrincipal principal;
        if (jwtUserId.HasValue)
        {
            var claims = new List<Claim>
            {
                new(ClaimTypes.NameIdentifier, jwtUserId.Value.ToString()),
                new(ClaimTypes.Role, role),
            };
            if (tokenCompanyId.HasValue) claims.Add(new Claim("company_id", tokenCompanyId.Value.ToString()));
            principal = new ClaimsPrincipal(new ClaimsIdentity(claims, authenticationType: "Bearer"));
        }
        else
        {
            principal = new ClaimsPrincipal(new ClaimsIdentity()); // غير مُصادَق
        }

        var http = new DefaultHttpContext { User = principal };
        if (withApiKey) http.Request.Headers["X-Api-Key"] = TestApiKey;
        controller.ControllerContext = new ControllerContext { HttpContext = http };
        return (controller, db);
    }

    private static JsonElement Body(object o) =>
        JsonDocument.Parse(JsonSerializer.Serialize(o)).RootElement.Clone();

    private static int StatusOf(IActionResult r) => r switch
    {
        ObjectResult o => o.StatusCode ?? 200,
        StatusCodeResult s => s.StatusCode,
        _ => throw new Xunit.Sdk.XunitException("نتيجة غير متوقعة: " + r.GetType().Name),
    };

    private static JsonElement Json(IActionResult r) =>
        JsonDocument.Parse(JsonSerializer.Serialize(((ObjectResult)r).Value)).RootElement.Clone();

    private SubscriptionLog? ReadLog(long id)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        return ctx.Set<SubscriptionLog>().AsNoTracking().IgnoreQueryFilters().FirstOrDefault(l => l.Id == id);
    }

    // ═══════ POST subscriptionlogs ═══════

    [SkippableFact]
    public async Task Jwt_CreateLog_IgnoresBodyCompanyAndUser()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        var (c, db) = Build(jwtUserId: s.UserA, tokenCompanyId: s.CompanyA);
        await using var _ = db;

        var r = await c.CreateSubscriptionLog(Body(new
        {
            customerName = "مزوّر",
            companyId = s.CompanyB.ToString(),   // محاولة كتابة في شركة أخرى
            userId = s.UserB.ToString(),         // محاولة انتحال مستخدم آخر
            planPrice = 0,
        }));

        Assert.Equal(200, StatusOf(r));
        var id = Json(r).GetProperty("data").GetProperty("Id").GetInt64();
        var saved = ReadLog(id)!;
        Assert.Equal(s.CompanyA, saved.CompanyId);
        Assert.Equal(s.UserA, saved.UserId);
    }

    [SkippableFact]
    public async Task Jwt_CreateLog_RejectsTechnicianFromOtherCompany()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        var (c, db) = Build(jwtUserId: s.UserA, tokenCompanyId: s.CompanyA);
        await using var _ = db;
        var marker = "cross-tech-" + Guid.NewGuid().ToString("N");

        var r = await c.CreateSubscriptionLog(Body(new
        {
            customerName = marker,
            linkedTechnicianId = s.TechB.ToString(),
            collectionType = "technician",
            planPrice = 1000,
        }));

        Assert.Equal(400, StatusOf(r));
        await using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        Assert.False(await check.Set<SubscriptionLog>().AnyAsync(l => l.CustomerName == marker));
    }

    [SkippableFact]
    public async Task Jwt_CreateLog_RejectsAgentFromOtherCompany()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        var (c, db) = Build(jwtUserId: s.UserA, tokenCompanyId: s.CompanyA);
        await using var _ = db;

        var r = await c.CreateSubscriptionLog(Body(new
        {
            customerName = "x",
            linkedAgentId = s.AgentB.ToString(),
            collectionType = "agent",
            planPrice = 1000,
        }));

        Assert.Equal(400, StatusOf(r));
    }

    [SkippableFact]
    public async Task Jwt_CreateLog_AcceptsTechnicianFromSameCompany()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        var (c, db) = Build(jwtUserId: s.UserA, tokenCompanyId: s.CompanyA);
        await using var _ = db;

        var r = await c.CreateSubscriptionLog(Body(new
        {
            customerName = "x",
            linkedTechnicianId = s.TechA.ToString(),
            planPrice = 0,
        }));

        Assert.Equal(200, StatusOf(r));
        var saved = ReadLog(Json(r).GetProperty("data").GetProperty("Id").GetInt64())!;
        Assert.Equal(s.TechA, saved.LinkedTechnicianId);
        Assert.Equal(s.CompanyA, saved.CompanyId);
    }

    // ═══════ PUT / DELETE subscriptionlogs/{id} ═══════

    [SkippableFact]
    public async Task Jwt_UpdateLog_OfOtherCompany_Forbidden()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        var (c, db) = Build(jwtUserId: s.UserA, tokenCompanyId: s.CompanyA);
        await using var _ = db;

        var r = await c.UpdateSubscriptionLog(s.LogB, Body(new { subscriptionNotes = "عبث" }));

        Assert.Equal(403, StatusOf(r));
        Assert.Contains("شركة أخرى", Json(r).GetProperty("message").GetString());
        Assert.Null(ReadLog(s.LogB)!.SubscriptionNotes);
    }

    [SkippableFact]
    public async Task Jwt_UpdateLog_ReassignToOtherCompanyTechnician_Rejected()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        var (c, db) = Build(jwtUserId: s.UserA, tokenCompanyId: s.CompanyA);
        await using var _ = db;

        var r = await c.UpdateSubscriptionLog(s.LogA, Body(new { LinkedTechnicianId = s.TechB.ToString() }));

        Assert.Equal(400, StatusOf(r));
        Assert.Null(ReadLog(s.LogA)!.LinkedTechnicianId);
    }

    [SkippableFact]
    public async Task Jwt_DeleteLog_OfOtherCompany_Forbidden()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        var (c, db) = Build(jwtUserId: s.UserA, tokenCompanyId: s.CompanyA);
        await using var _ = db;

        var r = await c.DeleteSubscriptionLog(s.LogB);

        Assert.Equal(403, StatusOf(r));
        Assert.Contains("شركة أخرى", Json(r).GetProperty("message").GetString());
        Assert.False(ReadLog(s.LogB)!.IsDeleted);
    }

    // ═══════ GET subscriptionlogs ═══════

    [SkippableFact]
    public async Task Jwt_GetLogs_IgnoresQueryCompany_ReturnsOnlyOwnCompany()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        var (c, db) = Build(jwtUserId: s.UserA, tokenCompanyId: s.CompanyA);
        await using var _ = db;

        var r = await c.GetSubscriptionLogs(s.CompanyB.ToString(), null, null, null, 15000);

        Assert.Equal(200, StatusOf(r));
        var companies = Json(r).EnumerateArray()
            .Select(e => e.GetProperty("CompanyId").GetString())
            .Distinct().ToList();
        Assert.Single(companies);
        Assert.Equal(s.CompanyA.ToString(), companies[0]);
    }

    // ═══════ هوية/صلاحيات ═══════

    [SkippableFact]
    public async Task NoCredentials_Unauthorized()
    {
        _fx.SkipIfUnavailable();
        var (c, db) = Build();
        await using var _ = db;

        Assert.Equal(401, StatusOf(await c.GetSubscriptionLogs(null, null, null, null, 10)));
    }

    [SkippableFact]
    public async Task Jwt_StaleTokenCompanyMismatch_Forbidden()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        // توكن يدّعي شركة ب بينما المستخدم في قاعدة البيانات من شركة أ
        var (c, db) = Build(jwtUserId: s.UserA, tokenCompanyId: s.CompanyB);
        await using var _ = db;

        Assert.Equal(403, StatusOf(await c.GetSubscriptionLogs(null, null, null, null, 10)));
    }

    [SkippableFact]
    public async Task Jwt_CompanyUser_CannotCallSuperAdminEndpoints()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        var (c, db) = Build(jwtUserId: s.UserA, tokenCompanyId: s.CompanyA);
        await using var _ = db;

        Assert.Equal(403, StatusOf(await c.GetCompanies()));
        Assert.Equal(403, StatusOf(await c.DeleteCompany(s.CompanyB)));
    }

    [SkippableFact]
    public async Task Jwt_CannotManageEmployeesOfOtherCompany()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        var (c, db) = Build(jwtUserId: s.UserA, tokenCompanyId: s.CompanyA);
        await using var _ = db;

        Assert.Equal(403, StatusOf(await c.GetCompanyEmployees(s.CompanyB)));
        Assert.Equal(403, StatusOf(await c.UpdateEmployeePassword(s.CompanyB, s.UserB,
            new InternalUpdatePasswordRequest { NewPassword = "hacked123" })));
    }

    [SkippableFact]
    public async Task Jwt_PlainEmployee_CannotManageColleagues()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        var (c, db) = Build(jwtUserId: s.UserA, tokenCompanyId: s.CompanyA);
        await using var _ = db;

        // موظف عادي بلا صلاحية إدارة المستخدمين (V2 فارغة لا تمنحها — fail-closed هنا)
        Assert.Equal(403, StatusOf(await c.UpdateEmployeePassword(s.CompanyA, s.UserA2,
            new InternalUpdatePasswordRequest { NewPassword = "hacked123" })));
        Assert.Equal(403, StatusOf(await c.GetCompanyEmployeeById(s.CompanyA, s.UserA2)));
        // قراءة سجلّه هو مسموحة
        Assert.Equal(200, StatusOf(await c.GetCompanyEmployeeById(s.CompanyA, s.UserA)));
    }

    // ═══════ المسار القديم دون تغيير ═══════

    [SkippableFact]
    public async Task LegacyApiKey_BehaviourUnchanged_BodyCompanyHonoured()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        var (c, db) = Build(withApiKey: true);
        await using var _ = db;

        var r = await c.CreateSubscriptionLog(Body(new
        {
            customerName = "legacy",
            companyId = s.CompanyB.ToString(),
            userId = s.UserB.ToString(),
            planPrice = 0,
        }));

        Assert.Equal(200, StatusOf(r));
        var saved = ReadLog(Json(r).GetProperty("data").GetProperty("Id").GetInt64())!;
        Assert.Equal(s.CompanyB, saved.CompanyId);
        Assert.Equal(s.UserB, saved.UserId);
    }
}
