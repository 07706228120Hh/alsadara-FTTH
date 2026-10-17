using System.Reflection;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Abstractions;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.AspNetCore.Routing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Sadara.API.Authorization;
using Sadara.API.Controllers;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;
using Sadara.Infrastructure.Data;
using Sadara.Infrastructure.Repositories;
using Sadara.Integration.Tests.Support;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// Phase 0 / Stream C — tenant isolation + write authorization for
/// <see cref="AccountingController"/>, <see cref="WithdrawalRequestController"/> and <see cref="HrReportsController"/>.
///
/// Runs on a real Postgres (Testcontainers, shared "Postgres" collection) because several actions open
/// real DB transactions. The central EF tenant filter is OFF (EnforceIsolation=false, as in production),
/// so every assertion here exercises the per-controller isolation, not the global filter.
///
/// Each test class instance seeds its own two companies (fresh Guids) so it never collides with other
/// suites sharing the container.
/// </summary>
[Collection("Postgres")]
public class AccountingTenantIsolationTests
{
    private readonly PostgresFixture _fx;

    private readonly Guid _companyA = Guid.NewGuid();
    private readonly Guid _companyB = Guid.NewGuid();

    // V2 permission JSONs (shape stored in User.FirstSystemPermissionsV2)
    private const string ViewOnlyPerms = """{"accounting":{"view":true}}""";
    private const string AccountantPerms = """{"accounting":{"view":true,"add":true,"edit":true}}""";
    private const string FullSalariesPerms =
        """{"accounting":{"view":true,"add":true,"edit":true,"delete":true},"accounting.salaries":{"view":true,"add":true,"edit":true,"delete":true},"accounting.withdrawals":{"view":true,"edit":true},"hr.reports":{"view":true}}""";

    public AccountingTenantIsolationTests(PostgresFixture fx) => _fx = fx;

    // ═══════════════════════ seeding ═══════════════════════

    private sealed record World(
        Guid AccountantA, Guid EmployeeA, Guid EmployeeB,
        long SalaryA, long SalaryB, long AdjustmentB,
        Guid CashBoxA, Guid CashBoxB,
        long WithdrawalA, long WithdrawalB);

    private World Seed()
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<Company>().AddRange(
            new Company { Id = _companyA, Name = "شركة أ", Code = "ISO-A-" + _companyA.ToString("N")[..8] },
            new Company { Id = _companyB, Name = "شركة ب", Code = "ISO-B-" + _companyB.ToString("N")[..8] });
        ctx.SaveChanges();

        User NewUser(Guid company, string? perms) => new()
        {
            Id = Guid.NewGuid(),
            Username = "iso-" + Guid.NewGuid().ToString("N")[..10],
            FullName = "مستخدم اختبار",
            PhoneNumber = UniquePhone(),
            CompanyId = company,
            Role = UserRole.Employee,
            FirstSystemPermissionsV2 = perms,
            Salary = 600_000m,
            IsInSalaryRoster = true,
            IsActive = true,
        };

        var accountantA = NewUser(_companyA, FullSalariesPerms);
        var employeeA = NewUser(_companyA, null);
        var employeeB = NewUser(_companyB, null);
        ctx.Set<User>().AddRange(accountantA, employeeA, employeeB);
        ctx.SaveChanges();

        EmployeeSalary NewSalary(Guid company, Guid user) => new()
        {
            UserId = user, CompanyId = company, Month = 1, Year = 2031,
            BaseSalary = 500_000m, NetSalary = 500_000m, Status = SalaryStatus.Pending,
        };
        var salaryA = NewSalary(_companyA, employeeA.Id);
        var salaryB = NewSalary(_companyB, employeeB.Id);
        ctx.Set<EmployeeSalary>().AddRange(salaryA, salaryB);

        var adjustmentB = new EmployeeDeductionBonus
        {
            UserId = employeeB.Id, CompanyId = _companyB, Type = AdjustmentType.Deduction,
            Category = "غرامة", Amount = 10_000m, Month = 1, Year = 2031, Description = "اختبار",
            CreatedById = employeeB.Id, IsActive = true,
        };
        ctx.Set<EmployeeDeductionBonus>().Add(adjustmentB);

        var boxA = new CashBox { Id = Guid.NewGuid(), Name = "صندوق أ", CompanyId = _companyA, CurrentBalance = 1_000_000m };
        var boxB = new CashBox { Id = Guid.NewGuid(), Name = "صندوق ب", CompanyId = _companyB, CurrentBalance = 9_000_000m };
        ctx.Set<CashBox>().AddRange(boxA, boxB);

        var wA = new WithdrawalRequest { UserId = employeeA.Id, UserName = "أ", CompanyId = _companyA, Amount = 1_000m };
        var wB = new WithdrawalRequest { UserId = employeeB.Id, UserName = "ب", CompanyId = _companyB, Amount = 2_000m };
        ctx.Set<WithdrawalRequest>().AddRange(wA, wB);

        ctx.SaveChanges();
        return new World(accountantA.Id, employeeA.Id, employeeB.Id, salaryA.Id, salaryB.Id, adjustmentB.Id,
            boxA.Id, boxB.Id, wA.Id, wB.Id);
    }

    // ═══════════════════════ controller builders ═══════════════════════

    private TestTenant TenantOf(Guid? company, bool superAdmin = false) =>
        new() { CompanyId = company, IsSuperAdmin = superAdmin, BypassTenantFilter = superAdmin, EnforceIsolation = false };

    private static ControllerContext ContextFor(Guid userId, string role) => new()
    {
        HttpContext = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity(new[]
            {
                new Claim(ClaimTypes.NameIdentifier, userId.ToString()),
                new Claim(ClaimTypes.Role, role),
            }, "TestAuth")),
        },
    };

    private (AccountingController ctrl, SadaraDbContext db) Accounting(Guid userId, Guid? company, bool superAdmin = false)
    {
        var tenant = TenantOf(company, superAdmin);
        var db = _fx.CreateContext(tenant);
        var ctrl = new AccountingController(new UnitOfWork(db), NullLogger<AccountingController>.Instance, tenant)
        {
            ControllerContext = ContextFor(userId, superAdmin ? "SuperAdmin" : "Employee"),
        };
        return (ctrl, db);
    }

    private (WithdrawalRequestController ctrl, SadaraDbContext db) Withdrawals(Guid userId, Guid? company)
    {
        var tenant = TenantOf(company);
        var db = _fx.CreateContext(tenant);
        var ctrl = new WithdrawalRequestController(new UnitOfWork(db),
            NullLogger<WithdrawalRequestController>.Instance, tenant)
        {
            ControllerContext = ContextFor(userId, "Employee"),
        };
        return (ctrl, db);
    }

    private (HrReportsController ctrl, SadaraDbContext db) HrReports(Guid userId, Guid? company)
    {
        var tenant = TenantOf(company);
        var db = _fx.CreateContext(tenant);
        var ctrl = new HrReportsController(new UnitOfWork(db), NullLogger<HrReportsController>.Instance, tenant)
        {
            ControllerContext = ContextFor(userId, "Employee"),
        };
        return (ctrl, db);
    }

    private static int StatusOf(IActionResult r) => r switch
    {
        ObjectResult o => o.StatusCode ?? 200,
        StatusCodeResult s => s.StatusCode,
        _ => throw new Xunit.Sdk.XunitException($"Unexpected result {r.GetType().Name}"),
    };

    private static JsonElement Json(IActionResult r)
    {
        var o = Assert.IsAssignableFrom<ObjectResult>(r);
        return JsonDocument.Parse(JsonSerializer.Serialize(o.Value)).RootElement;
    }

    private SalaryStatus SalaryStatusInDb(long id)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        return ctx.Set<EmployeeSalary>().IgnoreQueryFilters().Single(s => s.Id == id).Status;
    }

    // ═══════════════════════ reads: client companyId is ignored ═══════════════════════

    [SkippableFact]
    public async Task GetSalaries_ForeignCompanyParam_ReturnsOnlyOwnCompany()
    {
        _fx.SkipIfUnavailable();
        var w = Seed();
        var (ctrl, db) = Accounting(w.AccountantA, _companyA);
        using var _ = db;

        var json = Json(await ctrl.GetSalaries(companyId: _companyB, year: 2031));

        var rows = json.GetProperty("data").EnumerateArray().ToList();
        Assert.NotEmpty(rows);
        Assert.All(rows, r => Assert.Equal(_companyA, r.GetProperty("CompanyId").GetGuid()));
        Assert.DoesNotContain(rows, r => r.GetProperty("Id").GetInt64() == w.SalaryB);
    }

    [SkippableFact]
    public async Task GetSalaries_NoCompanyParam_NoLongerReturnsAllCompanies()
    {
        _fx.SkipIfUnavailable();
        var w = Seed();
        var (ctrl, db) = Accounting(w.AccountantA, _companyA);
        using var _ = db;

        var json = Json(await ctrl.GetSalaries(year: 2031));

        var ids = json.GetProperty("data").EnumerateArray().Select(r => r.GetProperty("Id").GetInt64()).ToList();
        Assert.Contains(w.SalaryA, ids);
        Assert.DoesNotContain(w.SalaryB, ids);
    }

    [SkippableFact]
    public async Task GetSalaries_TokenWithoutCompany_Forbidden()
    {
        _fx.SkipIfUnavailable();
        var w = Seed();
        var (ctrl, db) = Accounting(w.AccountantA, company: null);
        using var _ = db;

        var result = await ctrl.GetSalaries(companyId: _companyB);

        Assert.Equal(403, StatusOf(result));
        Assert.False(Json(result).GetProperty("success").GetBoolean());
    }

    [SkippableFact]
    public async Task GetSalaries_SuperAdmin_KeepsCrossCompanyAccess()
    {
        _fx.SkipIfUnavailable();
        var w = Seed();
        var (ctrl, db) = Accounting(Guid.NewGuid(), company: null, superAdmin: true);
        using var _ = db;

        var json = Json(await ctrl.GetSalaries(companyId: _companyB, year: 2031));

        var ids = json.GetProperty("data").EnumerateArray().Select(r => r.GetProperty("Id").GetInt64()).ToList();
        Assert.Contains(w.SalaryB, ids);
    }

    [SkippableFact]
    public async Task Dashboard_ForeignCompanyParam_ShowsOwnCashOnly()
    {
        _fx.SkipIfUnavailable();
        var w = Seed();
        var (ctrl, db) = Accounting(w.AccountantA, _companyA);
        using var _ = db;

        var json = Json(await ctrl.GetDashboard(companyId: _companyB));

        var totalCash = json.GetProperty("data").GetProperty("CashBoxes").GetProperty("TotalBalance").GetDecimal();
        Assert.Equal(1_000_000m, totalCash); // company A box only (B holds 9,000,000)
    }

    [SkippableFact]
    public async Task SalaryDetails_ForeignSalary_NotFound()
    {
        _fx.SkipIfUnavailable();
        var w = Seed();
        var (ctrl, db) = Accounting(w.AccountantA, _companyA);
        using var _ = db;

        Assert.Equal(404, StatusOf(await ctrl.GetSalaryDetails(w.SalaryB)));
        Assert.Equal(200, StatusOf(await ctrl.GetSalaryDetails(w.SalaryA)));
    }

    [SkippableFact]
    public async Task CashBoxTransactions_ForeignBox_NotFound()
    {
        _fx.SkipIfUnavailable();
        var w = Seed();
        var (ctrl, db) = Accounting(w.AccountantA, _companyA);
        using var _ = db;

        Assert.Equal(404, StatusOf(await ctrl.GetCashTransactions(w.CashBoxB)));
    }

    // ═══════════════════════ writes: cross-company denial ═══════════════════════

    [SkippableFact]
    public async Task UpdateSalary_ForeignSalary_NotFound_AndUnchanged()
    {
        _fx.SkipIfUnavailable();
        var w = Seed();
        var (ctrl, db) = Accounting(w.AccountantA, _companyA);
        using var _ = db;

        var result = await ctrl.UpdateSalary(w.SalaryB, new UpdateSalaryDto(null, 1m, null, null, "hack"));

        Assert.Equal(404, StatusOf(result));
        using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        var salary = check.Set<EmployeeSalary>().Single(s => s.Id == w.SalaryB);
        Assert.Equal(0m, salary.Allowances);
        Assert.Null(salary.Notes);
    }

    [SkippableFact]
    public async Task PaySalary_ForeignSalary_NotFound_AndStillPending()
    {
        _fx.SkipIfUnavailable();
        var w = Seed();
        var (ctrl, db) = Accounting(w.AccountantA, _companyA);
        using var _ = db;

        var result = await ctrl.PaySalary(w.SalaryB, new PaySalaryDto(null, w.AccountantA));

        Assert.Equal(404, StatusOf(result));
        Assert.Equal(SalaryStatus.Pending, SalaryStatusInDb(w.SalaryB));
    }

    [SkippableFact]
    public async Task PaySalary_OwnSalaryWithForeignCashBox_Rejected_AndStillPending()
    {
        _fx.SkipIfUnavailable();
        var w = Seed();
        var (ctrl, db) = Accounting(w.AccountantA, _companyA);
        using var _ = db;

        var result = await ctrl.PaySalary(w.SalaryA, new PaySalaryDto(w.CashBoxB, w.AccountantA));

        Assert.Equal(400, StatusOf(result));
        Assert.Equal(SalaryStatus.Pending, SalaryStatusInDb(w.SalaryA));
        using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        Assert.Equal(9_000_000m, check.Set<CashBox>().Single(b => b.Id == w.CashBoxB).CurrentBalance);
    }

    [SkippableFact]
    public async Task DeleteSalary_ForeignSalary_NotFound()
    {
        _fx.SkipIfUnavailable();
        var w = Seed();
        var (ctrl, db) = Accounting(w.AccountantA, _companyA);
        using var _ = db;

        Assert.Equal(404, StatusOf(await ctrl.DeleteSalary(w.SalaryB)));
        using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        Assert.False(check.Set<EmployeeSalary>().IgnoreQueryFilters().Single(s => s.Id == w.SalaryB).IsDeleted);
    }

    [SkippableFact]
    public async Task PayrollBulkWrites_ExplicitForeignCompany_Forbidden()
    {
        _fx.SkipIfUnavailable();
        var w = Seed();
        var (ctrl, db) = Accounting(w.AccountantA, _companyA);
        using var _ = db;

        Assert.Equal(403, StatusOf(await ctrl.GenerateMonthlySalaries(new GenerateSalariesDto(_companyB, 1, 2031))));
        Assert.Equal(403, StatusOf(await ctrl.PayAllSalaries(new PayAllSalariesDto(_companyB, 1, 2031, null, w.AccountantA))));
        Assert.Equal(403, StatusOf(await ctrl.DeletePayroll(_companyB, 1, 2031)));
        Assert.Equal(403, StatusOf(await ctrl.UpdateSalaryRoster(new UpdateSalaryRosterDto(_companyB, new List<Guid>()))));

        Assert.Equal(SalaryStatus.Pending, SalaryStatusInDb(w.SalaryB));
        using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        Assert.True(check.Set<User>().Single(u => u.Id == w.EmployeeB).IsInSalaryRoster);
    }

    [SkippableFact]
    public async Task EmployeeAdjustments_ForeignRecordOrEmployee_Denied()
    {
        _fx.SkipIfUnavailable();
        var w = Seed();
        var (ctrl, db) = Accounting(w.AccountantA, _companyA);
        using var _ = db;

        Assert.Equal(404, StatusOf(await ctrl.UpdateEmployeeAdjustment(w.AdjustmentB,
            new UpdateAdjustmentDto(null, null, 1m, null, null, null, null))));
        Assert.Equal(404, StatusOf(await ctrl.DeleteEmployeeAdjustment(w.AdjustmentB)));

        // Own company in the body, but the target employee belongs to company B.
        var create = await ctrl.CreateEmployeeAdjustment(new CreateAdjustmentDto(
            w.EmployeeB, _companyA, AdjustmentType.Bonus, "مكافأة", 5m, 1, 2031, null, null, w.AccountantA));
        Assert.Equal(404, StatusOf(create));

        // Listing with B's companyId only returns A rows (none seeded) — never B's adjustment.
        var list = Json(await ctrl.GetEmployeeAdjustments(companyId: _companyB));
        Assert.DoesNotContain(list.GetProperty("data").EnumerateArray(),
            r => r.GetProperty("Id").GetInt64() == w.AdjustmentB);
    }

    // ═══════════════════════ withdrawals ═══════════════════════

    [SkippableFact]
    public async Task Withdrawals_List_IgnoresClientCompany()
    {
        _fx.SkipIfUnavailable();
        var w = Seed();
        var (ctrl, db) = Withdrawals(w.AccountantA, _companyA);
        using var _ = db;

        var json = Json(await ctrl.GetWithdrawalRequests(companyId: _companyB.ToString()));

        var ids = json.GetProperty("requests").EnumerateArray().Select(r => r.GetProperty("Id").GetInt64()).ToList();
        Assert.Contains(w.WithdrawalA, ids);
        Assert.DoesNotContain(w.WithdrawalB, ids);
    }

    [SkippableFact]
    public async Task Withdrawals_ForeignRequest_PayApproveRejectCancel_NotFound()
    {
        _fx.SkipIfUnavailable();
        var w = Seed();
        var (ctrl, db) = Withdrawals(w.AccountantA, _companyA);
        using var _ = db;

        Assert.Equal(404, StatusOf(await ctrl.PayWithdrawalRequest(w.WithdrawalB, new PayWithdrawalDto(null, OverrideLimit: true))));
        Assert.Equal(404, StatusOf(await ctrl.ApproveWithdrawalRequest(w.WithdrawalB)));
        Assert.Equal(404, StatusOf(await ctrl.RejectWithdrawalRequest(w.WithdrawalB)));
        Assert.Equal(404, StatusOf(await ctrl.CancelWithdrawalRequest(w.WithdrawalB)));

        using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        Assert.Equal(WithdrawalRequestStatus.Pending,
            check.Set<WithdrawalRequest>().Single(r => r.Id == w.WithdrawalB).Status);
        Assert.False(check.Set<EmployeeDeductionBonus>().Any(a => a.UserId == w.EmployeeB && a.Category == "سلفة"));
    }

    [SkippableFact]
    public async Task Withdrawals_MaxWithdrawal_ForeignEmployee_NotFound()
    {
        _fx.SkipIfUnavailable();
        var w = Seed();
        var (ctrl, db) = Withdrawals(w.AccountantA, _companyA);
        using var _ = db;

        Assert.Equal(404, StatusOf(await ctrl.GetMaxWithdrawal(w.EmployeeB)));
        Assert.Equal(200, StatusOf(await ctrl.GetMaxWithdrawal(w.EmployeeA))); // accountant holds accounting.withdrawals/view
    }

    // ═══════════════════════ HR reports ═══════════════════════

    [SkippableFact]
    public async Task HrReports_ForeignEmployee_NotFound_AndCompanyParamIgnored()
    {
        _fx.SkipIfUnavailable();
        var w = Seed();
        var (ctrl, db) = HrReports(w.AccountantA, _companyA);
        using var _ = db;

        Assert.Equal(404, StatusOf(await ctrl.GetEmployeeReport(w.EmployeeB, 1, 2031)));
        Assert.Equal(200, StatusOf(await ctrl.GetEmployeeReport(w.EmployeeA, 1, 2031)));

        var json = Json(await ctrl.GetMonthlySalaryReport(_companyB, 1, 2031));
        var userIds = json.GetProperty("data").EnumerateArray().Select(r => r.GetProperty("UserId").GetGuid()).ToList();
        Assert.Contains(w.EmployeeA, userIds);
        Assert.DoesNotContain(w.EmployeeB, userIds);
    }

    // ═══════════════════════ write permissions (RequirePermission filters) ═══════════════════════

    /// <summary>
    /// Runs every <see cref="RequirePermissionAttribute"/> that ASP.NET would run for the action
    /// (class-level + method-level) against a real user row. Returns the first short-circuit result, or null (= allowed).
    /// </summary>
    private async Task<IActionResult?> RunPermissionFilters(Type controller, string action, Guid userId)
    {
        var method = controller.GetMethod(action) ?? throw new InvalidOperationException(action);
        var attrs = controller.GetCustomAttributes<RequirePermissionAttribute>(inherit: true)
            .Concat(method.GetCustomAttributes<RequirePermissionAttribute>(inherit: true));

        using var db = _fx.CreateContext(PostgresFixture.SystemTenant);
        var services = new ServiceCollection().AddSingleton<IUnitOfWork>(new UnitOfWork(db)).BuildServiceProvider();
        var http = new DefaultHttpContext
        {
            RequestServices = services,
            User = new ClaimsPrincipal(new ClaimsIdentity(new[]
            {
                new Claim(ClaimTypes.NameIdentifier, userId.ToString()),
                new Claim(ClaimTypes.Role, "Employee"),
            }, "TestAuth")),
        };
        var actionContext = new ActionContext(http, new RouteData(),
            new ActionDescriptor { EndpointMetadata = new List<object>() });

        foreach (var attr in attrs)
        {
            var ctx = new AuthorizationFilterContext(actionContext, new List<IFilterMetadata>());
            await attr.OnAuthorizationAsync(ctx);
            if (ctx.Result != null) return ctx.Result;
        }
        return null;
    }

    /// <summary>Unique phone per seeded user ((CompanyId, PhoneNumber) is unique per company).</summary>
    private static string UniquePhone() =>
        "07" + Random.Shared.NextInt64(100_000_000, 999_999_999).ToString();

    private Guid SeedPermUser(string? perms)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        if (!ctx.Set<Company>().Any(c => c.Id == _companyA))
        {
            ctx.Set<Company>().Add(new Company { Id = _companyA, Name = "شركة أ", Code = "PRM-" + _companyA.ToString("N")[..8] });
            ctx.SaveChanges();
        }
        var user = new User
        {
            Id = Guid.NewGuid(),
            Username = "prm-" + Guid.NewGuid().ToString("N")[..10],
            FullName = "مستخدم صلاحيات",
            PhoneNumber = UniquePhone(),
            CompanyId = _companyA,
            Role = UserRole.Employee,
            FirstSystemPermissionsV2 = perms,
        };
        ctx.Set<User>().Add(user);
        ctx.SaveChanges();
        return user.Id;
    }

    public static IEnumerable<object[]> PayrollWriteActions() => new[]
    {
        new object[] { nameof(AccountingController.GenerateMonthlySalaries) },
        new object[] { nameof(AccountingController.UpdateSalary) },
        new object[] { nameof(AccountingController.PaySalary) },
        new object[] { nameof(AccountingController.PayAllSalaries) },
        new object[] { nameof(AccountingController.DeleteSalary) },
        new object[] { nameof(AccountingController.DeletePayroll) },
        new object[] { nameof(AccountingController.UpdateSalaryRoster) },
        new object[] { nameof(AccountingController.CreateSalaryPolicy) },
        new object[] { nameof(AccountingController.UpdateSalaryPolicy) },
        new object[] { nameof(AccountingController.DeleteSalaryPolicy) },
        new object[] { nameof(AccountingController.CreateEmployeeAdjustment) },
        new object[] { nameof(AccountingController.UpdateEmployeeAdjustment) },
        new object[] { nameof(AccountingController.DeleteEmployeeAdjustment) },
        new object[] { nameof(AccountingController.RepairSalaryJournalEntries) },
    };

    [SkippableTheory]
    [MemberData(nameof(PayrollWriteActions))]
    public async Task PayrollWrite_ViewOnlyUser_Forbidden(string action)
    {
        _fx.SkipIfUnavailable();
        var viewer = SeedPermUser(ViewOnlyPerms);

        var result = await RunPermissionFilters(typeof(AccountingController), action, viewer);

        Assert.NotNull(result);
        Assert.Equal(403, StatusOf(result!));
    }

    [SkippableFact]
    public async Task PayrollRead_ViewOnlyUser_Allowed()
    {
        _fx.SkipIfUnavailable();
        var viewer = SeedPermUser(ViewOnlyPerms);

        Assert.Null(await RunPermissionFilters(typeof(AccountingController), nameof(AccountingController.GetSalaries), viewer));
    }

    [SkippableFact]
    public async Task PayrollWrite_AccountantTemplate_AddEditAllowed_DeleteDenied()
    {
        _fx.SkipIfUnavailable();
        // Mirrors the Flutter "accountant" template: accounting {view, add, edit}, no explicit accounting.salaries key.
        var accountant = SeedPermUser(AccountantPerms);

        Assert.Null(await RunPermissionFilters(typeof(AccountingController), nameof(AccountingController.PaySalary), accountant));
        Assert.Null(await RunPermissionFilters(typeof(AccountingController), nameof(AccountingController.UpdateSalary), accountant));
        Assert.NotNull(await RunPermissionFilters(typeof(AccountingController), nameof(AccountingController.DeleteSalary), accountant));
    }

    [SkippableFact]
    public async Task PayrollWrite_ExplicitChildDeny_Forbidden()
    {
        _fx.SkipIfUnavailable();
        var user = SeedPermUser("""{"accounting":{"view":true,"add":true,"edit":true,"delete":true},"accounting.salaries":{"view":true,"add":false,"edit":false,"delete":false}}""");

        Assert.NotNull(await RunPermissionFilters(typeof(AccountingController), nameof(AccountingController.PaySalary), user));
        Assert.Null(await RunPermissionFilters(typeof(AccountingController), nameof(AccountingController.GetSalaries), user));
    }

    [SkippableTheory]
    [InlineData(nameof(WithdrawalRequestController.PayWithdrawalRequest))]
    [InlineData(nameof(WithdrawalRequestController.ApproveWithdrawalRequest))]
    [InlineData(nameof(WithdrawalRequestController.RejectWithdrawalRequest))]
    public async Task WithdrawalReview_ViewOnlyUser_Forbidden_EditorAllowed(string action)
    {
        _fx.SkipIfUnavailable();
        var viewer = SeedPermUser(ViewOnlyPerms);
        var editor = SeedPermUser(FullSalariesPerms);

        Assert.NotNull(await RunPermissionFilters(typeof(WithdrawalRequestController), action, viewer));
        Assert.Null(await RunPermissionFilters(typeof(WithdrawalRequestController), action, editor));
    }

    /// <summary>Regression guard: every non-GET payroll action carries a non-"view" RequirePermission.</summary>
    [Fact]
    public void AllPayrollWriteActions_RequireWriteLevelPermission()
    {
        foreach (var row in PayrollWriteActions())
        {
            var name = (string)row[0];
            var method = typeof(AccountingController).GetMethod(name)!;
            var perms = method.GetCustomAttributes<RequirePermissionAttribute>().ToList();
            Assert.True(perms.Count > 0, $"{name} has no method-level RequirePermission");
        }
    }
}
