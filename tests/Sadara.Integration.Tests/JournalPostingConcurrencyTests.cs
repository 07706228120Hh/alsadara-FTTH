using Microsoft.EntityFrameworkCore;
using Sadara.API.Controllers;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Repositories;
using Sadara.Integration.Tests.Support;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// Concurrent journal postings to the same accounts must not lose balance updates: the final
/// CurrentBalance has to equal the sum of every posted line. Skipped when Docker is unavailable.
/// </summary>
[Collection("Postgres")]
public class JournalPostingConcurrencyTests : IDisposable
{
    private static readonly Guid CompanyId = Guid.Parse("c3c3c3c3-0000-4000-8000-000000000001");

    private readonly PostgresFixture _fx;

    public JournalPostingConcurrencyTests(PostgresFixture fx)
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
            "DELETE FROM \"JournalEntryLines\" WHERE \"JournalEntryId\" IN (SELECT \"Id\" FROM \"JournalEntries\" WHERE \"CompanyId\" = {0});" +
            "DELETE FROM \"JournalEntries\" WHERE \"CompanyId\" = {0};" +
            "DELETE FROM \"Accounts\" WHERE \"CompanyId\" = {0};" +
            "DELETE FROM \"Users\" WHERE \"CompanyId\" = {0};" +
            "DELETE FROM \"Companies\" WHERE \"Id\" = {0};",
            CompanyId);
    }

    private sealed record Seeded(Guid UserId, Guid CashId, Guid RevenueId);

    private Seeded Seed(decimal cash = 0, decimal revenue = 0)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<Company>().Add(new Company { Id = CompanyId, Name = "شركة اختبار الترحيل", Code = "C-JPOST" });
        var userId = Guid.NewGuid();
        ctx.Set<User>().Add(new User
        {
            Id = userId,
            Username = $"u-{userId:N}"[..12],
            FullName = "مستخدم اختبار",
            PhoneNumber = "0772" + userId.ToString("N")[..7],
            CompanyId = CompanyId,
            Role = UserRole.CompanyAdmin
        });
        Account Leaf(string code, AccountType type, decimal balance) => new()
        {
            Id = Guid.NewGuid(), Code = code, Name = code, AccountType = type,
            Level = 1, IsLeaf = true, CurrentBalance = balance, CompanyId = CompanyId
        };
        var cashAccount = Leaf("T-CASH", AccountType.Assets, cash);
        var revenueAccount = Leaf("T-REV", AccountType.Revenue, revenue);
        ctx.AddRange(cashAccount, revenueAccount);
        ctx.SaveChanges();
        return new Seeded(userId, cashAccount.Id, revenueAccount.Id);
    }

    private static List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)> Lines(
        Seeded s, decimal amount) => new()
    {
        (s.CashId, amount, 0m, null),
        (s.RevenueId, 0m, amount, null)
    };

    private async Task<Dictionary<Guid, decimal>> Balances(Seeded s)
    {
        await using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        return await check.Set<Account>().IgnoreQueryFilters().AsNoTracking()
            .Where(a => a.Id == s.CashId || a.Id == s.RevenueId)
            .ToDictionaryAsync(a => a.Id, a => a.CurrentBalance);
    }

    [SkippableFact]
    public async Task ParallelPostings_ToTheSameAccounts_SumExactly()
    {
        _fx.SkipIfUnavailable();
        var s = Seed(cash: 1000, revenue: 0);
        const int postings = 24;
        const decimal amount = 10m;

        // Every context loads the accounts first, so all of them hold the same stale balance
        // before any posting is saved — the worst case for a read-modify-write update.
        var gate = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var tasks = Enumerable.Range(0, postings).Select(i => Task.Run(async () =>
        {
            await using var db = _fx.CreateContext(PostgresFixture.SystemTenant);
            var uow = new UnitOfWork(db);
            await uow.Accounts.GetByIdAsync(s.CashId);
            await uow.Accounts.GetByIdAsync(s.RevenueId);
            await gate.Task;
            await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
                uow, CompanyId, s.UserId, $"posting {i}", JournalReferenceType.Manual, $"t-{i}", Lines(s, amount));
        })).ToList();
        gate.SetResult();
        await Task.WhenAll(tasks);

        var balances = await Balances(s);
        Assert.Equal(1000 + postings * amount, balances[s.CashId]);
        Assert.Equal(postings * amount, balances[s.RevenueId]);

        await using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        var numbers = await check.Set<JournalEntry>().IgnoreQueryFilters().AsNoTracking()
            .Where(j => j.CompanyId == CompanyId).Select(j => j.EntryNumber).ToListAsync();
        Assert.Equal(postings, numbers.Count);
        Assert.Equal(postings, numbers.Distinct().Count());
    }

    [SkippableFact]
    public async Task Posting_KeepsTheCallersPendingBalanceChange_AndSeesOtherCommits()
    {
        _fx.SkipIfUnavailable();
        var s = Seed(cash: 100, revenue: 0);

        await using var db = _fx.CreateContext(PostgresFixture.SystemTenant);
        var uow = new UnitOfWork(db);
        var cash = (await uow.Accounts.GetByIdAsync(s.CashId))!;
        cash.CurrentBalance += 5; // caller's own unsaved change on the same tracked row

        // Another request commits a posting after this context loaded the account.
        await using (var other = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
                new UnitOfWork(other), CompanyId, s.UserId, "other", JournalReferenceType.Manual, "t-other", Lines(s, 30));
        }

        await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
            uow, CompanyId, s.UserId, "mine", JournalReferenceType.Manual, "t-mine", Lines(s, 7));

        Assert.Equal(142, cash.CurrentBalance); // 100 + 5 (pending) + 30 (other) + 7 (mine)
        var balances = await Balances(s);
        Assert.Equal(142, balances[s.CashId]);
        Assert.Equal(37, balances[s.RevenueId]);
    }

    [SkippableFact]
    public async Task Posting_InsideTheCallersTransaction_CommitsAndRollsBackWithIt()
    {
        _fx.SkipIfUnavailable();
        var s = Seed(cash: 100, revenue: 0);

        await using (var db = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            var uow = new UnitOfWork(db);
            await uow.BeginTransactionAsync();
            await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
                uow, CompanyId, s.UserId, "rolled back", JournalReferenceType.Manual, "t-rb", Lines(s, 50));
            await uow.RollbackTransactionAsync();
        }
        Assert.Equal(100, (await Balances(s))[s.CashId]);

        await using (var db = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            var uow = new UnitOfWork(db);
            await uow.BeginTransactionAsync();
            await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
                uow, CompanyId, s.UserId, "first", JournalReferenceType.Manual, "t-1", Lines(s, 20));
            await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
                uow, CompanyId, s.UserId, "second", JournalReferenceType.Manual, "t-2", Lines(s, 3));
            await uow.CommitTransactionAsync();
        }
        var balances = await Balances(s);
        Assert.Equal(123, balances[s.CashId]);
        Assert.Equal(23, balances[s.RevenueId]);
    }
}
