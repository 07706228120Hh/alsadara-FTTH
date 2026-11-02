using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Integration.Tests.Support;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// اختبارات ضمان قاعدة البيانات لسجلّ «تحويل العمولة» (<see cref="FtthCommissionTransfer"/>)
/// على Postgres حقيقي (Testcontainers) — لأن الفهرس الفريد المُرشّح
/// <c>UNIQUE (CompanyId, FtthAccountId, RequestId) WHERE "IsDeleted" = false</c>
/// لا يفرضه مزوّد EF InMemory. هذا هو ضمان idempotency على مستوى القاعدة (منع التحويل المزدوج
/// حتى عند السباق المتزامن قبل أي نداء FTTH).
///
/// عند غياب Docker تُتخطّى كل الاختبارات بوضوح (Skipped) عبر <see cref="PostgresFixture.SkipIfUnavailable"/>
/// — لا إخفاق ولا نجاح زائف. لا تمسّ الإنتاج إطلاقاً (حاوية محلية معزولة).
///
/// تغطية:
///  1) إدراج سجلّين فعّالين بنفس (الشركة/الحساب/RequestId) ⇒ انتهاك الفهرس (23505).
///  2) الفهرس مُرشّح بـ IsDeleted=false ⇒ سجلّ محذوف لا يحجب إدراج سجلّ فعّال بنفس المفتاح.
///  3) اختلاف أيٍّ من مكوّنات المفتاح (شركة/حساب/RequestId) ⇒ يُسمَح (لا تكرار).
/// </summary>
[Collection("Postgres")]
public class FtthCommissionTransferDbConstraintTests
{
    private readonly PostgresFixture _fx;
    public FtthCommissionTransferDbConstraintTests(PostgresFixture fx) => _fx = fx;

    private static readonly Guid CompanyA = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid CompanyB = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid Owner = Guid.Parse("a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1");

    private void Reset()
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Database.ExecuteSqlRaw(
            "DELETE FROM \"FtthCommissionTransfers\"; DELETE FROM \"Companies\";");
        ctx.Set<Company>().AddRange(
            new Company { Id = CompanyA, Name = "شركة أ", Code = "CO-A" },
            new Company { Id = CompanyB, Name = "شركة ب", Code = "CO-B" });
        ctx.SaveChanges();
    }

    private static FtthCommissionTransfer Record(
        Guid companyId, Guid accountId, string requestId, bool isDeleted = false)
        => new()
        {
            Id = Guid.NewGuid(),
            CompanyId = companyId,
            OwnerUserId = Owner,
            FtthAccountId = accountId,
            PartnerId = "P-1",
            Amount = 5000,
            RequestId = requestId,
            Status = FtthCommissionTransferStatus.Succeeded,
            IsDeleted = isDeleted,
        };

    [SkippableFact]
    public void Duplicate_Active_Key_Violates_Unique_Index()
    {
        _fx.SkipIfUnavailable();
        Reset();
        var accountId = Guid.NewGuid();

        using (var ctx = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            ctx.FtthCommissionTransfers.Add(Record(CompanyA, accountId, "dup-key"));
            ctx.SaveChanges();
        }

        using var ctx2 = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx2.FtthCommissionTransfers.Add(Record(CompanyA, accountId, "dup-key"));

        var ex = Assert.Throws<DbUpdateException>(() => ctx2.SaveChanges());
        var pg = ex.InnerException as Npgsql.PostgresException;
        Assert.NotNull(pg);
        Assert.Equal("23505", pg!.SqlState); // unique_violation
    }

    [SkippableFact]
    public void SoftDeleted_Record_Does_Not_Block_New_Active_Record_Same_Key()
    {
        _fx.SkipIfUnavailable();
        Reset();
        var accountId = Guid.NewGuid();

        // سجلّ محذوف بنفس المفتاح — خارج الفهرس المُرشّح.
        using (var ctx = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            ctx.FtthCommissionTransfers.Add(Record(CompanyA, accountId, "soft-key", isDeleted: true));
            ctx.SaveChanges();
        }

        // سجلّ فعّال بنفس المفتاح — يجب أن يُقبَل (الفهرس يتجاهل المحذوف).
        using var ctx2 = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx2.FtthCommissionTransfers.Add(Record(CompanyA, accountId, "soft-key"));
        var saved = ctx2.SaveChanges();

        Assert.Equal(1, saved);
    }

    [SkippableFact]
    public void Different_Company_Same_RequestId_Is_Allowed()
    {
        _fx.SkipIfUnavailable();
        Reset();
        var accountId = Guid.NewGuid();

        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.FtthCommissionTransfers.Add(Record(CompanyA, accountId, "x-key"));
        ctx.FtthCommissionTransfers.Add(Record(CompanyB, accountId, "x-key")); // شركة مختلفة
        var saved = ctx.SaveChanges();

        Assert.Equal(2, saved);
    }

    [SkippableFact]
    public void Different_RequestId_Same_Company_Account_Is_Allowed()
    {
        _fx.SkipIfUnavailable();
        Reset();
        var accountId = Guid.NewGuid();

        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.FtthCommissionTransfers.Add(Record(CompanyA, accountId, "key-1"));
        ctx.FtthCommissionTransfers.Add(Record(CompanyA, accountId, "key-2"));
        var saved = ctx.SaveChanges();

        Assert.Equal(2, saved);
    }
}
