using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Sadara.API.Controllers;
using Sadara.API.Constants;
using Sadara.API.Services;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Repositories;
using Sadara.Integration.Tests.Support;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// Per-partner page-balance accounts (11102-NN) on a real Postgres (Testcontainers): account creation,
/// top-up from the cash boxes, transfer from the general balance, reversal, idempotency, partner resolution
/// for an activation and tenant isolation. Skipped (not failed) when Docker is unavailable.
/// </summary>
[Collection("Postgres")]
public class PartnerPageBalanceTests : IDisposable
{
    private static readonly Guid CompanyA = Guid.Parse("a1a1a1a1-0000-4000-8000-000000000001");
    private static readonly Guid CompanyB = Guid.Parse("b1b1b1b1-0000-4000-8000-000000000002");

    private readonly PostgresFixture _fx;

    public PartnerPageBalanceTests(PostgresFixture fx)
    {
        _fx = fx;
        if (_fx.Available) Cleanup();
    }

    public void Dispose()
    {
        if (_fx.Available) Cleanup();
    }

    // Children first; scoped to this class's companies so other test classes are untouched.
    private void Cleanup()
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Database.ExecuteSqlRaw(
            "DELETE FROM \"JournalEntryLines\" WHERE \"JournalEntryId\" IN (SELECT \"Id\" FROM \"JournalEntries\" WHERE \"CompanyId\" IN ({0}, {1}));" +
            "DELETE FROM \"JournalEntries\" WHERE \"CompanyId\" IN ({0}, {1});" +
            "DELETE FROM \"Accounts\" WHERE \"CompanyId\" IN ({0}, {1}) AND \"ParentAccountId\" IS NOT NULL;" +
            "DELETE FROM \"Accounts\" WHERE \"CompanyId\" IN ({0}, {1});" +
            "DELETE FROM \"SubscriptionLogs\" WHERE \"CompanyId\" IN ({0}, {1});" +
            "DELETE FROM \"FtthAccounts\" WHERE \"CompanyId\" IN ({0}, {1});" +
            "DELETE FROM \"FtthPartners\" WHERE \"CompanyId\" IN ({0}, {1});" +
            "DELETE FROM \"Users\" WHERE \"CompanyId\" IN ({0}, {1});" +
            "DELETE FROM \"Companies\" WHERE \"Id\" IN ({0}, {1});",
            CompanyA, CompanyB);
    }

    private sealed record Seeded(Guid UserId, Guid PartnerId, Guid SecondPartnerId);

    /// <summary>Company + user + chart (1110 → 11101/11102/11104) + two partners.</summary>
    private Seeded Seed(Guid companyId, decimal petty = 1000, decimal general = 500, decimal main = 2000)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<Company>().Add(new Company { Id = companyId, Name = $"شركة {companyId:N}"[..20], Code = $"C-{companyId:N}"[..10] });
        var userId = Guid.NewGuid();
        ctx.Set<User>().Add(new User
        {
            Id = userId,
            Username = $"u-{userId:N}"[..12],
            FullName = "مستخدم اختبار",
            PhoneNumber = "0770" + userId.ToString("N")[..7],
            CompanyId = companyId,
            Role = UserRole.CompanyAdmin
        });

        var cash = new Account
        {
            Id = Guid.NewGuid(), Code = AccountCodes.Cash, Name = "النقد والصندوق", AccountType = AccountType.Assets,
            Level = 3, IsLeaf = false, CompanyId = companyId
        };
        ctx.Set<Account>().Add(cash);
        void Leaf(string code, string name, decimal balance) => ctx.Set<Account>().Add(new Account
        {
            Id = Guid.NewGuid(), Code = code, Name = name, AccountType = AccountType.Assets, ParentAccountId = cash.Id,
            Level = 4, IsLeaf = true, CurrentBalance = balance, CompanyId = companyId
        });
        Leaf(AccountCodes.PettyCash, "القاصة", petty);
        Leaf(AccountCodes.PageBalance, "رصيد الصفحة", general);
        Leaf(AccountCodes.CompanyMainCash, "صندوق الشركة الرئيسي", main);

        FtthPartner Partner(string name, string ftthId) => new()
        {
            Id = Guid.NewGuid(), CompanyId = companyId, Name = name, MainUsername = name, MainPasswordEncrypted = "enc",
            PartnerAccountId = ftthId
        };
        var p1 = Partner("مدينة الصدر", "2261175");
        var p2 = Partner("مكتب 11", "3171968");
        ctx.Set<FtthPartner>().AddRange(p1, p2);
        ctx.SaveChanges();
        return new Seeded(userId, p1.Id, p2.Id);
    }

    private decimal Balance(Guid companyId, string code)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        return ctx.Set<Account>().IgnoreQueryFilters().Single(a => a.CompanyId == companyId && a.Code == code).CurrentBalance;
    }

    private decimal PartnerBalance(Guid companyId, Guid partnerId)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        var key = PartnerPageBalanceHelper.DescriptionFor(partnerId);
        return ctx.Set<Account>().IgnoreQueryFilters().Single(a => a.CompanyId == companyId && a.Description == key).CurrentBalance;
    }

    private async Task<PartnerPageBalanceResult> Fund(Guid companyId, Guid partnerId, PartnerFundingSource source,
        decimal amount, Guid userId, string? key = null)
    {
        await using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        return await PartnerPageBalanceService.Fund(ctx, new UnitOfWork(ctx), companyId, partnerId, source, amount, null, key, userId);
    }

    private async Task<PartnerPageBalanceResult> Reverse(Guid companyId, Guid entryId, Guid userId)
    {
        await using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        return await PartnerPageBalanceService.Reverse(ctx, new UnitOfWork(ctx), companyId, entryId, userId);
    }

    [SkippableFact]
    public async Task EnsureAccount_CreatesSiblingOfGeneral_OncePerPartner_AndSyncsName()
    {
        _fx.SkipIfUnavailable();
        var s = Seed(CompanyA);

        await using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        var p1 = await ctx.Set<FtthPartner>().IgnoreQueryFilters().SingleAsync(p => p.Id == s.PartnerId);
        var p2 = await ctx.Set<FtthPartner>().IgnoreQueryFilters().SingleAsync(p => p.Id == s.SecondPartnerId);

        var a1 = await PartnerPageBalanceHelper.EnsurePartnerPageAccount(ctx, p1);
        var again = await PartnerPageBalanceHelper.EnsurePartnerPageAccount(ctx, p1);
        var a2 = await PartnerPageBalanceHelper.EnsurePartnerPageAccount(ctx, p2);
        var general = await PartnerPageBalanceHelper.FindGeneralPageAccount(ctx, CompanyA);

        Assert.NotNull(a1);
        Assert.Equal(a1!.Id, again!.Id);
        Assert.Equal("11102-01", a1.Code);
        Assert.Equal("11102-02", a2!.Code);
        Assert.Equal(general!.ParentAccountId, a1.ParentAccountId);
        Assert.Equal(general.Level, a1.Level);
        Assert.True(a1.IsLeaf);
        Assert.True(AccountCodes.IsPageBalanceCode(a1.Code));
        Assert.False(AccountCodes.KnownNonOperatorCashCodes.Contains(a1.Code));

        p1.Name = "اسم جديد";
        var renamed = await PartnerPageBalanceHelper.EnsurePartnerPageAccount(ctx, p1);
        Assert.Equal("رصيد الصفحة - اسم جديد", renamed!.Name);
    }

    [SkippableFact]
    public async Task TopUp_FromPettyCash_MovesMoney_WithBalancedEntry()
    {
        _fx.SkipIfUnavailable();
        var s = Seed(CompanyA, petty: 1000);

        var result = await Fund(CompanyA, s.PartnerId, PartnerFundingSource.PettyCash, 300, s.UserId);

        Assert.True(result.Success);
        Assert.Equal(300, PartnerBalance(CompanyA, s.PartnerId));
        Assert.Equal(700, Balance(CompanyA, AccountCodes.PettyCash));
        Assert.Equal(500, Balance(CompanyA, AccountCodes.PageBalance));

        await using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        var entry = await ctx.Set<JournalEntry>().IgnoreQueryFilters().Include(j => j.Lines)
            .SingleAsync(j => j.Id == result.JournalEntryId);
        Assert.Equal(JournalReferenceType.CashTransfer, entry.ReferenceType);
        Assert.Equal(JournalEntryStatus.Posted, entry.Status);
        Assert.Equal(CompanyA, entry.CompanyId);
        Assert.Equal(s.UserId, entry.CreatedById);
        Assert.Equal(entry.Lines.Sum(l => l.DebitAmount), entry.Lines.Sum(l => l.CreditAmount));
        Assert.Equal(300, entry.TotalDebit);
    }

    [SkippableFact]
    public async Task TopUp_FromCompanyMainCash_And_TransferFromGeneral_DebitTheRightSource()
    {
        _fx.SkipIfUnavailable();
        var s = Seed(CompanyA, general: 500, main: 2000);

        Assert.True((await Fund(CompanyA, s.PartnerId, PartnerFundingSource.CompanyMainCash, 800, s.UserId)).Success);
        Assert.True((await Fund(CompanyA, s.PartnerId, PartnerFundingSource.GeneralPageBalance, 200, s.UserId)).Success);

        Assert.Equal(1000, PartnerBalance(CompanyA, s.PartnerId));
        Assert.Equal(1200, Balance(CompanyA, AccountCodes.CompanyMainCash));
        Assert.Equal(300, Balance(CompanyA, AccountCodes.PageBalance));
        Assert.Equal(1000, Balance(CompanyA, AccountCodes.PettyCash));
    }

    [SkippableTheory]
    [InlineData(0)]
    [InlineData(-5)]
    [InlineData(10.123)]
    public async Task Fund_RejectsInvalidAmount(double amount)
    {
        _fx.SkipIfUnavailable();
        var s = Seed(CompanyA);

        var result = await Fund(CompanyA, s.PartnerId, PartnerFundingSource.PettyCash, (decimal)amount, s.UserId);

        Assert.False(result.Success);
        Assert.Equal(400, result.StatusCode);
        Assert.Equal(1000, Balance(CompanyA, AccountCodes.PettyCash));
    }

    [SkippableFact]
    public async Task Fund_RejectsWhenSourceBalanceIsInsufficient_AndPostsNothing()
    {
        _fx.SkipIfUnavailable();
        var s = Seed(CompanyA, petty: 100);

        var result = await Fund(CompanyA, s.PartnerId, PartnerFundingSource.PettyCash, 101, s.UserId);

        Assert.False(result.Success);
        Assert.Equal(400, result.StatusCode);
        Assert.Equal(100, Balance(CompanyA, AccountCodes.PettyCash));
        Assert.Equal(0, PartnerBalance(CompanyA, s.PartnerId));
        await using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        Assert.False(await ctx.Set<JournalEntry>().IgnoreQueryFilters().AnyAsync(j => j.CompanyId == CompanyA));
    }

    [SkippableFact]
    public async Task Fund_WithSameIdempotencyKey_PostsOnce()
    {
        _fx.SkipIfUnavailable();
        var s = Seed(CompanyA);
        const string key = "retry-key-0001";

        var first = await Fund(CompanyA, s.PartnerId, PartnerFundingSource.PettyCash, 250, s.UserId, key);
        var second = await Fund(CompanyA, s.PartnerId, PartnerFundingSource.PettyCash, 250, s.UserId, key);

        Assert.True(first.Success);
        Assert.False(first.Duplicate);
        Assert.True(second.Success);
        Assert.True(second.Duplicate);
        Assert.Equal(first.JournalEntryId, second.JournalEntryId);
        Assert.Equal(250, PartnerBalance(CompanyA, s.PartnerId));
        Assert.Equal(750, Balance(CompanyA, AccountCodes.PettyCash));
    }

    [SkippableFact]
    public async Task Fund_ReusingAKeyForADifferentRequest_IsAConflict()
    {
        _fx.SkipIfUnavailable();
        var s = Seed(CompanyA);
        const string key = "reused-key-0001";
        Assert.True((await Fund(CompanyA, s.PartnerId, PartnerFundingSource.PettyCash, 250, s.UserId, key)).Success);

        var otherAmount = await Fund(CompanyA, s.PartnerId, PartnerFundingSource.PettyCash, 300, s.UserId, key);
        var otherSource = await Fund(CompanyA, s.PartnerId, PartnerFundingSource.CompanyMainCash, 250, s.UserId, key);

        Assert.Equal(409, otherAmount.StatusCode);
        Assert.Equal(409, otherSource.StatusCode);
        Assert.Equal(250, PartnerBalance(CompanyA, s.PartnerId));
        Assert.Equal(750, Balance(CompanyA, AccountCodes.PettyCash));
        Assert.Equal(2000, Balance(CompanyA, AccountCodes.CompanyMainCash));
    }

    [SkippableFact]
    public async Task Fund_NeverDuplicatesADeactivatedPartnerAccount()
    {
        _fx.SkipIfUnavailable();
        var s = Seed(CompanyA);
        Assert.True((await Fund(CompanyA, s.PartnerId, PartnerFundingSource.PettyCash, 100, s.UserId)).Success);
        var key = PartnerPageBalanceHelper.DescriptionFor(s.PartnerId);
        await using (var ctx = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            var account = await ctx.Set<Account>().IgnoreQueryFilters().SingleAsync(a => a.CompanyId == CompanyA && a.Description == key);
            account.IsActive = false;
            await ctx.SaveChangesAsync();
        }

        var result = await Fund(CompanyA, s.PartnerId, PartnerFundingSource.PettyCash, 100, s.UserId);

        Assert.Equal(400, result.StatusCode);
        Assert.Equal(100, PartnerBalance(CompanyA, s.PartnerId)); // Single() ⇒ still exactly one account
        Assert.Equal(900, Balance(CompanyA, AccountCodes.PettyCash));
    }

    [SkippableFact]
    public async Task Overview_And_Statement_AreReadOnly_ForUnfundedPartners()
    {
        _fx.SkipIfUnavailable();
        var s = Seed(CompanyA);

        await using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        var overview = await PartnerPageBalanceService.GetOverview(ctx, CompanyA);
        var statement = await PartnerPageBalanceService.GetStatement(ctx, CompanyA, s.PartnerId, null, null, int.MaxValue, 50);

        Assert.Equal(2, overview.Partners.Count);
        Assert.All(overview.Partners, p => Assert.Null(p.AccountId));
        Assert.NotNull(statement);
        Assert.Empty(statement!.Rows);
        Assert.Equal(0, await ctx.Set<Account>().IgnoreQueryFilters()
            .CountAsync(a => a.CompanyId == CompanyA && a.Code.StartsWith(AccountCodes.PartnerPageBalancePrefix)));
    }

    [SkippableFact]
    public async Task Fund_ConcurrentRequestsWithSameKey_PostOnce()
    {
        _fx.SkipIfUnavailable();
        var s = Seed(CompanyA);
        const string key = "concurrent-key-01";

        var results = await Task.WhenAll(Enumerable.Range(0, 4)
            .Select(_ => Fund(CompanyA, s.PartnerId, PartnerFundingSource.PettyCash, 400, s.UserId, key)));

        Assert.All(results, r => Assert.True(r.Success));
        Assert.Single(results.Select(r => r.JournalEntryId).Distinct());
        Assert.Equal(400, PartnerBalance(CompanyA, s.PartnerId));
        Assert.Equal(600, Balance(CompanyA, AccountCodes.PettyCash));
    }

    [SkippableFact]
    public async Task Fund_ConcurrentRequests_NeverOverdrawTheSource()
    {
        _fx.SkipIfUnavailable();
        var s = Seed(CompanyA, petty: 1000);

        // 4 × 400 against 1000: exactly two may succeed.
        var results = await Task.WhenAll(Enumerable.Range(0, 4)
            .Select(_ => Fund(CompanyA, s.PartnerId, PartnerFundingSource.PettyCash, 400, s.UserId)));

        Assert.Equal(2, results.Count(r => r.Success));
        Assert.Equal(200, Balance(CompanyA, AccountCodes.PettyCash));
        Assert.Equal(800, PartnerBalance(CompanyA, s.PartnerId));
    }

    [SkippableFact]
    public async Task Reverse_RestoresBalances_OnlyOnce()
    {
        _fx.SkipIfUnavailable();
        var s = Seed(CompanyA);
        var funded = await Fund(CompanyA, s.PartnerId, PartnerFundingSource.PettyCash, 300, s.UserId);

        var reversed = await Reverse(CompanyA, funded.JournalEntryId!.Value, s.UserId);
        var again = await Reverse(CompanyA, funded.JournalEntryId.Value, s.UserId);
        var reversalOfReversal = await Reverse(CompanyA, reversed.JournalEntryId!.Value, s.UserId);

        Assert.True(reversed.Success);
        Assert.Equal(409, again.StatusCode);
        Assert.Equal(400, reversalOfReversal.StatusCode);
        Assert.Equal(0, PartnerBalance(CompanyA, s.PartnerId));
        Assert.Equal(1000, Balance(CompanyA, AccountCodes.PettyCash));
    }

    [SkippableFact]
    public async Task Reverse_IsRejected_WhenTheFundedMoneyWasAlreadySpent()
    {
        _fx.SkipIfUnavailable();
        var s = Seed(CompanyA);
        var funded = await Fund(CompanyA, s.PartnerId, PartnerFundingSource.PettyCash, 300, s.UserId);
        var key = PartnerPageBalanceHelper.DescriptionFor(s.PartnerId);
        await using (var ctx = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            // activations spent 200 of the 300
            var account = await ctx.Set<Account>().IgnoreQueryFilters().SingleAsync(a => a.CompanyId == CompanyA && a.Description == key);
            account.CurrentBalance = 100;
            await ctx.SaveChangesAsync();
        }

        var reversed = await Reverse(CompanyA, funded.JournalEntryId!.Value, s.UserId);

        Assert.Equal(400, reversed.StatusCode);
        Assert.Equal(100, PartnerBalance(CompanyA, s.PartnerId));
        Assert.Equal(700, Balance(CompanyA, AccountCodes.PettyCash));
    }

    [SkippableFact]
    public async Task ReturnToGeneral_MovesMoneyBack_EvenForADeletedPartner_AndNeverOverdraws()
    {
        _fx.SkipIfUnavailable();
        var s = Seed(CompanyA);
        var b = Seed(CompanyB);
        Assert.True((await Fund(CompanyA, s.PartnerId, PartnerFundingSource.PettyCash, 300, s.UserId)).Success);
        var generalBefore = Balance(CompanyA, AccountCodes.PageBalance);
        await using (var ctx = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            var partner = await ctx.Set<FtthPartner>().IgnoreQueryFilters().SingleAsync(p => p.Id == s.PartnerId);
            partner.IsDeleted = true;
            await ctx.SaveChangesAsync();
        }

        async Task<PartnerPageBalanceResult> Return(Guid companyId, decimal amount, Guid userId, string? key = null)
        {
            await using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
            return await PartnerPageBalanceService.ReturnToGeneral(ctx, new UnitOfWork(ctx), companyId, s.PartnerId, amount, null, key, userId);
        }

        var tooMuch = await Return(CompanyA, 301, s.UserId);
        var crossTenant = await Return(CompanyB, 100, b.UserId);
        var ok = await Return(CompanyA, 200, s.UserId, "return-key-0001");
        var replay = await Return(CompanyA, 200, s.UserId, "return-key-0001");
        var conflict = await Return(CompanyA, 100, s.UserId, "return-key-0001");

        Assert.Equal(400, tooMuch.StatusCode);
        Assert.Equal(404, crossTenant.StatusCode);
        Assert.True(ok.Success);
        Assert.True(replay.Duplicate);
        Assert.Equal(409, conflict.StatusCode);
        Assert.Equal(100, PartnerBalance(CompanyA, s.PartnerId));
        Assert.Equal(generalBefore + 200, Balance(CompanyA, AccountCodes.PageBalance));
    }

    [SkippableFact]
    public async Task CreateSubscriptionLog_TakesTheCompanyFromTheToken_NotFromTheBody()
    {
        _fx.SkipIfUnavailable();
        var a = Seed(CompanyA);
        var b = Seed(CompanyB);

        async Task<int> Create(Guid? bodyCompanyId, Guid? bodyUserId, string sessionId)
        {
            await using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
            var controller = new SubscriptionLogsController(new UnitOfWork(ctx), ctx,
                NullLogger<SubscriptionLogsController>.Instance, new TestTenant { CompanyId = CompanyA });
            var result = await controller.Create(new CreateSubscriptionLogRequest
            {
                CompanyId = bodyCompanyId, UserId = bodyUserId, SessionId = sessionId, CustomerName = "مشترك"
            });
            return (result as ObjectResult)?.StatusCode ?? 0;
        }

        var foreignCompany = await Create(CompanyB, b.UserId, "sess-foreign-company");
        var foreignUser = await Create(null, b.UserId, "sess-foreign-user");
        var stamped = await Create(null, a.UserId, "sess-own");

        Assert.Equal(403, foreignCompany);
        Assert.Equal(403, foreignUser);
        Assert.Equal(201, stamped);
        await using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        var logs = await check.Set<SubscriptionLog>().IgnoreQueryFilters()
            .Where(l => l.SessionId != null && l.SessionId.StartsWith("sess-")).ToListAsync();
        var log = Assert.Single(logs);
        Assert.Equal(CompanyA, log.CompanyId);
    }

    [SkippableFact]
    public async Task SubscriptionLogs_ReadAndWriteById_AreScopedToTheCallersCompany()
    {
        _fx.SkipIfUnavailable();
        Seed(CompanyA);
        Seed(CompanyB);
        long foreignId, ownId;
        await using (var ctx = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            var foreign = new SubscriptionLog { CompanyId = CompanyB, CustomerName = "foreign", SubscriptionId = "sub-iso", PaymentStatus = "unpaid" };
            var own = new SubscriptionLog { CompanyId = CompanyA, CustomerName = "own", SubscriptionId = "sub-iso", PaymentStatus = "unpaid" };
            ctx.AddRange(foreign, own);
            await ctx.SaveChangesAsync();
            foreignId = foreign.Id;
            ownId = own.Id;
        }

        await using var db = _fx.CreateContext(PostgresFixture.SystemTenant);
        var controller = new SubscriptionLogsController(new UnitOfWork(db), db,
            NullLogger<SubscriptionLogsController>.Instance, new TestTenant { CompanyId = CompanyA });
        static int Code(IActionResult r) => (r as ObjectResult)?.StatusCode ?? 0;

        Assert.Equal(404, Code(await controller.GetById(foreignId)));
        Assert.Equal(404, Code(await controller.Update(foreignId, new UpdateSubscriptionLogRequest { IsPrinted = true })));
        Assert.Equal(404, Code(await controller.UpdatePaymentStatus(foreignId, new UpdatePaymentStatusRequest { PaymentStatus = "paid" })));
        await controller.BulkUpdatePaymentStatus(new BulkUpdatePaymentStatusRequest { Ids = new List<long> { foreignId, ownId }, PaymentStatus = "paid" });
        Assert.Equal(200, Code(await controller.GetById(ownId)));
        Assert.Equal(200, Code(await controller.Update(ownId, new UpdateSubscriptionLogRequest { IsPrinted = true })));

        await using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        var rows = await check.Set<SubscriptionLog>().IgnoreQueryFilters().AsNoTracking()
            .Where(l => l.Id == foreignId || l.Id == ownId).ToDictionaryAsync(l => l.Id);
        Assert.Equal("unpaid", rows[foreignId].PaymentStatus);
        Assert.False(rows[foreignId].IsPrinted);
        Assert.Equal("paid", rows[ownId].PaymentStatus);
        Assert.True(rows[ownId].IsPrinted);
    }

    [SkippableFact]
    public async Task TenantIsolation_OtherCompanyCannotFundReverseOrRead()
    {
        _fx.SkipIfUnavailable();
        var a = Seed(CompanyA);
        var b = Seed(CompanyB);
        var funded = await Fund(CompanyA, a.PartnerId, PartnerFundingSource.PettyCash, 300, a.UserId);

        var crossFund = await Fund(CompanyB, a.PartnerId, PartnerFundingSource.PettyCash, 100, b.UserId);
        var crossReverse = await Reverse(CompanyB, funded.JournalEntryId!.Value, b.UserId);

        Assert.Equal(404, crossFund.StatusCode);
        Assert.Equal(404, crossReverse.StatusCode);
        Assert.Equal(300, PartnerBalance(CompanyA, a.PartnerId));
        Assert.Equal(1000, Balance(CompanyB, AccountCodes.PettyCash));

        await using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        Assert.Null(await PartnerPageBalanceService.GetStatement(ctx, CompanyB, a.PartnerId, null, null, 1, 50));
        var overviewB = await PartnerPageBalanceService.GetOverview(ctx, CompanyB);
        Assert.DoesNotContain(overviewB.Partners, p => p.PartnerId == a.PartnerId || p.PartnerId == a.SecondPartnerId);
        Assert.Equal(0, overviewB.PartnersTotal);
    }

    [SkippableFact]
    public async Task Overview_And_Statement_ReflectMovements()
    {
        _fx.SkipIfUnavailable();
        var s = Seed(CompanyA);
        var topUp = await Fund(CompanyA, s.PartnerId, PartnerFundingSource.PettyCash, 300, s.UserId);
        await Fund(CompanyA, s.SecondPartnerId, PartnerFundingSource.GeneralPageBalance, 50, s.UserId);

        await using (var ctx = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            var overview = await PartnerPageBalanceService.GetOverview(ctx, CompanyA);
            Assert.True(overview.HasPageAccount);
            Assert.Equal(450, overview.GeneralBalance);
            Assert.Equal(350, overview.PartnersTotal);
            Assert.Equal(700, overview.PettyCashBalance);
            Assert.Equal(2000, overview.CompanyMainCashBalance);
            Assert.Equal(300, overview.Partners.Single(p => p.PartnerId == s.PartnerId).Balance);

            var statement = await PartnerPageBalanceService.GetStatement(ctx, CompanyA, s.PartnerId, null, null, 1, 50);
            var row = Assert.Single(statement!.Rows);
            Assert.Equal("topup", row.Kind);
            Assert.Equal(300, row.Debit);
            Assert.True(row.CanReverse);
            Assert.False(row.Reversed);
            Assert.Equal(300, statement.CurrentBalance);
        }

        await Reverse(CompanyA, topUp.JournalEntryId!.Value, s.UserId);

        await using (var ctx = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            var statement = await PartnerPageBalanceService.GetStatement(ctx, CompanyA, s.PartnerId, null, null, 1, 50);
            Assert.Equal(2, statement!.Total);
            var original = statement.Rows.Single(r => r.Kind == "topup");
            Assert.True(original.Reversed);
            Assert.False(original.CanReverse);
            Assert.Contains(statement.Rows, r => r.Kind == "reversal" && r.Credit == 300 && !r.CanReverse);
            Assert.Equal(0, statement.CurrentBalance);
        }
    }

    [SkippableFact]
    public async Task ResolvePageAccount_UsesThePartnerOfTheLinkedAccount_AndNeverAnotherUsersAccount()
    {
        _fx.SkipIfUnavailable();
        var s = Seed(CompanyA);
        Guid otherUserId = Guid.NewGuid(), ownAccountId = Guid.NewGuid(), foreignAccountId = Guid.NewGuid();
        await using (var seed = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            seed.Set<User>().Add(new User { Id = otherUserId, Username = $"o-{otherUserId:N}"[..12], FullName = "آخر", PhoneNumber = "0780" + otherUserId.ToString("N")[..7], CompanyId = CompanyA, Role = UserRole.Employee });
            FtthAccount Linked(Guid id, Guid owner, Guid partnerId, string username) => new()
            {
                Id = id, CompanyId = CompanyA, OwnerUserId = owner, PartnerId = partnerId, Label = username,
                Username = username, PasswordEncrypted = "enc"
            };
            seed.Set<FtthAccount>().AddRange(
                Linked(ownAccountId, s.UserId, s.SecondPartnerId, "op-second"),
                Linked(Guid.NewGuid(), s.UserId, s.PartnerId, "op-first"),
                Linked(foreignAccountId, otherUserId, s.PartnerId, "op-foreign"));
            await seed.SaveChangesAsync();
        }

        await using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        SubscriptionLog Log(string? ftthPartnerId = null, string? operatorUsername = null) => new()
        {
            CompanyId = CompanyA, UserId = s.UserId, PartnerId = ftthPartnerId, OperatorUsername = operatorUsername
        };
        string KeyOf(Guid partnerId) => PartnerPageBalanceHelper.DescriptionFor(partnerId);

        // a partner account that was never funded is not charged: the general balance keeps paying
        var unfunded = await PartnerPageBalanceHelper.ResolvePageAccountForLog(ctx, Log(), ownAccountId);
        Assert.Equal(AccountCodes.PageBalance, unfunded!.Code);
        Assert.True((await Fund(CompanyA, s.PartnerId, PartnerFundingSource.PettyCash, 100, s.UserId)).Success);
        Assert.True((await Fund(CompanyA, s.SecondPartnerId, PartnerFundingSource.PettyCash, 100, s.UserId)).Success);

        // 1) the linked account the client used
        var byAccount = await PartnerPageBalanceHelper.ResolvePageAccountForLog(ctx, Log(), ownAccountId);
        Assert.Equal(KeyOf(s.SecondPartnerId), byAccount!.Description);

        // another user's linked account is ignored; two partners + no other hint ⇒ general balance
        var foreign = await PartnerPageBalanceHelper.ResolvePageAccountForLog(ctx, Log(), foreignAccountId);
        Assert.Equal(AccountCodes.PageBalance, foreign!.Code);

        // the FTTH partner id carried by the log decides, even against the linked account the client named
        var byFtthId = await PartnerPageBalanceHelper.ResolvePageAccountForLog(ctx, Log(ftthPartnerId: "2261175"), ownAccountId);
        Assert.Equal(KeyOf(s.PartnerId), byFtthId!.Description);

        // an unregistered partner id ⇒ general balance, no guessing from the other hints
        var unknownPartner = await PartnerPageBalanceHelper.ResolvePageAccountForLog(ctx, Log(ftthPartnerId: "9999999"), ownAccountId);
        Assert.Equal(AccountCodes.PageBalance, unknownPartner!.Code);

        // a partner id the user has no linked account with cannot steer the charge (client-supplied value)
        var notOwned = await PartnerPageBalanceHelper.ResolvePageAccountForLog(
            ctx, new SubscriptionLog { CompanyId = CompanyA, UserId = otherUserId, PartnerId = "3171968" }, null);
        Assert.Equal(AccountCodes.PageBalance, notOwned!.Code);

        // 3) operator username matches one of the user's linked accounts
        var byOperator = await PartnerPageBalanceHelper.ResolvePageAccountForLog(ctx, Log(operatorUsername: "OP-Second"), null);
        Assert.Equal(KeyOf(s.SecondPartnerId), byOperator!.Description);

        // nothing to go by ⇒ general balance
        var fallback = await PartnerPageBalanceHelper.ResolvePageAccountForLog(ctx, Log(), null);
        Assert.Equal(AccountCodes.PageBalance, fallback!.Code);

        // a log of another company never resolves into this company's accounts
        var otherCompany = await PartnerPageBalanceHelper.ResolvePageAccountForLog(
            ctx, new SubscriptionLog { CompanyId = CompanyB, UserId = s.UserId, PartnerId = "2261175" }, ownAccountId);
        Assert.Null(otherCompany);
    }
}
