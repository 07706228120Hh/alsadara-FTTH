using Microsoft.EntityFrameworkCore;
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
/// Batch C2 — the shared ServiceRequestAccountingHelper.VoidJournalEntryAsync used by the service-request
/// cancel/refund paths: reverses a posted entry's balances under a row lock, voids it and soft-deletes its
/// lines, and is idempotent + concurrency-safe via a journal-entry row lock with a status re-check.
/// All tests run on real PostgreSQL (Testcontainers).
/// </summary>
[Collection("Postgres")]
public class VoidJournalEntryTests : IDisposable
{
    private static readonly Guid CompanyA = Guid.Parse("c4c4c4c4-0000-4000-8000-000000000001");
    private readonly PostgresFixture _fx;

    public VoidJournalEntryTests(PostgresFixture fx) { _fx = fx; if (_fx.Available) Cleanup(); }
    public void Dispose() { if (_fx.Available) Cleanup(); }

    private void Cleanup()
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Database.ExecuteSqlRaw(
            "DELETE FROM \"JournalEntryLines\" WHERE \"JournalEntryId\" IN (SELECT \"Id\" FROM \"JournalEntries\" WHERE \"CompanyId\" = {0});" +
            "DELETE FROM \"JournalEntries\" WHERE \"CompanyId\" = {0};" +
            "DELETE FROM \"Accounts\" WHERE \"CompanyId\" = {0};" +
            "DELETE FROM \"Users\" WHERE \"CompanyId\" = {0};" +
            "DELETE FROM \"Companies\" WHERE \"Id\" = {0};",
            CompanyA);
    }

    private sealed record Seeded(Guid JeId, Guid AssetId, Guid RevenueId);

    private Seeded Seed()
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<Company>().Add(new Company { Id = CompanyA, Name = "ش-إبطال", Code = "C-VOID" });
        var userId = Guid.NewGuid();
        ctx.Set<User>().Add(new User
        {
            Id = userId, Username = $"u-{userId:N}"[..12], FullName = "مدير",
            PhoneNumber = "0781" + userId.ToString("N")[..7], CompanyId = CompanyA, Role = UserRole.SuperAdmin
        });
        var asset = new Account { Id = Guid.NewGuid(), Code = AccountCodes.PettyCash, Name = "قاصة", AccountType = AccountType.Assets, Level = 4, IsLeaf = true, IsActive = true, CurrentBalance = 100, CompanyId = CompanyA };
        var revenue = new Account { Id = Guid.NewGuid(), Code = "4110", Name = "إيراد صيانة", AccountType = AccountType.Revenue, Level = 3, IsLeaf = true, IsActive = true, CurrentBalance = 100, CompanyId = CompanyA };
        ctx.Set<Account>().AddRange(asset, revenue);
        var jeId = Guid.NewGuid();
        ctx.Set<JournalEntry>().Add(new JournalEntry
        {
            Id = jeId, EntryNumber = "JE-VOID-1", EntryDate = DateTime.UtcNow, Description = "fee",
            TotalDebit = 100, TotalCredit = 100, Status = JournalEntryStatus.Posted, CompanyId = CompanyA, CreatedById = userId,
            Lines = new List<JournalEntryLine>
            {
                new() { AccountId = asset.Id, DebitAmount = 100, CreditAmount = 0, CompanyId = CompanyA },
                new() { AccountId = revenue.Id, DebitAmount = 0, CreditAmount = 100, CompanyId = CompanyA },
            }
        });
        ctx.SaveChanges();
        return new Seeded(jeId, asset.Id, revenue.Id);
    }

    private async Task VoidInOwnTransaction(Guid jeId)
    {
        await using var db = _fx.CreateContext(PostgresFixture.SystemTenant);
        var uow = new UnitOfWork(db);
        await uow.BeginTransactionAsync();
        try
        {
            // IgnoreQueryFilters so a second (idempotency) call can still load the now soft-deleted entry;
            // real callers instead look it up with a !IsDeleted guard and skip when it returns null.
            var je = await db.Set<JournalEntry>().IgnoreQueryFilters().Include(j => j.Lines).FirstOrDefaultAsync(j => j.Id == jeId);
            if (je != null)
                await ServiceRequestAccountingHelper.VoidJournalEntryAsync(uow, je);
            await uow.CommitTransactionAsync();
        }
        catch { if (uow.HasActiveTransaction) await uow.RollbackTransactionAsync(); throw; }
    }

    private (decimal asset, decimal revenue, JournalEntryStatus status, bool deleted, int liveLines) State(Seeded s)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        var asset = ctx.Set<Account>().IgnoreQueryFilters().Single(a => a.Id == s.AssetId).CurrentBalance;
        var revenue = ctx.Set<Account>().IgnoreQueryFilters().Single(a => a.Id == s.RevenueId).CurrentBalance;
        var je = ctx.Set<JournalEntry>().IgnoreQueryFilters().Single(j => j.Id == s.JeId);
        var liveLines = ctx.Set<JournalEntryLine>().IgnoreQueryFilters().Count(l => l.JournalEntryId == s.JeId && !l.IsDeleted);
        return (asset, revenue, je.Status, je.IsDeleted, liveLines);
    }

    [SkippableFact]
    public async Task Void_Reverses_Balances_Voids_And_SoftDeletes_Lines()
    {
        _fx.SkipIfUnavailable();
        var s = Seed();
        await VoidInOwnTransaction(s.JeId);

        var st = State(s);
        Assert.Equal(0, st.asset);                            // 100 − (100−0) = 0
        Assert.Equal(0, st.revenue);                          // 100 − (100−0) = 0
        Assert.Equal(JournalEntryStatus.Voided, st.status);
        Assert.True(st.deleted);                              // historical entry kept (soft delete)
        Assert.Equal(0, st.liveLines);                        // lines soft-deleted
    }

    [SkippableFact]
    public async Task Void_IsIdempotent_SecondCallDoesNotDoubleReverse()
    {
        _fx.SkipIfUnavailable();
        var s = Seed();
        await VoidInOwnTransaction(s.JeId);
        await VoidInOwnTransaction(s.JeId); // second call sees Voided under the lock ⇒ no-op

        var st = State(s);
        Assert.Equal(0, st.asset);    // still exactly one reversal (not +100 nor −100)
        Assert.Equal(0, st.revenue);
    }

    [SkippableFact]
    public async Task Void_UnderConcurrency_ReversesExactlyOnce()
    {
        _fx.SkipIfUnavailable();
        var s = Seed();

        async Task<bool> Run()
        {
            try { await VoidInOwnTransaction(s.JeId); return true; } catch { return false; }
        }
        await Task.WhenAll(Task.Run(Run), Task.Run(Run));

        var st = State(s);
        Assert.Equal(0, st.asset);    // reversed EXACTLY once despite the race (−100 would mean double)
        Assert.Equal(0, st.revenue);
        Assert.Equal(JournalEntryStatus.Voided, st.status);
    }
}
