using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Sadara.API.Controllers;
using Sadara.API.Hubs;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Data;
using Sadara.Integration.Tests.Support;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// اختبارات «الإخراج الإجباري لكل موظفي الشركة» (<c>POST /api/session/force-logout-company</c>).
///
/// يتحقّق على Postgres حقيقي (ExecuteUpdateAsync لا يعمل على InMemory) من:
///   1) العزل بين الشركات + استثناء الضاغط + ضبط ختم الإبطال + إنشاء سجلّ تدقيق.
///   2) رفض 403 لغير مدير الشركة.
///   3) رفض 400 حين لا تحمل الجلسة شركة.
///
/// يُتخطّى كاملاً إذا لم يتوفّر Docker (انظر <see cref="PostgresFixture"/>). لا يمسّ الإنتاج.
/// </summary>
[Collection("Postgres")]
public class ForceLogoutTests
{
    private readonly PostgresFixture _fx;
    public ForceLogoutTests(PostgresFixture fx) => _fx = fx;

    private static readonly Guid CompanyA = Guid.Parse("a1a1a1a1-aaaa-4aaa-8aaa-a1a1a1a1a1a1");
    private static readonly Guid CompanyB = Guid.Parse("b2b2b2b2-bbbb-4bbb-8bbb-b2b2b2b2b2b2");

    private SessionController BuildController(Guid currentUserId, Guid? companyId, string? role)
    {
        var tenant = new TestTenant { CompanyId = companyId, IsSuperAdmin = false };
        var controller = new SessionController(
            _fx.CreateContext(tenant),
            new NoopHubContext(),
            tenant,
            NullLogger<SessionController>.Instance);

        var claims = new List<Claim> { new(ClaimTypes.NameIdentifier, currentUserId.ToString()) };
        if (role is not null) claims.Add(new Claim(ClaimTypes.Role, role));
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(new ClaimsIdentity(claims, "TestAuth"))
            }
        };
        return controller;
    }

    private Guid SeedUser(Guid companyId, UserRole role, string? refreshToken)
    {
        var id = Guid.NewGuid();
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<User>().Add(new User
        {
            Id = id,
            Username = $"u-{id:N}".Substring(0, 12),
            FullName = "مستخدم اختبار",
            PhoneNumber = id.ToString("N").Substring(0, 15), // فريد لتفادي فهرس (CompanyId, PhoneNumber)
            CompanyId = companyId,
            Role = role,
            RefreshToken = refreshToken,
            RefreshTokenExpiryTime = refreshToken == null ? null : DateTime.UtcNow.AddDays(7),
        });
        ctx.SaveChanges();
        return id;
    }

    private void SeedCompanies()
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        foreach (var (id, code) in new[] { (CompanyA, "FL-A"), (CompanyB, "FL-B") })
        {
            if (!ctx.Set<Company>().IgnoreQueryFilters().Any(c => c.Id == id))
                ctx.Set<Company>().Add(new Company { Id = id, Name = code, Code = code });
        }
        ctx.SaveChanges();
    }

    [SkippableFact]
    public async Task ForceLogout_ClearsOnlyOwnCompany_ExcludesPresser_AndAudits()
    {
        _fx.SkipIfUnavailable();
        SeedCompanies();

        var admin = SeedUser(CompanyA, UserRole.CompanyAdmin, "admin-rt");
        var emp1 = SeedUser(CompanyA, UserRole.Technician, "emp1-rt");
        var emp2 = SeedUser(CompanyA, UserRole.Employee, "emp2-rt");
        var otherCompanyUser = SeedUser(CompanyB, UserRole.Technician, "b-rt");

        var controller = BuildController(admin, CompanyA, "CompanyAdmin");
        var result = await controller.ForceLogoutCompany();

        // النتيجة 200 (العدد يُتحقَّق منه عبر سجلّ التدقيق وحالة القاعدة أدناه).
        Assert.IsType<OkObjectResult>(result);

        using var verify = _fx.CreateContext(PostgresFixture.SystemTenant);

        // الموظفان: RefreshToken مُسح + ختم الإبطال مضبوط.
        foreach (var uid in new[] { emp1, emp2 })
        {
            var u = verify.Set<User>().IgnoreQueryFilters().Single(x => x.Id == uid);
            Assert.Null(u.RefreshToken);
            Assert.NotNull(u.SessionsRevokedAtUtc);
        }

        // الأدمن الضاغط: لم يُمسّ.
        var adminRow = verify.Set<User>().IgnoreQueryFilters().Single(x => x.Id == admin);
        Assert.Equal("admin-rt", adminRow.RefreshToken);
        Assert.Null(adminRow.SessionsRevokedAtUtc);

        // شركة أخرى: لم تُمسّ (العزل).
        var bRow = verify.Set<User>().IgnoreQueryFilters().Single(x => x.Id == otherCompanyUser);
        Assert.Equal("b-rt", bRow.RefreshToken);
        Assert.Null(bRow.SessionsRevokedAtUtc);

        // سجلّ تدقيق أُنشئ لشركة A بالعدد الصحيح.
        var audit = verify.Set<ForceLogoutAudit>().IgnoreQueryFilters()
            .Where(a => a.CompanyId == CompanyA && a.RequestedByUserId == admin)
            .OrderByDescending(a => a.ExecutedAtUtc).First();
        Assert.Equal(2, audit.AffectedCount);
    }

    [SkippableFact]
    public async Task ForceLogout_NonAdmin_Returns403()
    {
        _fx.SkipIfUnavailable();
        SeedCompanies();
        var tech = SeedUser(CompanyA, UserRole.Technician, "tech-rt");

        var controller = BuildController(tech, CompanyA, "Technician");
        var result = await controller.ForceLogoutCompany();

        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(403, obj.StatusCode);

        // لم تُبطَل أي جلسة.
        using var verify = _fx.CreateContext(PostgresFixture.SystemTenant);
        var u = verify.Set<User>().IgnoreQueryFilters().Single(x => x.Id == tech);
        Assert.Equal("tech-rt", u.RefreshToken);
    }

    [SkippableFact]
    public async Task ForceLogout_NoCompanyInToken_Returns400()
    {
        _fx.SkipIfUnavailable();
        var controller = BuildController(Guid.NewGuid(), companyId: null, role: "CompanyAdmin");
        var result = await controller.ForceLogoutCompany();
        var obj = Assert.IsType<BadRequestObjectResult>(result);
        Assert.Equal(400, obj.StatusCode);
    }

    // ═══════ Stub بسيط لـ IHubContext<TaskHub> (بثّ SignalR لا أثر له في الاختبار) ═══════

    private sealed class NoopHubContext : IHubContext<TaskHub>
    {
        public IHubClients Clients { get; } = new NoopClients();
        public IGroupManager Groups { get; } = new NoopGroups();
    }

    private sealed class NoopClients : IHubClients
    {
        private static readonly IClientProxy Proxy = new NoopProxy();
        public IClientProxy All => Proxy;
        public IClientProxy AllExcept(IReadOnlyList<string> excludedConnectionIds) => Proxy;
        public IClientProxy Client(string connectionId) => Proxy;
        public IClientProxy Clients(IReadOnlyList<string> connectionIds) => Proxy;
        public IClientProxy Group(string groupName) => Proxy;
        public IClientProxy GroupExcept(string groupName, IReadOnlyList<string> excludedConnectionIds) => Proxy;
        public IClientProxy Groups(IReadOnlyList<string> groupNames) => Proxy;
        public IClientProxy User(string userId) => Proxy;
        public IClientProxy Users(IReadOnlyList<string> userIds) => Proxy;
    }

    private sealed class NoopProxy : IClientProxy
    {
        public Task SendCoreAsync(string method, object?[] args, CancellationToken cancellationToken = default)
            => Task.CompletedTask;
    }

    private sealed class NoopGroups : IGroupManager
    {
        public Task AddToGroupAsync(string connectionId, string groupName, CancellationToken cancellationToken = default)
            => Task.CompletedTask;
        public Task RemoveFromGroupAsync(string connectionId, string groupName, CancellationToken cancellationToken = default)
            => Task.CompletedTask;
    }
}
