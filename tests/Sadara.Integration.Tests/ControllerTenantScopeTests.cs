using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Sadara.API.Controllers;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Repositories;
using Sadara.Integration.Tests.Support;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// Leave / withdrawal / dashboard controllers must scope by the company in the token, never by a
/// companyId sent by the client. The DbContext runs with the global isolation filter OFF, so these
/// tests prove the explicit controller-level scope on its own. Skipped when Docker is unavailable.
/// </summary>
[Collection("Postgres")]
public class ControllerTenantScopeTests : IDisposable
{
    private static readonly Guid CompanyA = Guid.Parse("a2a2a2a2-0000-4000-8000-000000000001");
    private static readonly Guid CompanyB = Guid.Parse("b2b2b2b2-0000-4000-8000-000000000002");

    private readonly PostgresFixture _fx;

    public ControllerTenantScopeTests(PostgresFixture fx)
    {
        _fx = fx;
        if (_fx.Available) Cleanup();
    }

    public void Dispose()
    {
        if (_fx.Available) Cleanup();
    }

    private void Cleanup()
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Database.ExecuteSqlRaw(
            "DELETE FROM \"LeaveBalances\" WHERE \"CompanyId\" IN ({0}, {1});" +
            "DELETE FROM \"LeaveRequests\" WHERE \"CompanyId\" IN ({0}, {1});" +
            "DELETE FROM \"WithdrawalRequests\" WHERE \"CompanyId\" IN ({0}, {1});" +
            "DELETE FROM \"Users\" WHERE \"CompanyId\" IN ({0}, {1});" +
            "DELETE FROM \"Companies\" WHERE \"Id\" IN ({0}, {1});",
            CompanyA, CompanyB);
    }

    /// <summary>Company + one active admin user; returns the user id.</summary>
    private Guid Seed(Guid companyId)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<Company>().Add(new Company { Id = companyId, Name = $"شركة {companyId:N}"[..20], Code = $"C-{companyId:N}"[..10] });
        var userId = Guid.NewGuid();
        ctx.Set<User>().Add(new User
        {
            Id = userId,
            Username = $"u-{userId:N}"[..12],
            FullName = "مستخدم اختبار",
            PhoneNumber = "0771" + userId.ToString("N")[..7],
            CompanyId = companyId,
            Role = UserRole.CompanyAdmin,
            IsActive = true
        });
        ctx.SaveChanges();
        return userId;
    }

    private static T As<T>(T controller, Guid userId) where T : ControllerBase
    {
        var identity = new ClaimsIdentity(new[] { new Claim(ClaimTypes.NameIdentifier, userId.ToString()) }, "test");
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext { User = new ClaimsPrincipal(identity) }
        };
        return controller;
    }

    private static int Code(IActionResult result) => (result as ObjectResult)?.StatusCode ?? 0;

    private static JsonElement Body(IActionResult result) =>
        JsonSerializer.SerializeToElement(((ObjectResult)result).Value);

    [SkippableFact]
    public async Task Leave_IgnoresClientCompanyId_AndHidesForeignRequests()
    {
        _fx.SkipIfUnavailable();
        var userA = Seed(CompanyA);
        var userB = Seed(CompanyB);
        long ownId, foreignId;
        await using (var seed = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            LeaveRequest Request(Guid userId, Guid companyId) => new()
            {
                UserId = userId, UserName = "موظف", CompanyId = companyId, LeaveType = LeaveType.Unpaid,
                StartDate = new DateOnly(2026, 3, 1), EndDate = new DateOnly(2026, 3, 2), TotalDays = 2
            };
            var own = Request(userA, CompanyA);
            var foreign = Request(userB, CompanyB);
            seed.AddRange(own, foreign);
            await seed.SaveChangesAsync();
            ownId = own.Id;
            foreignId = foreign.Id;
        }

        await using var db = _fx.CreateContext(PostgresFixture.SystemTenant);
        var controller = As(new LeaveController(new UnitOfWork(db), NullLogger<LeaveController>.Instance,
            new TestTenant { CompanyId = CompanyA }), userA);

        var list = Body(await controller.GetLeaveRequests(null, null, CompanyB, null, null));
        var summary = Body(await controller.GetLeaveSummary(CompanyB, 2026));
        var foreignBalances = Body(await controller.GetLeaveBalances(userB, 2026));

        Assert.Equal(1, list.GetProperty("total").GetInt32());
        Assert.Equal(ownId, list.GetProperty("requests")[0].GetProperty("Id").GetInt64());
        Assert.Equal(1, summary.GetProperty("totalRequests").GetInt32());
        Assert.Equal(0, foreignBalances.GetProperty("balances").GetArrayLength());
        Assert.Equal(404, Code(await controller.GetLeaveRequest(foreignId)));
        Assert.Equal(404, Code(await controller.ApproveLeaveRequest(foreignId)));
        Assert.Equal(404, Code(await controller.RejectLeaveRequest(foreignId)));
        Assert.Equal(404, Code(await controller.CancelLeaveRequest(foreignId)));
        Assert.Equal(404, Code(await controller.SetLeaveBalance(new SetLeaveBalanceRequest(userB, 2026, (int)LeaveType.Annual, 30))));
        Assert.Equal(200, Code(await controller.BulkSetLeaveBalances(new BulkSetBalanceRequest(CompanyB, 2026, (int)LeaveType.Annual, 21))));
        Assert.Equal(200, Code(await controller.ApproveLeaveRequest(ownId)));

        await using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        var foreignRow = await check.Set<LeaveRequest>().IgnoreQueryFilters().AsNoTracking().SingleAsync(r => r.Id == foreignId);
        var balances = await check.Set<LeaveBalance>().IgnoreQueryFilters().AsNoTracking()
            .Where(b => b.CompanyId == CompanyA || b.CompanyId == CompanyB).ToListAsync();
        Assert.Equal(LeaveRequestStatus.Pending, foreignRow.Status);
        var balance = Assert.Single(balances);
        Assert.Equal(userA, balance.UserId);
        Assert.Equal(CompanyA, balance.CompanyId);
    }

    [SkippableFact]
    public async Task Withdrawal_IgnoresClientCompanyId_AndHidesForeignRequests()
    {
        _fx.SkipIfUnavailable();
        var userA = Seed(CompanyA);
        var userB = Seed(CompanyB);
        long ownId, foreignId;
        await using (var seed = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            var own = new WithdrawalRequest { UserId = userA, UserName = "موظف", CompanyId = CompanyA, Amount = 100 };
            var foreign = new WithdrawalRequest { UserId = userB, UserName = "موظف", CompanyId = CompanyB, Amount = 100 };
            seed.AddRange(own, foreign);
            await seed.SaveChangesAsync();
            ownId = own.Id;
            foreignId = foreign.Id;
        }

        await using var db = _fx.CreateContext(PostgresFixture.SystemTenant);
        var controller = As(new WithdrawalRequestController(new UnitOfWork(db),
            NullLogger<WithdrawalRequestController>.Instance, new TestTenant { CompanyId = CompanyA }), userA);

        var list = Body(await controller.GetWithdrawalRequests(companyId: CompanyB.ToString()));

        Assert.Equal(1, list.GetProperty("total").GetInt32());
        Assert.Equal(ownId, list.GetProperty("requests")[0].GetProperty("Id").GetInt64());
        Assert.Equal(404, Code(await controller.ApproveWithdrawalRequest(foreignId)));
        Assert.Equal(404, Code(await controller.PayWithdrawalRequest(foreignId, new PayWithdrawalDto(null, true))));
        Assert.Equal(404, Code(await controller.RejectWithdrawalRequest(foreignId)));
        Assert.Equal(404, Code(await controller.CancelWithdrawalRequest(foreignId)));
        Assert.Equal(404, Code(await controller.GetMaxWithdrawal(userB)));
        Assert.Equal(200, Code(await controller.GetMaxWithdrawal(userA)));
        Assert.Equal(200, Code(await controller.ApproveWithdrawalRequest(ownId)));

        await using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        var rows = await check.Set<WithdrawalRequest>().IgnoreQueryFilters().AsNoTracking()
            .Where(r => r.Id == ownId || r.Id == foreignId).ToDictionaryAsync(r => r.Id);
        Assert.Equal(WithdrawalRequestStatus.Pending, rows[foreignId].Status);
        Assert.Equal(WithdrawalRequestStatus.Approved, rows[ownId].Status);
    }

    [SkippableFact]
    public async Task Dashboard_CountsAndListsOnlyTheCallersUsers()
    {
        _fx.SkipIfUnavailable();
        var userA = Seed(CompanyA);
        Seed(CompanyB);

        await using var db = _fx.CreateContext(PostgresFixture.SystemTenant);
        var controller = As(new DashboardController(new UnitOfWork(db), new TestTenant { CompanyId = CompanyA }), userA);
        var noCompany = As(new DashboardController(new UnitOfWork(db), new TestTenant()), userA);

        var stats = Body(await controller.GetStats()).GetProperty("data");
        var recent = Body(await controller.GetRecentUsers(50)).GetProperty("data");
        var statsWithoutCompany = Body(await noCompany.GetStats()).GetProperty("data");

        Assert.Equal(1, stats.GetProperty("totalUsers").GetInt32());
        Assert.Equal(1, recent.GetArrayLength());
        Assert.Equal(userA, recent[0].GetProperty("Id").GetGuid());
        Assert.Equal(0, statsWithoutCompany.GetProperty("totalUsers").GetInt32());
    }
}
