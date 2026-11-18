using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Sadara.API.Constants;
using Sadara.API.Controllers;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Data;
using Sadara.Infrastructure.Repositories;
using Sadara.Integration.Tests.Support;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// Hardening guards for the accounting system:
/// (1) <see cref="ServiceRequestAccountingHelper.AssertBalanced"/> rejects any unbalanced set of lines
///     (the central guard now applied to every direct posting path).
/// (2) recalculate-balances is scoped to the caller's company and never recomputes another tenant's
///     accounts (the cross-tenant maintenance-endpoint fix).
/// </summary>
public class AccountingBalanceGuardTests
{
    private static (Guid, decimal, decimal, string?) L(decimal d, decimal c) => (Guid.NewGuid(), d, c, null);

    [Fact]
    public void AssertBalanced_Throws_WhenDebitNotEqualCredit()
    {
        var lines = new List<(Guid, decimal, decimal, string?)> { L(100, 0), L(0, 90) }; // gap 10
        var ex = Assert.Throws<InvalidOperationException>(() =>
            ServiceRequestAccountingHelper.AssertBalanced(lines, JournalReferenceType.FtthSubscription, "ref-1"));
        Assert.Contains("غير متوازن", ex.Message);
    }

    [Fact]
    public void AssertBalanced_Passes_WhenBalanced_WithinTolerance()
    {
        var lines = new List<(Guid, decimal, decimal, string?)> { L(100.000m, 0), L(0, 99.9995m), L(0, 0.0005m) };
        // no throw
        ServiceRequestAccountingHelper.AssertBalanced(lines, JournalReferenceType.Manual, "ref-2");
    }

    [Fact]
    public void AssertBalanced_RespectsToleranceBoundary_At_0_001()
    {
        // gap 0.0009 (≤ 0.001) passes
        ServiceRequestAccountingHelper.AssertBalanced(
            new List<(Guid, decimal, decimal, string?)> { L(100m, 0), L(0, 99.9991m) },
            JournalReferenceType.Manual, "tol-pass");
        // gap 0.0011 (> 0.001) throws
        Assert.Throws<InvalidOperationException>(() =>
            ServiceRequestAccountingHelper.AssertBalanced(
                new List<(Guid, decimal, decimal, string?)> { L(100m, 0), L(0, 99.9989m) },
                JournalReferenceType.Manual, "tol-throw"));
    }
}

[Collection("Postgres")]
public class RecalculateBalancesScopeTests : IDisposable
{
    private static readonly Guid CompanyA = Guid.Parse("c1c1c1c1-0000-4000-8000-000000000001");
    private static readonly Guid CompanyB = Guid.Parse("c2c2c2c2-0000-4000-8000-000000000002");

    private readonly PostgresFixture _fx;

    public RecalculateBalancesScopeTests(PostgresFixture fx)
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
        foreach (var co in new[] { CompanyA, CompanyB })
            ctx.Database.ExecuteSqlRaw(
                "DELETE FROM \"JournalEntryLines\" WHERE \"JournalEntryId\" IN (SELECT \"Id\" FROM \"JournalEntries\" WHERE \"CompanyId\" = {0});" +
                "DELETE FROM \"JournalEntries\" WHERE \"CompanyId\" = {0};" +
                "DELETE FROM \"Accounts\" WHERE \"CompanyId\" = {0};" +
                "DELETE FROM \"Users\" WHERE \"CompanyId\" = {0};" +
                "DELETE FROM \"Companies\" WHERE \"Id\" = {0};",
                co);
    }

    /// <summary>One company: an asset account whose stored balance is wrong, plus one posted entry
    /// (debit 100 asset / credit 100 revenue). After recalc the asset should read 100 and revenue 100.</summary>
    private void Seed(Guid companyId, decimal wrongAsset, decimal wrongRevenue)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<Company>().Add(new Company { Id = companyId, Name = "ش-" + companyId.ToString("N")[..4], Code = "C-" + companyId.ToString("N")[..4] });
        var userId = Guid.NewGuid();
        ctx.Set<User>().Add(new User
        {
            Id = userId, Username = $"u-{userId:N}"[..12], FullName = "مدير",
            PhoneNumber = "0781" + userId.ToString("N")[..7], CompanyId = companyId, Role = UserRole.SuperAdmin
        });

        var asset = new Account
        {
            Id = Guid.NewGuid(), Code = AccountCodes.Cash, Name = "النقد", AccountType = AccountType.Assets,
            Level = 3, IsLeaf = true, IsActive = true, CurrentBalance = wrongAsset, CompanyId = companyId
        };
        var revenue = new Account
        {
            Id = Guid.NewGuid(), Code = "4000", Name = "إيراد", AccountType = AccountType.Revenue,
            Level = 3, IsLeaf = true, IsActive = true, CurrentBalance = wrongRevenue, CompanyId = companyId
        };
        ctx.Set<Account>().AddRange(asset, revenue);

        var entry = new JournalEntry
        {
            Id = Guid.NewGuid(), EntryNumber = $"JE-TEST-{companyId.ToString("N")[..6]}", EntryDate = DateTime.UtcNow,
            Description = "test", TotalDebit = 100, TotalCredit = 100, Status = JournalEntryStatus.Posted,
            CompanyId = companyId, CreatedById = userId,
            Lines = new List<JournalEntryLine>
            {
                new() { AccountId = asset.Id, DebitAmount = 100, CreditAmount = 0, CompanyId = companyId },
                new() { AccountId = revenue.Id, DebitAmount = 0, CreditAmount = 100, CompanyId = companyId },
            }
        };
        ctx.Set<JournalEntry>().Add(entry);
        ctx.SaveChanges();
    }

    private decimal BalanceOf(Guid companyId, string code)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        return ctx.Set<Account>().IgnoreQueryFilters().Single(a => a.CompanyId == companyId && a.Code == code).CurrentBalance;
    }

    private static AccountingController Controller(SadaraDbContext db, Guid? tenantCompany, bool superAdmin) =>
        new(new UnitOfWork(db), NullLogger<AccountingController>.Instance,
            new TestTenant { CompanyId = tenantCompany, IsSuperAdmin = superAdmin });

    private static int Code(IActionResult r) => (r as ObjectResult)?.StatusCode ?? (r is OkObjectResult ? 200 : 0);

    [SkippableFact]
    public async Task Recalc_AsCompanyAdmin_FixesOwnCompanyOnly_LeavesOtherTenantUntouched()
    {
        _fx.SkipIfUnavailable();
        Seed(CompanyA, wrongAsset: 999, wrongRevenue: 0);
        Seed(CompanyB, wrongAsset: 777, wrongRevenue: 0);

        await using (var db = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            var result = await Controller(db, CompanyA, superAdmin: false).RecalculateAllBalances(companyId: null);
            Assert.Equal(200, Code(result));
        }

        // Company A corrected to the ledger values.
        Assert.Equal(100, BalanceOf(CompanyA, AccountCodes.Cash));
        Assert.Equal(100, BalanceOf(CompanyA, "4000"));
        // Company B left exactly as it was (no cross-tenant recompute).
        Assert.Equal(777, BalanceOf(CompanyB, AccountCodes.Cash));
        Assert.Equal(0, BalanceOf(CompanyB, "4000"));
    }

    [SkippableFact]
    public async Task Recalc_IsRejected_WhenNonSuperAdminHasNoCompany()
    {
        _fx.SkipIfUnavailable();
        await using var db = _fx.CreateContext(PostgresFixture.SystemTenant);
        var result = await Controller(db, tenantCompany: null, superAdmin: false).RecalculateAllBalances(companyId: null);
        Assert.Equal(403, Code(result));
    }
}
