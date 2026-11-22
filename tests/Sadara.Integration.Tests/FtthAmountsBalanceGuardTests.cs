using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
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
/// Root-cause fix for the FTTH edit path (UpdateJournalEntryAmounts via FixBasePrices): when a full manual
/// discount is applied to an entry created WITHOUT a 5110 promo line, the collection debit becomes 0 and —
/// before the fix — nothing booked the discount, leaving the entry unbalanced (debit 0 / credit N). The fix
/// adds the missing 5110 promo line and a balance guard inside one transaction, so the entry stays balanced
/// (or the whole edit fails and rolls back). Real PostgreSQL.
/// </summary>
[Collection("Postgres")]
public class FtthAmountsBalanceGuardTests : IDisposable
{
    private static readonly Guid CompanyA = Guid.Parse("f7f7f7f7-0000-4000-8000-000000000001");
    private readonly PostgresFixture _fx;

    public FtthAmountsBalanceGuardTests(PostgresFixture fx) { _fx = fx; if (_fx.Available) Cleanup(); }
    public void Dispose() { if (_fx.Available) Cleanup(); }

    private void Cleanup()
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Database.ExecuteSqlRaw(
            "DELETE FROM \"JournalEntryLines\" WHERE \"JournalEntryId\" IN (SELECT \"Id\" FROM \"JournalEntries\" WHERE \"CompanyId\" = {0});" +
            "DELETE FROM \"JournalEntries\" WHERE \"CompanyId\" = {0};" +
            "DELETE FROM \"SubscriptionLogs\" WHERE \"CompanyId\" = {0};" +
            "DELETE FROM \"Accounts\" WHERE \"CompanyId\" = {0};" +
            "DELETE FROM \"Users\" WHERE \"CompanyId\" = {0};" +
            "DELETE FROM \"Companies\" WHERE \"Id\" = {0};", CompanyA);
    }

    private sealed record Seeded(long LogId, Guid JeId, Guid CollectionAccId, Guid PromoAccId);

    // A BASIC renewal originally booked at full price (debit collection 35000 / credit page 35000, NO 5110 line),
    // whose log now carries a FULL manual discount (35000) — the exact shape that produced the unbalanced entries.
    private Seeded Seed()
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<Company>().Add(new Company { Id = CompanyA, Name = "ش-FTTH", Code = "C-FT" });
        var uid = Guid.NewGuid();
        ctx.Set<User>().Add(new User { Id = uid, Username = $"u-{uid:N}"[..12], FullName = "مشغل", PhoneNumber = "0781" + uid.ToString("N")[..7], CompanyId = CompanyA, Role = UserRole.Employee });

        var cash = new Account { Id = Guid.NewGuid(), Code = AccountCodes.Cash, Name = "النقد", AccountType = AccountType.Assets, Level = 3, IsLeaf = false, IsActive = true, CompanyId = CompanyA };
        var collection = new Account { Id = Guid.NewGuid(), Code = "111099", Name = "صندوق المشغل", AccountType = AccountType.Assets, ParentAccountId = cash.Id, Level = 4, IsLeaf = true, IsActive = true, CurrentBalance = 35000, CompanyId = CompanyA };
        var page = new Account { Id = Guid.NewGuid(), Code = AccountCodes.PageBalance, Name = "رصيد الصفحة", AccountType = AccountType.Assets, ParentAccountId = cash.Id, Level = 4, IsLeaf = true, IsActive = true, CurrentBalance = 0, CompanyId = CompanyA };
        var promo = new Account { Id = Guid.NewGuid(), Code = AccountCodes.PromotionExpense, Name = "مصاريف عروض", AccountType = AccountType.Expenses, Level = 3, IsLeaf = true, IsActive = true, CurrentBalance = 0, CompanyId = CompanyA };
        ctx.Set<Account>().AddRange(cash, collection, page, promo);

        var jeId = Guid.NewGuid();
        ctx.Set<JournalEntry>().Add(new JournalEntry
        {
            Id = jeId, EntryNumber = "JE-FT-1", EntryDate = DateTime.UtcNow, Description = "تجديد BASIC",
            TotalDebit = 35000, TotalCredit = 35000, Status = JournalEntryStatus.Posted, CompanyId = CompanyA, CreatedById = uid,
            ReferenceType = JournalReferenceType.FtthSubscription,
            Lines = new List<JournalEntryLine>
            {
                new() { AccountId = collection.Id, DebitAmount = 35000, CreditAmount = 0, CompanyId = CompanyA, Description = "صندوق المشغل - تجديد BASIC" },
                new() { AccountId = page.Id, DebitAmount = 0, CreditAmount = 35000, CompanyId = CompanyA, Description = "خصم من رصيد الصفحة - تجديد BASIC" },
            }
        });

        var log = new SubscriptionLog
        {
            CompanyId = CompanyA, UserId = uid, CustomerName = "عميل", SubscriptionId = "sub-ft", PaymentStatus = "paid",
            PlanName = "BASIC", PlanPrice = 35000, BasePrice = 35000, ManualDiscount = 35000, CompanyDiscount = 0, MaintenanceFee = 0,
            CollectionType = "cash", OperationType = "renew", JournalEntryId = jeId
        };
        ctx.Set<SubscriptionLog>().Add(log);
        ctx.SaveChanges();
        return new Seeded(log.Id, jeId, collection.Id, promo.Id);
    }

    private FtthAccountingController Controller(SadaraDbContext db)
    {
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>()).Build();
        return new FtthAccountingController(new UnitOfWork(db), NullLogger<FtthAccountingController>.Instance, config,
            new TestTenant { CompanyId = CompanyA, IsSuperAdmin = true }, db);
    }

    private (decimal td, decimal tc, int promoLines, decimal collectionDr) State(Seeded s)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        var je = ctx.Set<JournalEntry>().IgnoreQueryFilters().Single(j => j.Id == s.JeId);
        var promoLines = ctx.Set<JournalEntryLine>().IgnoreQueryFilters().Count(l => l.JournalEntryId == s.JeId && l.AccountId == s.PromoAccId && !l.IsDeleted);
        var coll = ctx.Set<JournalEntryLine>().IgnoreQueryFilters().Where(l => l.JournalEntryId == s.JeId && l.AccountId == s.CollectionAccId && !l.IsDeleted).Select(l => l.DebitAmount).FirstOrDefault();
        return (je.TotalDebit, je.TotalCredit, promoLines, coll);
    }

    [SkippableFact]
    public async Task FullDiscountEdit_AddsMissingPromoLine_KeepsEntryBalanced()
    {
        _fx.SkipIfUnavailable();
        var s = Seed();

        await using (var db = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            // FixBasePrices يستدعي UpdateJournalEntryAmounts للسجل ذي الخصم الكامل.
            var result = await Controller(db).FixBasePrices(new List<FixBasePriceItem> { new(s.LogId, 35000m) });
            Assert.IsType<Microsoft.AspNetCore.Mvc.OkObjectResult>(result);
        }

        var st = State(s);
        Assert.Equal(st.td, st.tc);            // القيد متوازن (قبل الإصلاح كان 0 ≠ 35000)
        Assert.Equal(35000m, st.td);           // مدين = دائن = 35,000
        Assert.Equal(1, st.promoLines);        // سطر 5110 المفقود أُضيف
        Assert.Equal(0m, st.collectionDr);     // طرف التحصيل صُفِّر (خصم كامل)
    }

    [SkippableFact]
    public async Task Balanced_Ledger_Has_No_Unbalanced_FtthEntry_AfterEdit()
    {
        _fx.SkipIfUnavailable();
        var s = Seed();
        await using (var db = _fx.CreateContext(PostgresFixture.SystemTenant))
            await Controller(db).FixBasePrices(new List<FixBasePriceItem> { new(s.LogId, 35000m) });

        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        // لا قيد غير متوازن في الشركة بعد التعديل.
        Assert.Equal(0, ctx.Set<JournalEntry>().IgnoreQueryFilters()
            .Count(j => j.CompanyId == CompanyA && j.Status == JournalEntryStatus.Posted && !j.IsDeleted
                     && (j.TotalDebit - j.TotalCredit > 0.001m || j.TotalCredit - j.TotalDebit > 0.001m)));
    }
}
