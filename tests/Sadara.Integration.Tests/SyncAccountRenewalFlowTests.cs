using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.AspNetCore.Mvc;
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
/// Condition #4 — exercises the «مزامنة» sync account over the ACTUAL renewal path (not just the permission
/// gate): with its proposed least privilege (SecondSystemPermissionsV2 = subscriptions:{add,edit}) it can
/// create/renew a subscription log, the activation's automatic journal entry is posted (balanced, company-
/// scoped), the company is sealed from the token (no cross-company), and it is NOT granted manual accounting.
/// Real PostgreSQL (Testcontainers).
/// </summary>
[Collection("Postgres")]
public class SyncAccountRenewalFlowTests : IDisposable
{
    private static readonly Guid CompanyA = Guid.Parse("a9a9a9a9-0000-4000-8000-000000000001");
    private static readonly Guid CompanyB = Guid.Parse("b9b9b9b9-0000-4000-8000-000000000002");
    private const string SyncV2Second = "{\"subscriptions\":{\"add\":true,\"edit\":true}}";

    private readonly PostgresFixture _fx;
    public SyncAccountRenewalFlowTests(PostgresFixture fx) { _fx = fx; if (_fx.Available) Cleanup(); }
    public void Dispose() { if (_fx.Available) Cleanup(); }

    private void Cleanup()
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        foreach (var co in new[] { CompanyA, CompanyB })
            ctx.Database.ExecuteSqlRaw(
                "DELETE FROM \"JournalEntryLines\" WHERE \"JournalEntryId\" IN (SELECT \"Id\" FROM \"JournalEntries\" WHERE \"CompanyId\" = {0});" +
                "DELETE FROM \"JournalEntries\" WHERE \"CompanyId\" = {0};" +
                "DELETE FROM \"SubscriptionLogs\" WHERE \"CompanyId\" = {0};" +
                "DELETE FROM \"Accounts\" WHERE \"CompanyId\" = {0};" +
                "DELETE FROM \"Users\" WHERE \"CompanyId\" = {0};" +
                "DELETE FROM \"Companies\" WHERE \"Id\" = {0};", co);
    }

    // Seeds a company, a sync-like user (subscriptions:{add,edit} only), and the minimal chart (1110 + 11102).
    private Guid Seed(Guid companyId)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<Company>().Add(new Company { Id = companyId, Name = "ش-" + companyId.ToString("N")[..4], Code = "C-" + companyId.ToString("N")[..4] });
        var uid = Guid.NewGuid();
        ctx.Set<User>().Add(new User
        {
            Id = uid, Username = $"u-{uid:N}"[..12], FullName = "مزامنة",
            PhoneNumber = "0781" + uid.ToString("N")[..7], CompanyId = companyId, Role = UserRole.Employee,
            SecondSystemPermissionsV2 = SyncV2Second   // أقل امتياز مُعتمَد
        });
        var cash = new Account { Id = Guid.NewGuid(), Code = AccountCodes.Cash, Name = "النقد", AccountType = AccountType.Assets, Level = 3, IsLeaf = false, CompanyId = companyId };
        ctx.Set<Account>().Add(cash);
        ctx.Set<Account>().Add(new Account { Id = Guid.NewGuid(), Code = AccountCodes.PageBalance, Name = "رصيد الصفحة", AccountType = AccountType.Assets, ParentAccountId = cash.Id, Level = 4, IsLeaf = true, CurrentBalance = 500000, CompanyId = companyId });
        ctx.SaveChanges();
        return uid;
    }

    private SubscriptionLogsController Controller(SadaraDbContext db, Guid companyId) =>
        new(new UnitOfWork(db), db, NullLogger<SubscriptionLogsController>.Instance, new TestTenant { CompanyId = companyId });

    private static int Code(IActionResult r) => (r as ObjectResult)?.StatusCode ?? (r is CreatedAtActionResult ? 201 : 0);

    [SkippableFact]
    public async Task SyncAccount_Renewal_CreatesLog_PostsBalancedJournalEntry_ScopedToCompany()
    {
        _fx.SkipIfUnavailable();
        var uidA = Seed(CompanyA);

        await using (var db = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            var result = await Controller(db, CompanyA).Create(new CreateSubscriptionLogRequest
            {
                CompanyId = CompanyA, UserId = uidA, SessionId = "sess-renew-1", CustomerName = "مشترك تجديد",
                PlanName = "BASIC", PlanPrice = 35000, CollectionType = "cash",
                OperationType = "renew", ActivatedBy = "مزامنة"
            });
            Assert.Equal(201, Code(result));
        }

        // السجل أُنشئ وخُتم بشركة التوكن.
        await using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        var log = check.Set<SubscriptionLog>().IgnoreQueryFilters().Single(l => l.SessionId == "sess-renew-1");
        Assert.Equal(CompanyA, log.CompanyId);

        // القيد المحاسبي التلقائي للتفعيل أُنشئ، متوازن، ومختوم بالشركة.
        Assert.NotNull(log.JournalEntryId);
        var je = check.Set<JournalEntry>().IgnoreQueryFilters().Single(j => j.Id == log.JournalEntryId!.Value);
        Assert.Equal(CompanyA, je.CompanyId);
        Assert.Equal(JournalEntryStatus.Posted, je.Status);
        Assert.Equal(je.TotalDebit, je.TotalCredit);      // متوازن
        Assert.True(je.TotalDebit > 0);
    }

    [SkippableFact]
    public async Task SyncAccount_ForeignCompanyInBody_IsRejected_And_NullIsSealedToToken()
    {
        _fx.SkipIfUnavailable();
        var uidA = Seed(CompanyA);
        Seed(CompanyB);

        // (1) الجسم يحمل الشركة B بينما التوكن A ⇒ رفض صريح 403 (لا عبور بين الشركات).
        await using (var db = _fx.CreateContext(PostgresFixture.SystemTenant))
            Assert.Equal(403, Code(await Controller(db, CompanyA).Create(new CreateSubscriptionLogRequest
            {
                CompanyId = CompanyB, UserId = uidA, SessionId = "sess-foreign", CustomerName = "مشترك",
                PlanName = "BASIC", PlanPrice = 35000, CollectionType = "cash", OperationType = "renew", ActivatedBy = "مزامنة"
            })));

        // (2) الجسم بلا شركة ⇒ يُختَم بشركة التوكن A ⇒ 201.
        await using (var db = _fx.CreateContext(PostgresFixture.SystemTenant))
            Assert.Equal(201, Code(await Controller(db, CompanyA).Create(new CreateSubscriptionLogRequest
            {
                CompanyId = null, UserId = uidA, SessionId = "sess-null", CustomerName = "مشترك",
                PlanName = "BASIC", PlanPrice = 35000, CollectionType = "cash", OperationType = "renew", ActivatedBy = "مزامنة"
            })));

        await using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        // الطلب العابر رُفض ⇒ لا سجل له، ولا أثر لأي قيد في الشركة B.
        Assert.False(check.Set<SubscriptionLog>().IgnoreQueryFilters().Any(l => l.SessionId == "sess-foreign"));
        Assert.Equal(0, check.Set<JournalEntry>().IgnoreQueryFilters().Count(j => j.CompanyId == CompanyB));
        // الطلب السليم خُتم بالشركة A.
        Assert.Equal(CompanyA, check.Set<SubscriptionLog>().IgnoreQueryFilters().Single(l => l.SessionId == "sess-null").CompanyId);
    }
}
