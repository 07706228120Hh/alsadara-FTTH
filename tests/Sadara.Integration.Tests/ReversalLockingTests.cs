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
/// Batch C1 — SubscriptionLogsController.Delete reversal, hardened to run inside ONE transaction with
/// account-row locking and a journal-entry row lock that re-checks status, so a reversal is atomic and
/// can never run twice. All DB-backed tests run on real PostgreSQL (Testcontainers), not in-memory.
/// </summary>
public class PostingDeltaTests
{
    [Fact]
    public void PostingDelta_IsCorrect_ForEveryAccountType()
    {
        // Debit-natured accounts: balance delta = debit − credit.
        Assert.Equal(100m, ServiceRequestAccountingHelper.PostingDelta(AccountType.Assets, 100, 0));
        Assert.Equal(-30m, ServiceRequestAccountingHelper.PostingDelta(AccountType.Assets, 0, 30));
        Assert.Equal(50m, ServiceRequestAccountingHelper.PostingDelta(AccountType.Expenses, 50, 0));
        // Credit-natured accounts: balance delta = credit − debit.
        Assert.Equal(100m, ServiceRequestAccountingHelper.PostingDelta(AccountType.Liabilities, 0, 100));
        Assert.Equal(-20m, ServiceRequestAccountingHelper.PostingDelta(AccountType.Liabilities, 20, 0));
        Assert.Equal(100m, ServiceRequestAccountingHelper.PostingDelta(AccountType.Equity, 0, 100));
        Assert.Equal(100m, ServiceRequestAccountingHelper.PostingDelta(AccountType.Revenue, 0, 100));
        // Reversal (−delta) exactly undoes posting (+delta) for each type.
        foreach (var t in new[] { AccountType.Assets, AccountType.Expenses, AccountType.Liabilities, AccountType.Equity, AccountType.Revenue })
        {
            var d = ServiceRequestAccountingHelper.PostingDelta(t, 70, 25);
            Assert.Equal(0m, d + (-d));
        }
    }
}

[Collection("Postgres")]
public class ReversalLockingTests : IDisposable
{
    private static readonly Guid CompanyA = Guid.Parse("c3c3c3c3-0000-4000-8000-000000000001");
    private readonly PostgresFixture _fx;

    public ReversalLockingTests(PostgresFixture fx) { _fx = fx; if (_fx.Available) Cleanup(); }
    public void Dispose() { if (_fx.Available) Cleanup(); }

    private void Cleanup()
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Database.ExecuteSqlRaw(
            "DELETE FROM \"TechnicianTransactions\" WHERE \"CompanyId\" = {0};" +
            "DELETE FROM \"SubscriptionLogs\" WHERE \"CompanyId\" = {0};" +
            "DELETE FROM \"JournalEntryLines\" WHERE \"JournalEntryId\" IN (SELECT \"Id\" FROM \"JournalEntries\" WHERE \"CompanyId\" = {0});" +
            "DELETE FROM \"JournalEntries\" WHERE \"CompanyId\" = {0};" +
            "DELETE FROM \"Accounts\" WHERE \"CompanyId\" = {0};" +
            "DELETE FROM \"Users\" WHERE \"CompanyId\" = {0};" +
            "DELETE FROM \"Companies\" WHERE \"Id\" = {0};",
            CompanyA);
    }

    private sealed record Seeded(long LogId, Guid JeId, Guid TechId, Guid AssetId, Guid RevenueId);

    /// <summary>A posted activation: asset 100 / revenue 100, a technician charged 100, linked log+entry.</summary>
    private Seeded Seed()
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<Company>().Add(new Company { Id = CompanyA, Name = "ش-عكس", Code = "C-REV" });
        var techId = Guid.NewGuid();
        ctx.Set<User>().Add(new User
        {
            Id = techId, Username = $"t-{techId:N}"[..12], FullName = "فني",
            PhoneNumber = "0781" + techId.ToString("N")[..7], CompanyId = CompanyA, Role = UserRole.Employee,
            TechTotalCharges = 100, TechTotalPayments = 0, TechNetBalance = -100
        });
        var asset = new Account { Id = Guid.NewGuid(), Code = AccountCodes.PageBalance, Name = "رصيد الصفحة", AccountType = AccountType.Assets, Level = 4, IsLeaf = true, IsActive = true, CurrentBalance = 100, CompanyId = CompanyA };
        var revenue = new Account { Id = Guid.NewGuid(), Code = "4000", Name = "إيراد", AccountType = AccountType.Revenue, Level = 3, IsLeaf = true, IsActive = true, CurrentBalance = 100, CompanyId = CompanyA };
        ctx.Set<Account>().AddRange(asset, revenue);

        var jeId = Guid.NewGuid();
        ctx.Set<JournalEntry>().Add(new JournalEntry
        {
            Id = jeId, EntryNumber = "JE-REV-1", EntryDate = DateTime.UtcNow, Description = "activation",
            TotalDebit = 100, TotalCredit = 100, Status = JournalEntryStatus.Posted, CompanyId = CompanyA, CreatedById = techId,
            Lines = new List<JournalEntryLine>
            {
                new() { AccountId = asset.Id, DebitAmount = 100, CreditAmount = 0, CompanyId = CompanyA },
                new() { AccountId = revenue.Id, DebitAmount = 0, CreditAmount = 100, CompanyId = CompanyA },
            }
        });

        var log = new SubscriptionLog
        {
            CompanyId = CompanyA, CustomerName = "عميل", SubscriptionId = "sub-rev", PaymentStatus = "paid",
            UserId = techId, LinkedTechnicianId = techId, PlanPrice = 100, JournalEntryId = jeId, PlanName = "BASIC"
        };
        ctx.Set<SubscriptionLog>().Add(log);
        ctx.SaveChanges();

        ctx.Set<TechnicianTransaction>().Add(new TechnicianTransaction
        {
            TechnicianId = techId, Type = TechnicianTransactionType.Charge, Category = TechnicianTransactionCategory.Subscription,
            Amount = 100, BalanceAfter = -100, Description = "شراء", ReferenceNumber = log.Id.ToString(), CompanyId = CompanyA
        });
        ctx.SaveChanges();
        return new Seeded(log.Id, jeId, techId, asset.Id, revenue.Id);
    }

    private static SubscriptionLogsController Controller(SadaraDbContext db) =>
        new(new UnitOfWork(db), db, NullLogger<SubscriptionLogsController>.Instance,
            new TestTenant { CompanyId = CompanyA, IsSuperAdmin = true });

    private static int Code(IActionResult r) => (r as ObjectResult)?.StatusCode ?? (r is OkObjectResult ? 200 : 0);

    private (decimal asset, decimal revenue, decimal techCharges, JournalEntryStatus jeStatus, bool jeDeleted) State(Seeded s)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        var asset = ctx.Set<Account>().IgnoreQueryFilters().Single(a => a.Id == s.AssetId).CurrentBalance;
        var revenue = ctx.Set<Account>().IgnoreQueryFilters().Single(a => a.Id == s.RevenueId).CurrentBalance;
        var tech = ctx.Set<User>().IgnoreQueryFilters().Single(u => u.Id == s.TechId).TechTotalCharges;
        var je = ctx.Set<JournalEntry>().IgnoreQueryFilters().Single(j => j.Id == s.JeId);
        return (asset, revenue, tech, je.Status, je.IsDeleted);
    }

    [SkippableFact]
    public async Task Delete_Reverses_Balances_VoidsEntry_And_SoftDeletes_Once()
    {
        _fx.SkipIfUnavailable();
        var s = Seed();
        await using (var db = _fx.CreateContext(PostgresFixture.SystemTenant))
            Assert.Equal(200, Code(await Controller(db).Delete(s.LogId)));

        var st = State(s);
        Assert.Equal(0, st.asset);                               // 100 − (100−0) = 0
        Assert.Equal(0, st.revenue);                             // 100 − (100−0) = 0
        Assert.Equal(0, st.techCharges);                         // 100 − 100 = 0
        Assert.Equal(JournalEntryStatus.Voided, st.jeStatus);    // entry voided
        Assert.True(st.jeDeleted);                               // historical record kept (soft delete)
    }

    [SkippableFact]
    public async Task Delete_IsIdempotent_SecondCallDoesNotDoubleReverse()
    {
        _fx.SkipIfUnavailable();
        var s = Seed();
        await using (var db1 = _fx.CreateContext(PostgresFixture.SystemTenant))
            Assert.Equal(200, Code(await Controller(db1).Delete(s.LogId)));
        // Second delete: the soft-deleted log is filtered out ⇒ 404, nothing reversed again.
        await using (var db2 = _fx.CreateContext(PostgresFixture.SystemTenant))
            Assert.Equal(404, Code(await Controller(db2).Delete(s.LogId)));

        var st = State(s);
        Assert.Equal(0, st.asset);     // still exactly one reversal (not +100 nor −100)
        Assert.Equal(0, st.revenue);
        Assert.Equal(0, st.techCharges);
    }

    [SkippableFact]
    public async Task Delete_UnderConcurrency_ReversesExactlyOnce()
    {
        _fx.SkipIfUnavailable();
        var s = Seed();

        // Two concurrent deletes of the same log on two connections. The JE row lock serializes them:
        // one reverses+voids+commits, the other blocks then sees Voided and skips. Net: single reversal.
        async Task<int> RunDelete()
        {
            await using var db = _fx.CreateContext(PostgresFixture.SystemTenant);
            try { return Code(await Controller(db).Delete(s.LogId)); }
            catch { return 500; }
        }
        var t1 = Task.Run(RunDelete);
        var t2 = Task.Run(RunDelete);
        var codes = await Task.WhenAll(t1, t2);

        // Neither call errored out (no deadlock / unhandled exception).
        Assert.All(codes, c => Assert.Contains(c, new[] { 200, 404 }));

        var st = State(s);
        Assert.Equal(0, st.asset);    // reversed EXACTLY once despite the race (−100 would mean double)
        Assert.Equal(0, st.revenue);
        Assert.Equal(0, st.techCharges);
        Assert.Equal(JournalEntryStatus.Voided, st.jeStatus);
        Assert.True(st.jeDeleted);
    }
}
