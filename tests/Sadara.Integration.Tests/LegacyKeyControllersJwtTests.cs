using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.Connections.Features;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Sadara.API.Controllers;
using Sadara.API.Hubs;
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
/// المرحلة 0 / A2: المتحكّمات السبعة التي كانت تقبل المفتاح الداخلي فقط + LocationHub صارت تقبل JWT موظف
/// الشركة (الشركة من التوكن) مع إبقاء المفتاح القديم (خادم↔خادم) — بمفتاح اختبار عشوائي لا بالمفتاح الحقيقي.
/// لكل متحكّم: عزل مسار JWT بين شركتين، رفض توكن المواطن/غير الموظف، وبقاء مسار المفتاح القديم.
/// Postgres حقيقي عبر Testcontainers (يُتخطّى بوضوح إن لم يتوفّر Docker).
/// </summary>
[Collection("Postgres")]
public sealed class LegacyKeyControllersJwtTests
{
    private readonly PostgresFixture _fx;

    // مفتاح اختبار عشوائي لكل تشغيل — ليس مفتاح الإنتاج إطلاقاً.
    private static readonly string TestApiKey = "test-" + Guid.NewGuid().ToString("N");

    public LegacyKeyControllersJwtTests(PostgresFixture fx) => _fx = fx;

    // ═══════════════════════════ بنية تحتية ═══════════════════════════

    private const string NoTrackingPerms = "{\"tasks\":{\"view\":true}}";
    private const string TrackingPerms = "{\"tracking\":{\"view\":true,\"delete\":false}}";

    private sealed record Seed(
        string Suffix,
        Guid CompanyA, Guid CompanyB,
        Guid ManagerA, Guid EmployeeA, Guid TrackerA, Guid EmployeeA2,
        Guid ManagerB, Guid EmployeeB, Guid Citizen,
        string EmployeeAName, string EmployeeA2Name, string EmployeeBName);

    private Seed SeedData()
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        var suffix = Guid.NewGuid().ToString("N")[..8];

        var companyA = new Company { Id = Guid.NewGuid(), Name = "شركة أ " + suffix, Code = "LA-" + suffix };
        var companyB = new Company { Id = Guid.NewGuid(), Name = "شركة ب " + suffix, Code = "LB-" + suffix };
        ctx.Set<Company>().AddRange(companyA, companyB);

        User NewUser(Guid? companyId, UserRole role, string tag, string? perms) => new()
        {
            Id = Guid.NewGuid(),
            Username = $"{tag}-{suffix}",
            FullName = $"{tag} {suffix}",
            PhoneNumber = $"07{Random.Shared.Next(100000000, 999999999)}",
            CompanyId = companyId,
            Role = role,
            IsActive = true,
            FirstSystemPermissionsV2 = perms,
        };

        var managerA = NewUser(companyA.Id, UserRole.Manager, "mgrA", NoTrackingPerms);
        var employeeA = NewUser(companyA.Id, UserRole.Employee, "empA", NoTrackingPerms);
        var trackerA = NewUser(companyA.Id, UserRole.TechnicalLeader, "trkA", TrackingPerms);
        var employeeA2 = NewUser(companyA.Id, UserRole.Technician, "empA2", NoTrackingPerms);
        var managerB = NewUser(companyB.Id, UserRole.CompanyAdmin, "mgrB", NoTrackingPerms);
        var employeeB = NewUser(companyB.Id, UserRole.Employee, "empB", NoTrackingPerms);
        var citizen = NewUser(null, UserRole.Citizen, "cit", null);
        ctx.Set<User>().AddRange(managerA, employeeA, trackerA, employeeA2, managerB, employeeB, citizen);
        ctx.SaveChanges();

        return new Seed(suffix, companyA.Id, companyB.Id,
            managerA.Id, employeeA.Id, trackerA.Id, employeeA2.Id, managerB.Id, employeeB.Id, citizen.Id,
            employeeA.FullName, employeeA2.FullName, employeeB.FullName);
    }

    private static IConfiguration Config(Guid? defaultCompany = null) =>
        new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Security:InternalApiKey"] = TestApiKey,
                ["Tenancy:DefaultCompanyId"] = defaultCompany?.ToString() ?? "",
            })
            .Build();

    /// <summary>سياق HTTP: jwtUserId ⇒ توكن مُصادَق؛ withApiKey ⇒ ترويسة المفتاح القديم؛ وإلا بلا اعتماد.</summary>
    private static DefaultHttpContext Http(Guid? jwtUserId, Guid? tokenCompanyId, bool withApiKey, string role = "Employee")
    {
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
            principal = new ClaimsPrincipal(new ClaimsIdentity());
        }

        var http = new DefaultHttpContext { User = principal };
        if (withApiKey) http.Request.Headers["X-Api-Key"] = TestApiKey;
        return http;
    }

    private sealed class Ctx : IAsyncDisposable
    {
        public required SadaraDbContext Db { get; init; }
        public required UnitOfWork Uow { get; init; }
        public required DefaultHttpContext Http { get; init; }
        public ValueTask DisposeAsync() => Db.DisposeAsync();
    }

    private Ctx NewCtx(Guid? jwtUserId = null, Guid? tokenCompanyId = null, bool withApiKey = false)
    {
        var db = _fx.CreateContext(PostgresFixture.SystemTenant);
        return new Ctx { Db = db, Uow = new UnitOfWork(db), Http = Http(jwtUserId, tokenCompanyId, withApiKey) };
    }

    private static T Attach<T>(T controller, HttpContext http) where T : ControllerBase
    {
        controller.ControllerContext = new ControllerContext { HttpContext = http };
        return controller;
    }

    private static int StatusOf(IActionResult r) => r switch
    {
        ObjectResult o => o.StatusCode ?? 200,
        StatusCodeResult s => s.StatusCode,
        _ => throw new Xunit.Sdk.XunitException("نتيجة غير متوقعة: " + r.GetType().Name),
    };

    private static JsonElement Json(IActionResult r) =>
        JsonDocument.Parse(JsonSerializer.Serialize(((ObjectResult)r).Value)).RootElement.Clone();

    private static List<string> Strings(JsonElement arr, string prop) =>
        arr.EnumerateArray()
            .Select(e => e.EnumerateObject()
                .Where(p => string.Equals(p.Name, prop, StringComparison.OrdinalIgnoreCase))
                .Select(p => p.Value.ValueKind == JsonValueKind.String ? p.Value.GetString() ?? "" : p.Value.ToString())
                .FirstOrDefault() ?? "")
            .ToList();

    // ═══════════════════════════ EmployeeLocation ═══════════════════════════

    private sealed class RecordingHubContext : IHubContext<LocationHub>
    {
        public List<(IReadOnlyList<string> Groups, string Method)> Sent { get; } = new();
        public IHubClients Clients => new RecordingClients(this);
        public IGroupManager Groups => throw new NotSupportedException();

        private sealed class RecordingClients(RecordingHubContext owner) : IHubClients
        {
            public IClientProxy All => throw new NotSupportedException();
            public IClientProxy AllExcept(IReadOnlyList<string> excludedConnectionIds) => throw new NotSupportedException();
            public IClientProxy Client(string connectionId) => throw new NotSupportedException();
            public IClientProxy Clients(IReadOnlyList<string> connectionIds) => throw new NotSupportedException();
            public IClientProxy Group(string groupName) => new Proxy(owner, new[] { groupName });
            public IClientProxy GroupExcept(string groupName, IReadOnlyList<string> excludedConnectionIds) => throw new NotSupportedException();
            public IClientProxy Groups(IReadOnlyList<string> groupNames) => new Proxy(owner, groupNames);
            public IClientProxy User(string userId) => throw new NotSupportedException();
            public IClientProxy Users(IReadOnlyList<string> userIds) => throw new NotSupportedException();
        }

        private sealed class Proxy(RecordingHubContext owner, IReadOnlyList<string> groups) : IClientProxy
        {
            public Task SendCoreAsync(string method, object?[] args, CancellationToken cancellationToken = default)
            {
                lock (owner.Sent) owner.Sent.Add((groups, method));
                return Task.CompletedTask;
            }
        }
    }

    private sealed class NoopFcm : IFcmNotificationService
    {
        public Task SendToUserAsync(Guid userId, string title, string body, Dictionary<string, string>? data = null) => Task.CompletedTask;
        public Task SendToUsersAsync(IEnumerable<Guid> userIds, string title, string body, Dictionary<string, string>? data = null) => Task.CompletedTask;
    }

    private EmployeeLocationController LocationController(Ctx c, RecordingHubContext? hub = null) =>
        Attach(new EmployeeLocationController(c.Uow, Config(), NullLogger<EmployeeLocationController>.Instance,
            hub ?? new RecordingHubContext(), new NoopFcm()), c.Http);

    private void SeedLocation(string label, Guid? companyId, double lat = 33.3)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<EmployeeLocation>().Add(new EmployeeLocation
        {
            UserId = label, CompanyId = companyId, Latitude = lat, Longitude = 44.4,
            IsActive = true, LastUpdate = DateTime.UtcNow,
        });
        ctx.SaveChanges();
    }

    [SkippableFact]
    public async Task Location_Jwt_Post_UsesOwnLabelAndStampsCompany_EvenIfBodyNamesAnotherEmployee()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        var hub = new RecordingHubContext();
        await using var c = NewCtx(s.EmployeeA, s.CompanyA);

        var r = await LocationController(c, hub).UpdateLocation(new EmployeeLocationController.LocationUpdateRequest
        {
            UserId = s.EmployeeA2Name, // محاولة انتحال زميل
            Latitude = 33.31, Longitude = 44.41,
        });

        Assert.Equal(200, StatusOf(r));
        await using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        var own = await check.Set<EmployeeLocation>().AsNoTracking().SingleAsync(e => e.UserId == s.EmployeeAName);
        Assert.Equal(s.CompanyA, own.CompanyId);
        Assert.False(await check.Set<EmployeeLocation>().AnyAsync(e => e.UserId == s.EmployeeA2Name));
        var log = await check.Set<EmployeeLocationLog>().AsNoTracking().FirstAsync(l => l.UserId == s.EmployeeAName);
        Assert.Equal(s.CompanyA, log.CompanyId);

        // البث: المشاهدون العامّون + مجموعة الشركة أ فقط
        var sent = Assert.Single(hub.Sent);
        Assert.Contains(LocationHub.CompanyGroup(s.CompanyA), sent.Groups);
        Assert.DoesNotContain(LocationHub.CompanyGroup(s.CompanyB), sent.Groups);
    }

    [SkippableFact]
    public async Task Location_Jwt_Active_IsCompanyScoped_IncludingUnstampedRowsOfOwnEmployees()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        SeedLocation(s.EmployeeAName, s.CompanyA);
        SeedLocation(s.EmployeeA2Name, null);   // صف قديم غير مختوم لموظف من أ
        SeedLocation(s.EmployeeBName, s.CompanyB);
        SeedLocation("مجهول " + s.Suffix, null); // صف قديم لا يطابق أي موظف من أ

        await using var c = NewCtx(s.ManagerA, s.CompanyA);
        var r = await LocationController(c).GetActiveLocations();

        Assert.Equal(200, StatusOf(r));
        var ids = Strings(Json(r).GetProperty("data"), "userId");
        Assert.Contains(s.EmployeeAName, ids);
        Assert.Contains(s.EmployeeA2Name, ids);
        Assert.DoesNotContain(s.EmployeeBName, ids);
        Assert.DoesNotContain("مجهول " + s.Suffix, ids);
    }

    [SkippableFact]
    public async Task Location_Jwt_Active_RequiresTrackingPermission_FailClosed()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();

        await using (var c = NewCtx(s.EmployeeA, s.CompanyA))
            Assert.Equal(403, StatusOf(await LocationController(c).GetActiveLocations()));

        await using (var c = NewCtx(s.TrackerA, s.CompanyA))
            Assert.Equal(200, StatusOf(await LocationController(c).GetActiveLocations()));
    }

    [SkippableFact]
    public async Task Location_Jwt_History_OfOtherCompanyEmployee_IsEmpty()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        await using (var seed = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            seed.Set<EmployeeLocationLog>().Add(new EmployeeLocationLog
            {
                UserId = s.EmployeeBName, CompanyId = s.CompanyB, Latitude = 1, Longitude = 1, RecordedAt = DateTime.UtcNow,
            });
            await seed.SaveChangesAsync();
        }

        await using var c = NewCtx(s.ManagerA, s.CompanyA);
        var r = await LocationController(c).GetHistory(s.EmployeeBName, 24, snap: false);
        Assert.Equal(200, StatusOf(r));
        Assert.Equal(0, Json(r).GetProperty("totalPoints").GetInt32());
    }

    [SkippableFact]
    public async Task Location_Jwt_Purge_EmployeeForbidden_ManagerDeletesOnlyOwnCompany()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        await using (var seed = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            var old = DateTime.UtcNow.AddDays(-60);
            seed.Set<EmployeeLocationLog>().AddRange(
                new EmployeeLocationLog { UserId = s.EmployeeAName, CompanyId = s.CompanyA, RecordedAt = old },
                new EmployeeLocationLog { UserId = s.EmployeeBName, CompanyId = s.CompanyB, RecordedAt = old });
            await seed.SaveChangesAsync();
        }

        await using (var c = NewCtx(s.EmployeeA, s.CompanyA))
        {
            c.Http.Request.Headers["X-Caller-Role"] = "super_admin"; // ترويسة مزوّرة لا أثر لها على JWT
            Assert.Equal(403, StatusOf(await LocationController(c).PurgeOldData(30)));
        }

        await using (var c = NewCtx(s.ManagerA, s.CompanyA))
            Assert.Equal(200, StatusOf(await LocationController(c).PurgeOldData(30)));

        await using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        Assert.False(await check.Set<EmployeeLocationLog>().AnyAsync(l => l.UserId == s.EmployeeAName));
        Assert.True(await check.Set<EmployeeLocationLog>().AnyAsync(l => l.UserId == s.EmployeeBName));
    }

    [SkippableFact]
    public async Task Location_CitizenAndUnknownTokens_Rejected_NoCredentials401()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();

        await using (var c = NewCtx(s.Citizen))
            Assert.Equal(403, StatusOf(await LocationController(c).GetActiveLocations()));
        await using (var c = NewCtx(Guid.NewGuid(), s.CompanyA)) // وكيل/حساب ليس في جدول الموظفين
            Assert.Equal(403, StatusOf(await LocationController(c).UpdateLocation(
                new EmployeeLocationController.LocationUpdateRequest { UserId = "x", Latitude = 1, Longitude = 1 })));
        await using (var c = NewCtx(s.EmployeeB, s.CompanyA)) // توكن قديم بشركة لا تطابق قاعدة البيانات
            Assert.Equal(403, StatusOf(await LocationController(c).GetActiveLocations()));
        await using (var c = NewCtx())
            Assert.Equal(401, StatusOf(await LocationController(c).GetActiveLocations()));
    }

    [SkippableFact]
    public async Task Location_LegacyKey_StillUnscoped()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        SeedLocation(s.EmployeeAName, s.CompanyA);
        SeedLocation(s.EmployeeBName, s.CompanyB);

        await using (var c = NewCtx(withApiKey: true))
        {
            var post = await LocationController(c).UpdateLocation(new EmployeeLocationController.LocationUpdateRequest
            {
                UserId = "مفتاح " + s.Suffix, Latitude = 33, Longitude = 44,
            });
            Assert.Equal(200, StatusOf(post));
        }

        await using var c2 = NewCtx(withApiKey: true);
        var r = await LocationController(c2).GetActiveLocations();
        Assert.Equal(200, StatusOf(r));
        var ids = Strings(Json(r).GetProperty("data"), "userId");
        Assert.Contains(s.EmployeeAName, ids);
        Assert.Contains(s.EmployeeBName, ids);
        Assert.Contains("مفتاح " + s.Suffix, ids);
    }

    // ═══════════════════════════ LocationHub ═══════════════════════════

    private sealed class TestCallerContext(HttpContext http) : HubCallerContext
    {
        private readonly FeatureCollection _features = CreateFeatures(http);
        public bool Aborted { get; private set; }
        public override string ConnectionId { get; } = Guid.NewGuid().ToString("N");
        public override string? UserIdentifier => null;
        public override ClaimsPrincipal? User => http.User;
        public override IDictionary<object, object?> Items { get; } = new Dictionary<object, object?>();
        public override IFeatureCollection Features => _features;
        public override CancellationToken ConnectionAborted => CancellationToken.None;
        public override void Abort() => Aborted = true;

        private static FeatureCollection CreateFeatures(HttpContext http)
        {
            var f = new FeatureCollection();
            f.Set<IHttpContextFeature>(new HttpContextFeature { HttpContext = http });
            return f;
        }

        private sealed class HttpContextFeature : IHttpContextFeature
        {
            public HttpContext? HttpContext { get; set; }
        }
    }

    private sealed class RecordingGroups : IGroupManager
    {
        public List<string> Joined { get; } = new();
        public Task AddToGroupAsync(string connectionId, string groupName, CancellationToken cancellationToken = default)
        {
            Joined.Add(groupName);
            return Task.CompletedTask;
        }
        public Task RemoveFromGroupAsync(string connectionId, string groupName, CancellationToken cancellationToken = default) =>
            Task.CompletedTask;
    }

    private async Task<(TestCallerContext Ctx, RecordingGroups Groups)> ConnectHub(DefaultHttpContext http)
    {
        var services = new ServiceCollection();
        services.AddScoped<IUnitOfWork>(_ => new UnitOfWork(_fx.CreateContext(PostgresFixture.SystemTenant)));
        await using var sp = services.BuildServiceProvider();

        var ctx = new TestCallerContext(http);
        var groups = new RecordingGroups();
        var hub = new LocationHub(Config(), sp.GetRequiredService<IServiceScopeFactory>(), NullLogger<LocationHub>.Instance)
        {
            Context = ctx,
            Groups = groups,
        };
        await hub.OnConnectedAsync();
        return (ctx, groups);
    }

    [SkippableFact]
    public async Task Hub_Jwt_TrackingUser_JoinsOnlyOwnCompanyGroup_EmployeeAndCitizenAborted()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();

        var (okCtx, okGroups) = await ConnectHub(Http(s.TrackerA, s.CompanyA, false));
        Assert.False(okCtx.Aborted);
        Assert.Equal(new[] { LocationHub.CompanyGroup(s.CompanyA) }, okGroups.Joined);

        var (empCtx, empGroups) = await ConnectHub(Http(s.EmployeeA, s.CompanyA, false));
        Assert.True(empCtx.Aborted);
        Assert.Empty(empGroups.Joined);

        var (citCtx, _) = await ConnectHub(Http(s.Citizen, null, false));
        Assert.True(citCtx.Aborted);

        var (anonCtx, _) = await ConnectHub(Http(null, null, false));
        Assert.True(anonCtx.Aborted);
    }

    [SkippableFact]
    public async Task Hub_LegacyKeyQuery_JoinsWatchers_WrongKeyAborted()
    {
        _fx.SkipIfUnavailable();

        var good = Http(null, null, false);
        good.Request.QueryString = new QueryString("?apiKey=" + TestApiKey);
        var (goodCtx, goodGroups) = await ConnectHub(good);
        Assert.False(goodCtx.Aborted);
        Assert.Equal(new[] { LocationHub.LegacyWatchersGroup }, goodGroups.Joined);

        var bad = Http(null, null, false);
        bad.Request.QueryString = new QueryString("?apiKey=wrong-" + Guid.NewGuid().ToString("N"));
        var (badCtx, _) = await ConnectHub(bad);
        Assert.True(badCtx.Aborted);
    }

    // ═══════════════════════════ Reminder ═══════════════════════════

    private sealed class NoHttpFactory : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) => throw new InvalidOperationException("لا شبكة في الاختبار");
    }

    private ReminderController Reminder(Ctx c, Guid? defaultCompany = null) =>
        Attach(new ReminderController(c.Uow, Config(defaultCompany), NullLogger<ReminderController>.Instance, new NoHttpFactory()), c.Http);

    [SkippableFact]
    public async Task Reminder_Jwt_SettingsAndLogs_AreCompanyScoped_QueryTenantIgnored()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        await using (var seed = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            seed.Set<ReminderSettings>().AddRange(
                new ReminderSettings { TenantId = s.CompanyA.ToString(), CompanyId = s.CompanyA, IsEnabled = true, BatchesJson = "[{\"id\":\"a\"}]" },
                new ReminderSettings { TenantId = s.CompanyB.ToString(), CompanyId = s.CompanyB, IsEnabled = true, BatchesJson = "[{\"id\":\"b\"}]" });
            seed.Set<ReminderExecutionLog>().AddRange(
                new ReminderExecutionLog { TenantId = s.CompanyA.ToString(), CompanyId = s.CompanyA, BatchId = "logA-" + s.Suffix },
                new ReminderExecutionLog { TenantId = s.CompanyB.ToString(), CompanyId = s.CompanyB, BatchId = "logB-" + s.Suffix });
            await seed.SaveChangesAsync();
        }

        await using var c = NewCtx(s.EmployeeA, s.CompanyA);
        var settings = await Reminder(c).GetSettings(s.CompanyB.ToString()); // محاولة قراءة إعدادات ب
        Assert.Equal(200, StatusOf(settings));
        Assert.Contains("\"a\"", Json(settings).GetProperty("data").GetProperty("batchesJson").GetString());

        var logs = await Reminder(c).GetLogs(500);
        var batchIds = Strings(Json(logs).GetProperty("data"), "batchId");
        Assert.Contains("logA-" + s.Suffix, batchIds);
        Assert.DoesNotContain("logB-" + s.Suffix, batchIds);
    }

    [SkippableFact]
    public async Task Reminder_Jwt_SaveSettings_OnlyDefaultCompanyManager_N8nLogKeyOnly()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        var body = new ReminderController.SaveSettingsRequest { TenantId = s.CompanyB.ToString(), IsEnabled = false, BatchesJson = "[]" };

        // مدير شركة ليست الافتراضية ⇒ 403 (سير عمل n8n عام للمنصّة)
        await using (var c = NewCtx(s.ManagerB, s.CompanyB))
            Assert.Equal(403, StatusOf(await Reminder(c, defaultCompany: s.CompanyA).SaveSettings(body)));
        // موظف الشركة الافتراضية (ليس مديراً) ⇒ 403
        await using (var c = NewCtx(s.EmployeeA, s.CompanyA))
            Assert.Equal(403, StatusOf(await Reminder(c, defaultCompany: s.CompanyA).SaveSettings(body)));
        // مدير الشركة الافتراضية ⇒ 200 ويُحفظ لشركته هو (tenantId في الجسم يُتجاهل)
        await using (var c = NewCtx(s.ManagerA, s.CompanyA))
            Assert.Equal(200, StatusOf(await Reminder(c, defaultCompany: s.CompanyA).SaveSettings(body)));

        await using (var check = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            Assert.True(await check.Set<ReminderSettings>().AnyAsync(x => x.CompanyId == s.CompanyA));
            Assert.False(await check.Set<ReminderSettings>().AnyAsync(x => x.CompanyId == s.CompanyB));
        }

        var log = new ReminderController.SaveLogRequest { BatchId = "n8n-" + s.Suffix, Days = 1 };
        await using (var c = NewCtx(s.ManagerA, s.CompanyA))
            Assert.Equal(403, StatusOf(await Reminder(c).SaveLog(log)));
        await using (var c = NewCtx(withApiKey: true))
            Assert.Equal(200, StatusOf(await Reminder(c).SaveLog(log)));
        await using (var c = NewCtx(s.Citizen))
            Assert.Equal(403, StatusOf(await Reminder(c).GetLogs()));
    }

    // ═══════════════════════════ WhatsApp ═══════════════════════════

    private WhatsAppController WhatsApp(Ctx c, Guid? defaultCompany = null) =>
        Attach(new WhatsAppController(c.Uow, Config(defaultCompany), NullLogger<WhatsAppController>.Instance), c.Http);

    private static string Phone() => "9647" + Random.Shared.Next(100000000, 999999999);

    [SkippableFact]
    public async Task WhatsApp_Jwt_Inbox_IsCompanyScoped_UnstampedOnlyForDefaultCompany()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        string pA = Phone(), pB = Phone(), pNull = Phone();
        await using (var seed = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            seed.Set<WhatsAppConversation>().AddRange(
                new WhatsAppConversation { PhoneNumber = pA, CompanyId = s.CompanyA, LastMessageTime = DateTime.UtcNow },
                new WhatsAppConversation { PhoneNumber = pB, CompanyId = s.CompanyB, LastMessageTime = DateTime.UtcNow },
                new WhatsAppConversation { PhoneNumber = pNull, CompanyId = null, LastMessageTime = DateTime.UtcNow });
            await seed.SaveChangesAsync();
        }

        await using (var c = NewCtx(s.EmployeeA, s.CompanyA))
        {
            var phones = Strings(Json(await WhatsApp(c, defaultCompany: s.CompanyA).GetConversations(5000)).GetProperty("data"), "phoneNumber");
            Assert.Contains(pA, phones);
            Assert.Contains(pNull, phones);
            Assert.DoesNotContain(pB, phones);
        }

        await using (var c = NewCtx(s.EmployeeB, s.CompanyB))
        {
            var phones = Strings(Json(await WhatsApp(c, defaultCompany: s.CompanyA).GetConversations(5000)).GetProperty("data"), "phoneNumber");
            Assert.Contains(pB, phones);
            Assert.DoesNotContain(pA, phones);
            Assert.DoesNotContain(pNull, phones);

            // رسائل/تعليم محادثة شركة أخرى ⇒ غير موجودة
            Assert.Equal(404, StatusOf(await WhatsApp(c, defaultCompany: s.CompanyA).MarkAsRead(pA)));
            // تسجيل رسالة لرقم محادثته في شركة أخرى ⇒ تعارض لا كتابة فوقها
            Assert.Equal(409, StatusOf(await WhatsApp(c, defaultCompany: s.CompanyA)
                .SendMessage(pA, new WhatsAppController.SendMessageRequest { Message = "x" })));
        }

        await using (var c = NewCtx(withApiKey: true))
        {
            var phones = Strings(Json(await WhatsApp(c).GetConversations(5000)).GetProperty("data"), "phoneNumber");
            Assert.Contains(pA, phones);
            Assert.Contains(pB, phones);
        }
    }

    [SkippableFact]
    public async Task WhatsApp_Jwt_NewConversation_StampedWithTokenCompany_CitizenRejected()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        var p = Phone();

        await using (var c = NewCtx(s.EmployeeB, s.CompanyB))
            Assert.Equal(200, StatusOf(await WhatsApp(c).SendMessage(p, new WhatsAppController.SendMessageRequest { Message = "مرحبا" })));

        await using (var check = _fx.CreateContext(PostgresFixture.SystemTenant))
            Assert.Equal(s.CompanyB, (await check.Set<WhatsAppConversation>().SingleAsync(x => x.PhoneNumber == p)).CompanyId);

        await using (var c = NewCtx(s.Citizen))
            Assert.Equal(403, StatusOf(await WhatsApp(c).GetUnreadCount()));
        await using (var c = NewCtx())
            Assert.Equal(401, StatusOf(await WhatsApp(c).GetUnreadCount()));
    }

    // ═══════════════════════════ CompanyFtthSettings ═══════════════════════════

    private CompanyFtthSettingsController Ftth(Ctx c) =>
        Attach(new CompanyFtthSettingsController(c.Uow, Config(), c.Db, NullLogger<CompanyFtthSettingsController>.Instance), c.Http);

    [SkippableFact]
    public async Task FtthSettings_Jwt_OtherCompany403_PasswordOnlyForManager_WritesManagerOnly()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        var secret = "pw-" + s.Suffix;
        await using (var seed = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            seed.Set<CompanyFtthSettings>().Add(new CompanyFtthSettings
            {
                Id = Guid.NewGuid(), CompanyId = s.CompanyA, FtthUsername = "u", FtthPassword = secret, IsAutoSyncEnabled = false,
            });
            await seed.SaveChangesAsync();
        }

        await using (var c = NewCtx(s.EmployeeB, s.CompanyB))
            Assert.Equal(403, StatusOf(await Ftth(c).GetSettings(s.CompanyA)));

        await using (var c = NewCtx(s.EmployeeA, s.CompanyA))
        {
            var r = await Ftth(c).GetSettings(s.CompanyA);
            Assert.Equal(200, StatusOf(r));
            Assert.Equal("", Json(r).GetProperty("data").GetProperty("ftthPassword").GetString());
            Assert.Equal(403, StatusOf(await Ftth(c).TriggerSync(s.CompanyA)));
            Assert.Equal(403, StatusOf(await Ftth(c).SaveSettings(new SaveFtthSettingsRequest(s.CompanyA, "u", "p"))));
            Assert.Equal(200, StatusOf(await Ftth(c).GetSyncStatus(s.CompanyA)));
        }

        await using (var c = NewCtx(s.ManagerA, s.CompanyA))
        {
            var r = await Ftth(c).GetSettings(s.CompanyA);
            Assert.Equal(secret, Json(r).GetProperty("data").GetProperty("ftthPassword").GetString());
            // مدير أ لا يكتب إعدادات شركة ب عبر الجسم
            Assert.Equal(403, StatusOf(await Ftth(c).SaveSettings(new SaveFtthSettingsRequest(s.CompanyB, "u", "p"))));
        }

        await using (var c = NewCtx(withApiKey: true))
            Assert.Equal(secret, Json(await Ftth(c).GetSettings(s.CompanyA)).GetProperty("data").GetProperty("ftthPassword").GetString());
        await using (var c = NewCtx(s.Citizen))
            Assert.Equal(403, StatusOf(await Ftth(c).GetSettings(s.CompanyA)));
    }

    // ═══════════════════════════ IptvSubscribers ═══════════════════════════

    private IptvSubscribersController Iptv(Ctx c) => Attach(new IptvSubscribersController(c.Uow, Config()), c.Http);

    [SkippableFact]
    public async Task Iptv_Jwt_ListAndGet_AreCompanyScoped_CreateStampsTokenCompany()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        long idB;
        await using (var seed = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            var a = new IptvSubscriber { CompanyId = s.CompanyA.ToString(), CustomerName = "iptvA-" + s.Suffix };
            var b = new IptvSubscriber { CompanyId = s.CompanyB.ToString(), CustomerName = "iptvB-" + s.Suffix };
            seed.Set<IptvSubscriber>().AddRange(a, b);
            await seed.SaveChangesAsync();
            idB = b.Id;
        }

        // موظف بصلاحيات V2 لا تشمل iptv ⇒ 403 (نفس بوابة الواجهة)
        await using (var e = NewCtx(s.EmployeeA, s.CompanyA))
            Assert.Equal(403, StatusOf(await Iptv(e).GetAll(null)));

        await using var c = NewCtx(s.ManagerA, s.CompanyA);
        Assert.Equal(403, StatusOf(await Iptv(c).GetAll(s.CompanyB.ToString())));

        var list = Json(await Iptv(c).GetAll(null)).GetProperty("data");
        var names = Strings(list, "CustomerName");
        Assert.Contains("iptvA-" + s.Suffix, names);
        Assert.DoesNotContain("iptvB-" + s.Suffix, names);

        Assert.Equal(404, StatusOf(await Iptv(c).GetById(idB)));
        Assert.Equal(404, StatusOf(await Iptv(c).Delete(idB)));

        var created = await Iptv(c).Create(new CreateIptvSubscriberRequest(
            "", null, "new-" + s.Suffix, null, null, null, null, null));
        Assert.Equal(200, StatusOf(created));
        await using (var check = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            var row = await check.Set<IptvSubscriber>().SingleAsync(x => x.CustomerName == "new-" + s.Suffix);
            Assert.Equal(s.CompanyA.ToString(), row.CompanyId);
        }

        await using (var k = NewCtx(withApiKey: true))
            Assert.Equal(200, StatusOf(await Iptv(k).GetById(idB)));
        await using (var cit = NewCtx(s.Citizen))
            Assert.Equal(403, StatusOf(await Iptv(cit).GetAll(null)));
    }

    // ═══════════════════════════ SubscriberCache ═══════════════════════════

    private SubscriberCacheController Cache(Ctx c) =>
        Attach(new SubscriberCacheController(c.Uow, Config(), NullLogger<SubscriberCacheController>.Instance, c.Db), c.Http);

    [SkippableFact]
    public async Task SubscriberCache_Jwt_OtherTenant403_OwnTenantOk_KeyStillWorks()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        await using (var seed = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            seed.Set<FtthSubscriberCache>().Add(new FtthSubscriberCache { CompanyId = s.CompanyB, SubscriptionId = "subB-" + s.Suffix });
            await seed.SaveChangesAsync();
        }

        await using (var c = NewCtx(s.EmployeeA, s.CompanyA))
        {
            Assert.Equal(403, StatusOf(await Cache(c).Download(s.CompanyB)));
            Assert.Equal(403, StatusOf(await Cache(c).GetInfo(s.CompanyB)));
            Assert.Equal(200, StatusOf(await Cache(c).GetInfo(s.CompanyA)));
        }

        await using (var c = NewCtx(withApiKey: true))
            Assert.Equal(1, Json(await Cache(c).Download(s.CompanyB)).GetProperty("count").GetInt32());
        await using (var c = NewCtx(s.Citizen))
            Assert.Equal(403, StatusOf(await Cache(c).GetInfo(s.CompanyA)));
    }

    // ═══════════════════════════ ZoneStatistics ═══════════════════════════

    private ZoneStatisticsController Zones(Ctx c, Guid? defaultCompany = null) =>
        Attach(new ZoneStatisticsController(c.Uow, Config(defaultCompany)), c.Http);

    [SkippableFact]
    public async Task Zones_Jwt_ScopedReadsAndSync_DoesNotTouchOtherCompanyZone()
    {
        _fx.SkipIfUnavailable();
        var s = SeedData();
        var shared = "zone-" + s.Suffix;
        int idB;
        await using (var seed = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            var zb = new ZoneStatistic { ZoneName = shared, Fats = 5, CompanyId = s.CompanyB };
            seed.Set<ZoneStatistic>().Add(zb);
            await seed.SaveChangesAsync();
            idB = zb.Id;
        }

        await using (var e = NewCtx(s.EmployeeA, s.CompanyA)) // V2 بلا zones ⇒ 403
            Assert.Equal(403, StatusOf(await Zones(e).GetAll(shared)));

        await using (var c = NewCtx(s.ManagerA, s.CompanyA))
        {
            var r = await Zones(c).SyncZones(new List<SyncZoneRequest> { new(shared, 9, s.CompanyB) });
            Assert.Equal(200, StatusOf(r));
            Assert.Equal(1, Json(r).GetProperty("added").GetInt32());

            var names = Json(await Zones(c).GetAll(shared)).EnumerateArray().Select(z => z.GetProperty("CompanyId").GetString()).ToList();
            Assert.Equal(new[] { s.CompanyA.ToString() }, names);

            Assert.Equal(404, StatusOf(await Zones(c).Delete(idB)));
        }

        await using (var check = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            var b = await check.Set<ZoneStatistic>().SingleAsync(z => z.Id == idB);
            Assert.Equal(5, b.Fats); // زون ب لم تُعدَّل
            var a = await check.Set<ZoneStatistic>().SingleAsync(z => z.ZoneName == shared && z.CompanyId == s.CompanyA);
            Assert.Equal(9, a.Fats);
        }

        await using (var c = NewCtx(withApiKey: true))
            Assert.Equal(2, Json(await Zones(c).GetAll(shared)).GetArrayLength());
        await using (var c = NewCtx(s.Citizen))
            Assert.Equal(403, StatusOf(await Zones(c).GetSummary()));
        await using (var c = NewCtx())
            Assert.Equal(401, StatusOf(await Zones(c).GetSummary()));
    }
}
