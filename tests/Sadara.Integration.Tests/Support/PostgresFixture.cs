using Microsoft.EntityFrameworkCore;
using Sadara.Application.Interfaces;
using Sadara.Infrastructure.Data;
using Testcontainers.PostgreSql;
using Xunit;

namespace Sadara.Integration.Tests.Support;

/// <summary>
/// مُهيّئ Postgres حقيقي (Testcontainers) لاختبارات <c>GET /api/ServiceRequests/summary</c>.
///
/// لماذا Postgres حقيقي وليس InMemory؟
///   الأكشن <c>GetSummary</c> يستخدم SQL خام يعتمد دوال Postgres حصراً:
///     - استخراج JSON:  ""Details""::json->>'department'
///     - التجميع المشروط: count(*) FILTER (WHERE ...)
///     - regex:          ""Details"" ~ '^\s*[{[]'
///   مزوّد EF Core InMemory لا يدعم أياً منها؛ لذا لا يمكن اختبار هذا الأكشن إلا على Postgres.
///
/// السلوك عند غياب Docker (كبيئة CI الحالية / أجهزة بلا Docker daemon):
///   <see cref="Available"/> = false، وكل اختبار يستدعي <see cref="SkipIfUnavailable"/>
///   فيُتخطّى (Skipped) بوضوح — لا يُخفَق ولا يُلوّن أخضر زوراً.
///
/// لا يمسّ الإنتاج إطلاقاً: الحاوية محلية معزولة، تُنشأ وتُدمَّر ضمن دورة الاختبار.
/// </summary>
public sealed class PostgresFixture : IAsyncLifetime
{
    private PostgreSqlContainer? _container;

    /// <summary>هل توفّر Postgres فعلياً (نجح إقلاع الحاوية)؟ إن لا، تُتخطّى الاختبارات.</summary>
    public bool Available { get; private set; }

    /// <summary>سبب عدم التوفّر (يُعرَض في رسالة التخطّي).</summary>
    public string? SkipReason { get; private set; }

    /// <summary>سلسلة الاتصال بحاوية الاختبار (صالحة فقط عند <see cref="Available"/>).</summary>
    public string ConnectionString { get; private set; } = string.Empty;

    public async Task InitializeAsync()
    {
        try
        {
            _container = new PostgreSqlBuilder()
                .WithImage("postgres:16-alpine")
                .WithDatabase("sadara_test")
                .WithUsername("sadara")
                .WithPassword("sadara_test_pwd")
                .Build();

            await _container.StartAsync();
            ConnectionString = _container.GetConnectionString();

            // إنشاء المخطّط من نموذج EF (بلا هجرات — EnsureCreated يكفي لجداول الاختبار).
            await using var ctx = CreateContext(SystemTenant);
            await ctx.Database.EnsureCreatedAsync();

            Available = true;
        }
        catch (Exception ex)
        {
            // Docker غير متوفّر / تعذّر سحب الصورة / تعذّر الإقلاع => نُعلّم كـ "غير متوفّر".
            Available = false;
            SkipReason = "Postgres عبر Testcontainers غير متوفّر (Docker غير مشغّل أو تعذّر الإقلاع): "
                         + ex.GetType().Name + " — " + ex.Message;
            if (_container is not null)
            {
                try { await _container.DisposeAsync(); } catch { /* تجاهل */ }
                _container = null;
            }
        }
    }

    public async Task DisposeAsync()
    {
        if (_container is not null)
            await _container.DisposeAsync();
    }

    /// <summary>يتخطّى الاختبار (Skipped) بوضوح إذا لم تتوفّر قاعدة الاختبار.</summary>
    public void SkipIfUnavailable() =>
        Skip.IfNot(Available, SkipReason ?? "قاعدة اختبار Postgres غير متوفّرة.");

    /// <summary>ينشئ سياق قاعدة بيانات جديداً موجَّهاً لحاوية الاختبار بمستأجر محدّد.</summary>
    public SadaraDbContext CreateContext(ICurrentTenant tenant)
    {
        var options = new DbContextOptionsBuilder<SadaraDbContext>()
            .UseNpgsql(ConnectionString)
            .Options;
        return new SadaraDbContext(options, tenant);
    }

    /// <summary>سياق نظام يتجاوز فلتر العزل — يُستخدم للزرع والتحقّق المحايد.</summary>
    public static ICurrentTenant SystemTenant =>
        new TestTenant { BypassTenantFilter = true, IsSuperAdmin = true };
}

/// <summary>مزوّد مستأجر قابل للضبط للاختبار (نظير الموجود في TenantIsolationTests).</summary>
public sealed class TestTenant : ICurrentTenant
{
    public Guid? CompanyId { get; init; }
    public bool IsSuperAdmin { get; init; }
    public bool BypassTenantFilter { get; init; }
    public Guid? DefaultCompanyId { get; init; }
}
