using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Abstractions;
using Microsoft.AspNetCore.Mvc.Infrastructure;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Sadara.API.Authorization;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;
using Sadara.Infrastructure.Repositories;
using Sadara.Integration.Tests.Support;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// The root fail-closed fix for RequirePermissionAttribute: absence/emptiness of V2 permissions grants
/// NO automatic privilege (secure by default). Drives the authorization filter end-to-end against real
/// PostgreSQL-backed users. Proves: empty-V2 ⇒ denied; view-only ⇒ cannot write; SuperAdmin ⇒ allowed;
/// the Authz:FailOpen emergency escape valve restores legacy behaviour.
/// </summary>
[Collection("Postgres")]
public class AuthzFailClosedTests : IDisposable
{
    private static readonly Guid CompanyA = Guid.Parse("a7a7a7a7-0000-4000-8000-000000000001");
    private readonly PostgresFixture _fx;

    public AuthzFailClosedTests(PostgresFixture fx) { _fx = fx; if (_fx.Available) Cleanup(); }
    public void Dispose() { if (_fx.Available) Cleanup(); }

    private void Cleanup()
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Database.ExecuteSqlRaw(
            "DELETE FROM \"Users\" WHERE \"CompanyId\" = {0}; DELETE FROM \"Companies\" WHERE \"Id\" = {0};", CompanyA);
    }

    private Guid SeedUser(UserRole role, string? firstV2, string? secondV2 = null)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        if (!ctx.Set<Company>().IgnoreQueryFilters().Any(c => c.Id == CompanyA))
            ctx.Set<Company>().Add(new Company { Id = CompanyA, Name = "ش-أمن", Code = "C-SEC" });
        var id = Guid.NewGuid();
        ctx.Set<User>().Add(new User
        {
            Id = id, Username = $"u-{id:N}"[..12], FullName = "مستخدم",
            PhoneNumber = "0781" + id.ToString("N")[..7], CompanyId = CompanyA, Role = role,
            FirstSystemPermissionsV2 = firstV2, SecondSystemPermissionsV2 = secondV2
        });
        ctx.SaveChanges();
        return id;
    }

    // Runs the attribute against a user and returns the resulting HTTP status (0 = allowed/no result).
    private async Task<int> Authorize(Guid userId, string role, string key, string action,
        PermissionSystem system = PermissionSystem.First, bool failOpen = false)
    {
        await using var db = _fx.CreateContext(PostgresFixture.SystemTenant);
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { ["Authz:FailOpen"] = failOpen ? "true" : "false" })
            .Build();
        var services = new ServiceCollection();
        services.AddSingleton<IUnitOfWork>(new UnitOfWork(db));
        services.AddSingleton<IConfiguration>(config);
        var sp = services.BuildServiceProvider();

        var http = new DefaultHttpContext { RequestServices = sp };
        http.User = new ClaimsPrincipal(new ClaimsIdentity(new[]
        {
            new Claim(ClaimTypes.Role, role),
            new Claim(ClaimTypes.NameIdentifier, userId.ToString()),
        }, "test"));
        var ad = new ActionDescriptor { EndpointMetadata = new List<object>() };
        var filterCtx = new AuthorizationFilterContext(
            new ActionContext(http, new RouteData(), ad), new List<IFilterMetadata>());

        var attr = new RequirePermissionAttribute(key, action, system);
        await attr.OnAuthorizationAsync(filterCtx);
        return (filterCtx.Result as IStatusCodeActionResult)?.StatusCode ?? 0;
    }

    [SkippableFact]
    public async Task EmptyV2_NonSuperAdmin_IsDenied_FailClosed()
    {
        _fx.SkipIfUnavailable();
        foreach (var v2 in new string?[] { null, "", "{}" })
        {
            var uid = SeedUser(UserRole.Employee, v2);
            // كان fail-open يمنح accounting.view؛ الآن fail-closed ⇒ 403.
            Assert.Equal(403, await Authorize(uid, "Employee", "accounting", "view"));
            Cleanup();
        }
    }

    [SkippableFact]
    public async Task ViewOnlyUser_CanView_ButCannotWrite()
    {
        _fx.SkipIfUnavailable();
        var uid = SeedUser(UserRole.Employee, "{\"accounting\":{\"view\":true,\"add\":false}}");
        Assert.Equal(0, await Authorize(uid, "Employee", "accounting", "view"));   // view allowed
        Assert.Equal(403, await Authorize(uid, "Employee", "accounting", "add"));  // write denied
        Assert.Equal(403, await Authorize(uid, "Employee", "accounting", "edit"));
        Assert.Equal(403, await Authorize(uid, "Employee", "accounting", "delete"));
    }

    [SkippableFact]
    public async Task WriterUser_WithExplicitAdd_CanWrite()
    {
        _fx.SkipIfUnavailable();
        var uid = SeedUser(UserRole.Employee, "{\"accounting\":{\"view\":true,\"add\":true,\"edit\":true,\"delete\":true}}");
        Assert.Equal(0, await Authorize(uid, "Employee", "accounting", "add"));
        Assert.Equal(0, await Authorize(uid, "Employee", "accounting", "edit"));
        Assert.Equal(0, await Authorize(uid, "Employee", "accounting", "delete"));
    }

    [SkippableFact]
    public async Task SuperAdmin_IsAllowed_EvenWithEmptyV2()
    {
        _fx.SkipIfUnavailable();
        var uid = SeedUser(UserRole.SuperAdmin, null);
        Assert.Equal(0, await Authorize(uid, "SuperAdmin", "accounting", "delete")); // role bypass preserved
    }

    [SkippableFact]
    public async Task ProposedSyncAccountLeastPrivilege_AllowsSubscription_DeniesManualAccounting()
    {
        _fx.SkipIfUnavailable();
        // صلاحية «مزامنة» المقترحة (أقل امتياز): subscriptions add/edit في النظام الثاني فقط —
        // تطابق نشاطها (تجديد/تغيير FTTH) بلا أي صلاحية محاسبة يدوية.
        var uid = SeedUser(UserRole.Employee, firstV2: null,
            secondV2: "{\"subscriptions\":{\"add\":true,\"edit\":true}}");

        // يُسمح بإنشاء/تعديل الاشتراك (مسار المزامنة الفعلي) — النظام الثاني.
        Assert.Equal(0, await Authorize(uid, "Employee", "subscriptions", "add", PermissionSystem.Second));
        Assert.Equal(0, await Authorize(uid, "Employee", "subscriptions", "edit", PermissionSystem.Second));
        // ويُرفَض أي إنشاء/ترحيل محاسبي يدوي (لا تصعيد مالي خارج نطاق المزامنة).
        Assert.Equal(403, await Authorize(uid, "Employee", "accounting", "add"));
        Assert.Equal(403, await Authorize(uid, "Employee", "accounting", "edit"));
        Assert.Equal(403, await Authorize(uid, "Employee", "subscriptions", "delete", PermissionSystem.Second));
    }

    [SkippableFact]
    public async Task EmergencyEscapeValve_FailOpen_RestoresLegacyGrant()
    {
        _fx.SkipIfUnavailable();
        var uid = SeedUser(UserRole.Employee, null);
        // مع Authz:FailOpen=true يعود السلوك القديم (سماح عند فراغ V2) — صمّام تراجع فقط.
        Assert.Equal(0, await Authorize(uid, "Employee", "accounting", "view", failOpen: true));
        // وبدونه يُرفَض (الافتراضي fail-closed).
        Assert.Equal(403, await Authorize(uid, "Employee", "accounting", "view", failOpen: false));
    }
}
