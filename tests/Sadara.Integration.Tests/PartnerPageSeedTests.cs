using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Sadara.API.Constants;
using Sadara.API.Controllers;
using Sadara.API.Services;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Data;
using Sadara.Infrastructure.Repositories;
using Sadara.Integration.Tests.Support;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// The one-time partner opening-balance seeding endpoint: creates each partner's «11102-NN» account and
/// posts one balanced opening entry (debit partners = real FTTH balance, credit the general 11102, plug the
/// difference to retained earnings 3200). Guarded by a config flag + idempotency. Skipped without Docker.
/// </summary>
[Collection("Postgres")]
public class PartnerPageSeedTests : IDisposable
{
    private static readonly Guid CompanyA = Guid.Parse("d4d4d4d4-0000-4000-8000-000000000001");

    private readonly PostgresFixture _fx;

    public PartnerPageSeedTests(PostgresFixture fx)
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
            "DELETE FROM \"Accounts\" WHERE \"CompanyId\" = {0} AND \"ParentAccountId\" IS NOT NULL;" +
            "DELETE FROM \"Accounts\" WHERE \"CompanyId\" = {0};" +
            "DELETE FROM \"FtthPartners\" WHERE \"CompanyId\" = {0};" +
            "DELETE FROM \"Users\" WHERE \"CompanyId\" = {0};" +
            "DELETE FROM \"Companies\" WHERE \"Id\" = {0};",
            CompanyA);
    }

    private sealed record Seeded(Guid UserId, Guid Partner1, Guid Partner2);

    /// <summary>Company + super-admin user + chart (1110 → 11102, 3200) + two partners. General 11102 = <paramref name="general"/>.</summary>
    private Seeded Seed(decimal general = 1000, decimal retained = 0)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<Company>().Add(new Company { Id = CompanyA, Name = "شركة البذر", Code = "C-SEED" });
        var userId = Guid.NewGuid();
        ctx.Set<User>().Add(new User
        {
            Id = userId, Username = $"u-{userId:N}"[..12], FullName = "مدير",
            PhoneNumber = "0781" + userId.ToString("N")[..7], CompanyId = CompanyA, Role = UserRole.SuperAdmin
        });

        var cash = new Account
        {
            Id = Guid.NewGuid(), Code = AccountCodes.Cash, Name = "النقد والصندوق", AccountType = AccountType.Assets,
            Level = 3, IsLeaf = false, CompanyId = CompanyA
        };
        ctx.Set<Account>().Add(cash);
        ctx.Set<Account>().Add(new Account
        {
            Id = Guid.NewGuid(), Code = AccountCodes.PageBalance, Name = "رصيد الصفحة", AccountType = AccountType.Assets,
            ParentAccountId = cash.Id, Level = 4, IsLeaf = true, CurrentBalance = general, CompanyId = CompanyA
        });
        ctx.Set<Account>().Add(new Account
        {
            Id = Guid.NewGuid(), Code = AccountCodes.RetainedEarnings, Name = "أرباح محتجزة", AccountType = AccountType.Equity,
            Level = 2, IsLeaf = true, CurrentBalance = retained, CompanyId = CompanyA
        });

        FtthPartner Partner(string name, string ftthId) => new()
        {
            Id = Guid.NewGuid(), CompanyId = CompanyA, Name = name, MainUsername = name,
            MainPasswordEncrypted = "enc", PartnerAccountId = ftthId
        };
        var p1 = Partner("مدينة الصدر", "2261175");
        var p2 = Partner("مكتب 11", "3171968");
        ctx.Set<FtthPartner>().AddRange(p1, p2);
        ctx.SaveChanges();
        return new Seeded(userId, p1.Id, p2.Id);
    }

    private FtthAccountingController Controller(SadaraDbContext db, Guid userId, bool allowSeed)
    {
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["PartnerPageBalance:AllowSeed"] = allowSeed ? "true" : "false"
            }).Build();
        var controller = new FtthAccountingController(new UnitOfWork(db),
            NullLogger<FtthAccountingController>.Instance, config,
            new TestTenant { CompanyId = CompanyA, IsSuperAdmin = true }, db);
        var identity = new ClaimsIdentity(new[] { new Claim(ClaimTypes.NameIdentifier, userId.ToString()) }, "test");
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext { User = new ClaimsPrincipal(identity) }
        };
        return controller;
    }

    private static int Code(IActionResult r) => (r as ObjectResult)?.StatusCode ?? (r is OkObjectResult ? 200 : 0);

    private decimal BalanceOf(string code)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        return ctx.Set<Account>().IgnoreQueryFilters().Single(a => a.CompanyId == CompanyA && a.Code == code).CurrentBalance;
    }

    private decimal PartnerBalance(Guid partnerId)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        var key = PartnerPageBalanceHelper.DescriptionFor(partnerId);
        return ctx.Set<Account>().IgnoreQueryFilters().Single(a => a.CompanyId == CompanyA && a.Description == key).CurrentBalance;
    }

    [SkippableFact]
    public async Task Seed_CreatesPartnerAccounts_PostsBalancedOpeningEntry_AndZeroesGeneral()
    {
        _fx.SkipIfUnavailable();
        var s = Seed(general: 1000, retained: 0);

        await using (var db = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            var controller = Controller(db, s.UserId, allowSeed: true);
            var result = await controller.SeedPartnerPageOpeningBalances(new SeedPartnerPageOpeningRequest(
                new List<PartnerOpeningDto>
                {
                    new(s.Partner1, 1500),
                    new(s.Partner2, 300),
                }, "seed-key-1", Confirm: true));
            Assert.Equal(200, Code(result));
        }

        // Each partner's account now holds its opening balance; the general 11102 is drained to zero.
        Assert.Equal(1500, PartnerBalance(s.Partner1));
        Assert.Equal(300, PartnerBalance(s.Partner2));
        Assert.Equal(0, BalanceOf(AccountCodes.PageBalance));
        // Plug to retained earnings = openSum - general = 1800 - 1000 = 800 (credit raises equity).
        Assert.Equal(800, BalanceOf(AccountCodes.RetainedEarnings));

        // The opening journal entry is balanced.
        await using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        var entry = await check.Set<JournalEntry>().IgnoreQueryFilters().AsNoTracking()
            .SingleAsync(j => j.CompanyId == CompanyA);
        Assert.Equal(entry.TotalDebit, entry.TotalCredit);
        Assert.Equal(1800, entry.TotalDebit);
    }

    [SkippableFact]
    public async Task Seed_IsRejected_WhenAlreadySeeded()
    {
        _fx.SkipIfUnavailable();
        var s = Seed();
        List<PartnerOpeningDto> openings = new() { new(s.Partner1, 1500), new(s.Partner2, 300) };

        await using (var db = _fx.CreateContext(PostgresFixture.SystemTenant))
            Assert.Equal(200, Code(await Controller(db, s.UserId, true)
                .SeedPartnerPageOpeningBalances(new SeedPartnerPageOpeningRequest(openings, "k1", true))));

        await using (var db = _fx.CreateContext(PostgresFixture.SystemTenant))
            Assert.Equal(409, Code(await Controller(db, s.UserId, true)
                .SeedPartnerPageOpeningBalances(new SeedPartnerPageOpeningRequest(openings, "k2", true))));
    }

    [SkippableFact]
    public async Task Seed_IsRejected_WhenFlagOff_OrPartnerMissing_OrNotConfirmed()
    {
        _fx.SkipIfUnavailable();
        var s = Seed();
        List<PartnerOpeningDto> full = new() { new(s.Partner1, 1500), new(s.Partner2, 300) };

        await using var db = _fx.CreateContext(PostgresFixture.SystemTenant);
        // flag off ⇒ 403
        Assert.Equal(403, Code(await Controller(db, s.UserId, allowSeed: false)
            .SeedPartnerPageOpeningBalances(new SeedPartnerPageOpeningRequest(full, "k", true))));
        // not confirmed ⇒ 400
        Assert.Equal(400, Code(await Controller(db, s.UserId, true)
            .SeedPartnerPageOpeningBalances(new SeedPartnerPageOpeningRequest(full, "k", Confirm: false))));
        // a partner left out ⇒ 400 (no partial seeding)
        Assert.Equal(400, Code(await Controller(db, s.UserId, true)
            .SeedPartnerPageOpeningBalances(new SeedPartnerPageOpeningRequest(
                new List<PartnerOpeningDto> { new(s.Partner1, 1500) }, "k", true))));

        // nothing was created by the rejected calls
        Assert.Equal(0, await db.Set<Account>().IgnoreQueryFilters()
            .CountAsync(a => a.CompanyId == CompanyA && a.Code.StartsWith(AccountCodes.PartnerPageBalancePrefix)));
    }
}
