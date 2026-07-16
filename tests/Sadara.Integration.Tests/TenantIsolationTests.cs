using Microsoft.EntityFrameworkCore;
using Sadara.Application.Interfaces;
using Sadara.Domain.Entities;
using Sadara.Infrastructure.Data;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// اختبار العزل متعدد الشركات (Multi-Tenant Isolation).
///
/// يتحقّق آلياً من أن الفلتر المركزي في <see cref="SadaraDbContext"/>:
///   1) يعزل بيانات كل شركة (الشركة أ لا ترى ولا سجلاً من الشركة ب).
///   2) يتجاوزه مدير النظام (SuperAdmin) فيرى كل الشركات.
///   3) يعيّن CompanyId تلقائياً عند الإدراج إلى شركة المستخدم الحالي.
///
/// يستخدم مزوّد EF Core InMemory — لا يحتاج قاعدة بيانات، ولا يمسّ الإنتاج.
/// يغطّي النوعين: Account (CompanyId من نوع Guid) و Notification (Guid?).
/// </summary>
public class TenantIsolationTests
{
    private static readonly Guid CompanyA = Guid.Parse("11111111-1111-1111-1111-111111111111");
    private static readonly Guid CompanyB = Guid.Parse("22222222-2222-2222-2222-222222222222");

    /// <summary>مزوّد مستأجر قابل للضبط للاختبار.</summary>
    private sealed class TestTenant : ICurrentTenant
    {
        public Guid? CompanyId { get; init; }
        public bool IsSuperAdmin { get; init; }
        public bool BypassTenantFilter { get; init; }
    }

    // سياق نظام يتجاوز الفلتر — يُستخدم للزرع والتحقّق المحايد.
    private static ICurrentTenant SystemTenant =>
        new TestTenant { BypassTenantFilter = true, IsSuperAdmin = true };

    private static SadaraDbContext NewContext(string dbName, ICurrentTenant tenant) =>
        new(new DbContextOptionsBuilder<SadaraDbContext>()
                .UseInMemoryDatabase(dbName)
                .Options,
            tenant);

    // يزرع سجلاً لكل شركة (أ، ب) عبر سياق النظام (يحترم CompanyId الصريح).
    private static void SeedTwoCompanies(string dbName)
    {
        using var seed = NewContext(dbName, SystemTenant);

        seed.Set<Account>().AddRange(
            new Account { Id = Guid.NewGuid(), CompanyId = CompanyA },
            new Account { Id = Guid.NewGuid(), CompanyId = CompanyB });

        seed.Set<Notification>().AddRange(
            new Notification { Id = 1, CompanyId = CompanyA },
            new Notification { Id = 2, CompanyId = CompanyB });

        seed.SaveChanges();
    }

    [Fact]
    public void CompanyA_User_Sees_Only_CompanyA_Data()
    {
        var dbName = Guid.NewGuid().ToString();
        SeedTwoCompanies(dbName);

        using var ctx = NewContext(dbName, new TestTenant { CompanyId = CompanyA });

        var accounts = ctx.Set<Account>().ToList();
        Assert.NotEmpty(accounts);
        Assert.All(accounts, a => Assert.Equal(CompanyA, a.CompanyId));
        Assert.DoesNotContain(accounts, a => a.CompanyId == CompanyB);

        var notifications = ctx.Set<Notification>().ToList();
        Assert.All(notifications, n => Assert.Equal(CompanyA, n.CompanyId));
        Assert.DoesNotContain(notifications, n => n.CompanyId == CompanyB);
    }

    [Fact]
    public void CompanyB_User_Cannot_See_CompanyA_Data()
    {
        var dbName = Guid.NewGuid().ToString();
        SeedTwoCompanies(dbName);

        using var ctx = NewContext(dbName, new TestTenant { CompanyId = CompanyB });

        var accounts = ctx.Set<Account>().ToList();
        Assert.NotEmpty(accounts);
        Assert.All(accounts, a => Assert.Equal(CompanyB, a.CompanyId));
        Assert.DoesNotContain(accounts, a => a.CompanyId == CompanyA);
    }

    [Fact]
    public void SuperAdmin_Sees_All_Companies()
    {
        var dbName = Guid.NewGuid().ToString();
        SeedTwoCompanies(dbName);

        using var ctx = NewContext(dbName, new TestTenant { BypassTenantFilter = true, IsSuperAdmin = true });

        var accounts = ctx.Set<Account>().ToList();
        Assert.Contains(accounts, a => a.CompanyId == CompanyA);
        Assert.Contains(accounts, a => a.CompanyId == CompanyB);
    }

    [Fact]
    public void Insert_By_CompanyA_AutoAssigns_CompanyA()
    {
        var dbName = Guid.NewGuid().ToString();

        // إدراج بلا تحديد CompanyId من سياق الشركة أ
        using (var ctxA = NewContext(dbName, new TestTenant { CompanyId = CompanyA }))
        {
            ctxA.Set<Account>().Add(new Account { Id = Guid.NewGuid() });
            ctxA.SaveChanges();
        }

        // تحقّق محايد: عُيّنت الشركة تلقائياً إلى أ
        using var check = NewContext(dbName, SystemTenant);
        var account = Assert.Single(check.Set<Account>());
        Assert.Equal(CompanyA, account.CompanyId);
    }

    [Fact]
    public void CompanyA_Insert_Is_Invisible_To_CompanyB()
    {
        var dbName = Guid.NewGuid().ToString();

        using (var ctxA = NewContext(dbName, new TestTenant { CompanyId = CompanyA }))
        {
            ctxA.Set<Account>().Add(new Account { Id = Guid.NewGuid() });
            ctxA.SaveChanges();
        }

        // الشركة ب لا ترى ما أدرجته أ
        using var ctxB = NewContext(dbName, new TestTenant { CompanyId = CompanyB });
        Assert.Empty(ctxB.Set<Account>().ToList());
    }

    [Fact]
    public void Insert_With_Foreign_CompanyId_Is_Forced_To_Current_Company()
    {
        var dbName = Guid.NewGuid().ToString();

        // محاولة حقن: مستخدم الشركة أ يُدرج سجلاً بـ CompanyId = ب صراحةً
        using (var ctxA = NewContext(dbName, new TestTenant { CompanyId = CompanyA }))
        {
            ctxA.Set<Account>().Add(new Account { Id = Guid.NewGuid(), CompanyId = CompanyB });
            ctxA.SaveChanges();
        }

        // النتيجة: فُرضت شركة أ (لا حقن في ب) — ولا تراه ب
        using var check = NewContext(dbName, SystemTenant);
        var account = Assert.Single(check.Set<Account>());
        Assert.Equal(CompanyA, account.CompanyId);

        using var ctxB = NewContext(dbName, new TestTenant { CompanyId = CompanyB });
        Assert.Empty(ctxB.Set<Account>().ToList());
    }
}
