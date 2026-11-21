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
/// End-to-end financial cycle on real PostgreSQL: create → post a balanced journal entry (central engine
/// with account-row locking) → reverse it (VoidJournalEntryAsync, idempotent + locked) → re-apply (post a
/// new entry). Proves balances always reflect exactly one application — no amount doubling — across the
/// full lifecycle, and that a repeated reversal is a no-op. Covers the integration of C1/C2's shared helpers.
/// </summary>
[Collection("Postgres")]
public class FinancialCycleE2ETests : IDisposable
{
    private static readonly Guid Company = Guid.Parse("c5c5c5c5-0000-4000-8000-000000000001");
    private readonly PostgresFixture _fx;

    public FinancialCycleE2ETests(PostgresFixture fx) { _fx = fx; if (_fx.Available) Cleanup(); }
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
            Company);
    }

    private sealed record Seeded(Guid UserId, Guid AssetId, Guid RevenueId);

    private Seeded Seed()
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<Company>().Add(new Company { Id = Company, Name = "ش-دورة", Code = "C-CYC" });
        var userId = Guid.NewGuid();
        ctx.Set<User>().Add(new User
        {
            Id = userId, Username = $"u-{userId:N}"[..12], FullName = "مدير",
            PhoneNumber = "0781" + userId.ToString("N")[..7], CompanyId = Company, Role = UserRole.SuperAdmin
        });
        var asset = new Account { Id = Guid.NewGuid(), Code = AccountCodes.PettyCash, Name = "قاصة", AccountType = AccountType.Assets, Level = 4, IsLeaf = true, IsActive = true, CurrentBalance = 0, CompanyId = Company };
        var revenue = new Account { Id = Guid.NewGuid(), Code = "4110", Name = "إيراد صيانة", AccountType = AccountType.Revenue, Level = 3, IsLeaf = true, IsActive = true, CurrentBalance = 0, CompanyId = Company };
        ctx.Set<Account>().AddRange(asset, revenue);
        ctx.SaveChanges();
        return new Seeded(userId, asset.Id, revenue.Id);
    }

    // Posts a balanced entry: debit the asset `amount`, credit the revenue `amount` (central engine, locked).
    private async Task<Guid> PostEntry(Seeded s, decimal amount, string refId)
    {
        await using var db = _fx.CreateContext(PostgresFixture.SystemTenant);
        var uow = new UnitOfWork(db);
        var lines = new List<(Guid, decimal, decimal, string?)>
        {
            (s.AssetId, amount, 0m, "debit asset"),
            (s.RevenueId, 0m, amount, "credit revenue"),
        };
        return await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
            uow, Company, s.UserId, "cycle", JournalReferenceType.Manual, refId, lines);
    }

    // Reverses an entry inside its own transaction (as real callers do).
    private async Task ReverseEntry(Guid jeId)
    {
        await using var db = _fx.CreateContext(PostgresFixture.SystemTenant);
        var uow = new UnitOfWork(db);
        await uow.BeginTransactionAsync();
        try
        {
            var je = await db.Set<JournalEntry>().IgnoreQueryFilters().Include(j => j.Lines).FirstOrDefaultAsync(j => j.Id == jeId);
            if (je != null) await ServiceRequestAccountingHelper.VoidJournalEntryAsync(uow, je);
            await uow.CommitTransactionAsync();
        }
        catch { if (uow.HasActiveTransaction) await uow.RollbackTransactionAsync(); throw; }
    }

    private (decimal asset, decimal revenue) Balances(Seeded s)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        return (
            ctx.Set<Account>().IgnoreQueryFilters().Single(a => a.Id == s.AssetId).CurrentBalance,
            ctx.Set<Account>().IgnoreQueryFilters().Single(a => a.Id == s.RevenueId).CurrentBalance);
    }

    private JournalEntryStatus StatusOf(Guid jeId)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        return ctx.Set<JournalEntry>().IgnoreQueryFilters().Single(j => j.Id == jeId).Status;
    }

    [SkippableFact]
    public async Task FullCycle_Post_Reverse_Reapply_NeverDoublesAmounts()
    {
        _fx.SkipIfUnavailable();
        var s = Seed();

        // 1) POST — balanced entry moves the ledger by exactly the amount.
        var je1 = await PostEntry(s, 100m, "cycle-1");
        Assert.Equal((100m, 100m), Balances(s));
        Assert.Equal(JournalEntryStatus.Posted, StatusOf(je1));

        // 2) REVERSE — ledger returns exactly to zero; the entry is voided.
        await ReverseEntry(je1);
        Assert.Equal((0m, 0m), Balances(s));
        Assert.Equal(JournalEntryStatus.Voided, StatusOf(je1));

        // 3) RE-APPLY — a new entry re-applies the amount ONCE (not stacked on a lingering old effect).
        var je2 = await PostEntry(s, 100m, "cycle-2");
        Assert.Equal((100m, 100m), Balances(s));   // 100, not 200 ⇒ no double-counting
        Assert.Equal(JournalEntryStatus.Posted, StatusOf(je2));

        // 4) IDEMPOTENT REVERSAL — reversing the already-voided entry again changes nothing.
        await ReverseEntry(je1);
        Assert.Equal((100m, 100m), Balances(s));   // je2 still applied; je1 stays voided
        Assert.Equal(JournalEntryStatus.Voided, StatusOf(je1));
        Assert.Equal(JournalEntryStatus.Posted, StatusOf(je2));

        // 5) REVERSE the re-applied entry — ledger back to zero, proving the whole cycle is balanced.
        await ReverseEntry(je2);
        Assert.Equal((0m, 0m), Balances(s));
    }

    [SkippableFact]
    public async Task Reverse_Then_Reapply_DifferentAmount_TracksLedgerExactly()
    {
        _fx.SkipIfUnavailable();
        var s = Seed();
        var je1 = await PostEntry(s, 50m, "amt-1");
        Assert.Equal((50m, 50m), Balances(s));
        await ReverseEntry(je1);
        Assert.Equal((0m, 0m), Balances(s));
        // Re-apply a corrected amount — ledger reflects only the new value.
        await PostEntry(s, 75m, "amt-2");
        Assert.Equal((75m, 75m), Balances(s));
    }
}
