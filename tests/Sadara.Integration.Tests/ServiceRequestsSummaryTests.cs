using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Enums;
using Sadara.Integration.Tests.Support;
using Xunit;
using static Sadara.Integration.Tests.Support.SummaryTestHarness;

namespace Sadara.Integration.Tests;

/// <summary>
/// اختبارات تكامل لـ <c>GET /api/ServiceRequests/summary</c> (الأكشن <c>GetSummary</c>).
///
/// تعمل على Postgres حقيقي (Testcontainers) لأن الأكشن يستخدم SQL خاماً بدوال Postgres
/// حصراً (::json->>، FILTER، regex ~) لا يدعمها مزوّد EF InMemory. عند غياب Docker
/// تُتخطّى كل الاختبارات بوضوح (Skipped) عبر <see cref="PostgresFixture.SkipIfUnavailable"/>
/// — لا إخفاق ولا نجاح زائف. لا تمسّ الإنتاج إطلاقاً.
///
/// تغطية:
///  1) عزل المستأجر: شركة أ ترى مجاميعها فقط، شركة ب أرقام مختلفة، SuperAdmin يرى الكل.
///  2) تصفير الحالات التسع في byStatus (Pending..OnHold) حتى الصفرية.
///  3) صحّة buckets: open+inProgress+completed+cancelled == total والتعيين الصحيح.
///  4) فلتر التاريخ half-open: from شامل، to حصري (لا ازدواج عند منتصف الليل).
///  5) بوابة التحصيل: بلا صلاحية collections/view (وصلاحيات V2 مضبوطة) => collections صفرية؛
///     SuperAdmin/CompanyAdmin/صاحب الصلاحية => collections معبّأة.
///  6) فلترة assignee: تقصر التجميع على مهام الشخص (technician أو createdByName).
/// </summary>
[Collection("Postgres")]
public class ServiceRequestsSummaryTests
{
    private readonly PostgresFixture _fx;

    public ServiceRequestsSummaryTests(PostgresFixture fx) => _fx = fx;

    // مطالبة الدور لسياق المستخدم (نظير قيَم RequirePermissionAttribute).
    private const string RoleSuperAdmin = "SuperAdmin";
    private const string RoleCompanyAdmin = "CompanyAdmin";
    private const string RoleEmployee = "Employee";

    // مساعد: تنظيف الطلبات بين الاختبارات لتفادي التداخل عبر قاعدة مشتركة.
    private void ResetRequests()
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Database.ExecuteSqlRaw(
            "DELETE FROM \"ServiceRequests\"; DELETE FROM \"Users\"; DELETE FROM \"Companies\";");
    }

    // ══════════════════════════════════════════════════════════════════════
    // 1) عزل المستأجر
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task CompanyA_User_Sees_Only_Own_Totals()
    {
        _fx.SkipIfUnavailable();
        ResetRequests();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);

        // شركة أ: 3 طلبات؛ شركة ب: 5 طلبات.
        SeedRequests(_fx, svc, op, new[]
        {
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Pending },
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Completed },
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.InProgress },
            new RequestSpec { CompanyId = CompanyB, Status = ServiceRequestStatus.Pending },
            new RequestSpec { CompanyId = CompanyB, Status = ServiceRequestStatus.Pending },
            new RequestSpec { CompanyId = CompanyB, Status = ServiceRequestStatus.Cancelled },
            new RequestSpec { CompanyId = CompanyB, Status = ServiceRequestStatus.Rejected },
            new RequestSpec { CompanyId = CompanyB, Status = ServiceRequestStatus.OnHold },
        });

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var controller = BuildController(db, new TestTenant { CompanyId = CompanyA }, roleClaim: RoleEmployee);

        var res = Unwrap(await controller.GetSummary());

        Assert.Equal(3, res.Total);
        Assert.Equal(1, res.ByStatus.Pending);
        Assert.Equal(1, res.ByStatus.Completed);
        Assert.Equal(1, res.ByStatus.InProgress);
        // لا أثر لأي حالة تخصّ شركة ب.
        Assert.Equal(0, res.ByStatus.Cancelled);
        Assert.Equal(0, res.ByStatus.Rejected);
        Assert.Equal(0, res.ByStatus.OnHold);
    }

    [SkippableFact]
    public async Task CompanyB_User_Sees_Different_Totals_Than_CompanyA()
    {
        _fx.SkipIfUnavailable();
        ResetRequests();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);

        SeedRequests(_fx, svc, op, new[]
        {
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Pending },
            new RequestSpec { CompanyId = CompanyB, Status = ServiceRequestStatus.Pending },
            new RequestSpec { CompanyId = CompanyB, Status = ServiceRequestStatus.Completed },
        });

        await using var dbA = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var totalA = Unwrap(await BuildController(dbA, new TestTenant { CompanyId = CompanyA }, roleClaim: RoleEmployee).GetSummary()).Total;

        await using var dbB = _fx.CreateContext(new TestTenant { CompanyId = CompanyB });
        var totalB = Unwrap(await BuildController(dbB, new TestTenant { CompanyId = CompanyB }, roleClaim: RoleEmployee).GetSummary()).Total;

        Assert.Equal(1, totalA);
        Assert.Equal(2, totalB);
        Assert.NotEqual(totalA, totalB);
    }

    [SkippableFact]
    public async Task SuperAdmin_Sees_All_Companies()
    {
        _fx.SkipIfUnavailable();
        ResetRequests();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);

        SeedRequests(_fx, svc, op, new[]
        {
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Pending },
            new RequestSpec { CompanyId = CompanyB, Status = ServiceRequestStatus.Pending },
            new RequestSpec { CompanyId = CompanyB, Status = ServiceRequestStatus.Completed },
        });

        var superTenant = new TestTenant { IsSuperAdmin = true, BypassTenantFilter = true };
        await using var db = _fx.CreateContext(superTenant);
        var res = Unwrap(await BuildController(db, superTenant, roleClaim: RoleSuperAdmin).GetSummary());

        Assert.Equal(3, res.Total); // كل الشركات.
    }

    [SkippableFact]
    public async Task NonSuperAdmin_Without_Company_In_Token_Is_Forbidden()
    {
        _fx.SkipIfUnavailable();
        ResetRequests();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        SeedRequests(_fx, svc, op, new[] { new RequestSpec { CompanyId = CompanyA } });

        // مستخدم غير SuperAdmin وبلا شركة في التوكن => Forbid (لا تسريب لبيانات كل الشركات).
        var tenant = new TestTenant { CompanyId = null, IsSuperAdmin = false };
        await using var db = _fx.CreateContext(tenant);
        var result = await BuildController(db, tenant, roleClaim: RoleEmployee).GetSummary();

        Assert.IsType<Microsoft.AspNetCore.Mvc.ForbidResult>(result);
    }

    // ══════════════════════════════════════════════════════════════════════
    // 2) تصفير الحالات التسع
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task ByStatus_Always_Contains_All_Nine_Statuses_Even_When_Zero()
    {
        _fx.SkipIfUnavailable();
        ResetRequests();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);

        // طلب واحد فقط بحالة Pending — الثمانية الباقية يجب أن تكون صفراً (لا مفقودة).
        SeedRequests(_fx, svc, op, new[]
        {
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Pending },
        });

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var s = Unwrap(await BuildController(db, new TestTenant { CompanyId = CompanyA }, roleClaim: RoleEmployee).GetSummary()).ByStatus;

        Assert.Equal(1, s.Pending);
        Assert.Equal(0, s.Reviewing);
        Assert.Equal(0, s.Approved);
        Assert.Equal(0, s.Assigned);
        Assert.Equal(0, s.InProgress);
        Assert.Equal(0, s.Completed);
        Assert.Equal(0, s.Cancelled);
        Assert.Equal(0, s.Rejected);
        Assert.Equal(0, s.OnHold);
    }

    [SkippableFact]
    public async Task ByStatus_Empty_Company_Returns_All_Zeros_And_Total_Zero()
    {
        _fx.SkipIfUnavailable();
        ResetRequests();
        SeedCompanies(_fx);
        SeedServiceAndOperation(_fx);
        // لا طلبات إطلاقاً.

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var res = Unwrap(await BuildController(db, new TestTenant { CompanyId = CompanyA }, roleClaim: RoleEmployee).GetSummary());

        Assert.Equal(0, res.Total);
        var s = res.ByStatus;
        foreach (var v in new[] { s.Pending, s.Reviewing, s.Approved, s.Assigned, s.InProgress, s.Completed, s.Cancelled, s.Rejected, s.OnHold })
            Assert.Equal(0, v);
    }

    // ══════════════════════════════════════════════════════════════════════
    // 3) صحّة buckets
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task Buckets_Sum_Equals_Total_And_Mapping_Is_Correct()
    {
        _fx.SkipIfUnavailable();
        ResetRequests();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);

        // open = Pending+Reviewing+Approved+Assigned+OnHold
        // inProgress = InProgress ؛ completed = Completed ؛ cancelled = Cancelled+Rejected
        SeedRequests(_fx, svc, op, new[]
        {
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Pending },   // open
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Reviewing },  // open
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Approved },   // open
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Assigned },   // open
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.OnHold },     // open (5)
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.InProgress }, // inProgress (1)
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Completed },  // completed (1)
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Completed },  // completed (2)
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Cancelled },  // cancelled
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Rejected },   // cancelled (2)
        });

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var res = Unwrap(await BuildController(db, new TestTenant { CompanyId = CompanyA }, roleClaim: RoleEmployee).GetSummary());

        var b = res.Buckets;
        Assert.Equal(5, b.Open);
        Assert.Equal(1, b.InProgress);
        Assert.Equal(2, b.Completed);
        Assert.Equal(2, b.Cancelled);

        // الثابت المحوري: مجموع الدلاء == الإجمالي.
        Assert.Equal(res.Total, b.Open + b.InProgress + b.Completed + b.Cancelled);
        Assert.Equal(10, res.Total);
    }

    // ══════════════════════════════════════════════════════════════════════
    // 4) فلتر التاريخ half-open (from شامل، to حصري)
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task Date_Filter_Is_Half_Open_To_Is_Exclusive()
    {
        _fx.SkipIfUnavailable();
        ResetRequests();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);

        var day1 = new DateTime(2026, 3, 10, 0, 0, 0, DateTimeKind.Utc);
        var day2 = new DateTime(2026, 3, 11, 0, 0, 0, DateTimeKind.Utc); // منتصف ليل الحدّ العلوي بالضبط.

        SeedRequests(_fx, svc, op, new[]
        {
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Pending, CreatedAt = day1.AddHours(9) },  // ضمن النطاق
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Pending, CreatedAt = day1.AddHours(23) }, // ضمن النطاق
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Pending, CreatedAt = day2 },              // == to بالضبط => يُقصى (حصري)
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Pending, CreatedAt = day2.AddHours(1) },  // بعد to => يُقصى
        });

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var controller = BuildController(db, new TestTenant { CompanyId = CompanyA }, roleClaim: RoleEmployee);

        // النطاق [day1, day2) — يجب أن يشمل صفّي day1 فقط، ويُقصي صفّ day2 (منتصف الليل) بلا ازدواج.
        var res = Unwrap(await controller.GetSummary(from: day1, to: day2));

        Assert.Equal(2, res.Total);
    }

    [SkippableFact]
    public async Task Date_Filter_From_Is_Inclusive()
    {
        _fx.SkipIfUnavailable();
        ResetRequests();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);

        var from = new DateTime(2026, 3, 10, 0, 0, 0, DateTimeKind.Utc);

        SeedRequests(_fx, svc, op, new[]
        {
            new RequestSpec { CompanyId = CompanyA, CreatedAt = from },                 // == from => مشمول (شامل)
            new RequestSpec { CompanyId = CompanyA, CreatedAt = from.AddSeconds(-1) },  // قبل from => مُقصى
        });

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var res = Unwrap(await BuildController(db, new TestTenant { CompanyId = CompanyA }, roleClaim: RoleEmployee).GetSummary(from: from));

        Assert.Equal(1, res.Total);
    }

    // ══════════════════════════════════════════════════════════════════════
    // 5) بوابة التحصيل (الأمن)
    // ══════════════════════════════════════════════════════════════════════

    // يبني طلبات تحصيل مسعّرة لفنّي معيّن (taskType يطابق شرط Q3).
    private void SeedCollectionRequests(int svc, int op)
    {
        SeedRequests(_fx, svc, op, new[]
        {
            new RequestSpec
            {
                CompanyId = CompanyA, Status = ServiceRequestStatus.Completed, FinalCost = 100m,
                Details = new() { ["taskType"] = "تحصيل مبلغ تجديد", ["technician"] = "علي" }
            },
            new RequestSpec
            {
                CompanyId = CompanyA, Status = ServiceRequestStatus.Completed, FinalCost = 50m,
                Details = new() { ["taskType"] = "استحصال مبلغ", ["technician"] = "علي" }
            },
        });
    }

    [SkippableFact]
    public async Task Collections_Empty_For_Employee_Without_Permission_When_V2_Is_Set()
    {
        _fx.SkipIfUnavailable();
        ResetRequests();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        SeedCollectionRequests(svc, op);

        // صلاحيات V2 مضبوطة (غير فارغة) لكنها تُغلق collections.view صراحةً.
        // ملاحظة: HasPermission يكون fail-open فقط عند V2 فارغة؛ هنا V2 مضبوطة => الإغلاق فعّال.
        const string permsClosed = "{\"accounting\":{\"collections\":{\"view\":false},\"view\":false}}";
        var userId = SeedUser(_fx, CompanyA, UserRole.Employee, permsClosed);

        var tenant = new TestTenant { CompanyId = CompanyA };
        await using var db = _fx.CreateContext(tenant);
        var controller = BuildController(db, tenant, userId: userId, roleClaim: RoleEmployee);

        var res = Unwrap(await controller.GetSummary());

        // مجاميع الحالة تظهر، لكن قسم التحصيلات صفري/فارغ (لا تسريب مالي).
        Assert.Equal(2, res.Total);
        Assert.Equal(0m, res.Collections.TotalCollected);
        Assert.Equal(0, res.Collections.Count);
        Assert.Empty(res.Collections.ByTechnician);
    }

    [SkippableFact]
    public async Task Collections_Populated_For_SuperAdmin()
    {
        _fx.SkipIfUnavailable();
        ResetRequests();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        SeedCollectionRequests(svc, op);

        var tenant = new TestTenant { IsSuperAdmin = true, BypassTenantFilter = true };
        await using var db = _fx.CreateContext(tenant);
        var controller = BuildController(db, tenant, roleClaim: RoleSuperAdmin);

        var res = Unwrap(await controller.GetSummary());

        Assert.Equal(150m, res.Collections.TotalCollected); // 100 + 50
        Assert.Equal(2, res.Collections.Count);
        Assert.NotEmpty(res.Collections.ByTechnician);
    }

    [SkippableFact]
    public async Task Collections_Populated_For_CompanyAdmin()
    {
        _fx.SkipIfUnavailable();
        ResetRequests();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        SeedCollectionRequests(svc, op);

        // CompanyAdmin يُسمح له دائماً (عبر مطالبة الدور) بلا حاجة لصلاحية V2.
        var tenant = new TestTenant { CompanyId = CompanyA };
        await using var db = _fx.CreateContext(tenant);
        var controller = BuildController(db, tenant, roleClaim: RoleCompanyAdmin);

        var res = Unwrap(await controller.GetSummary());

        Assert.Equal(150m, res.Collections.TotalCollected);
        Assert.Equal(2, res.Collections.Count);
    }

    [SkippableFact]
    public async Task Collections_Populated_For_Employee_With_Explicit_Permission()
    {
        _fx.SkipIfUnavailable();
        ResetRequests();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        SeedCollectionRequests(svc, op);

        // موظف عادي لكن يملك accounting.collections/view = true صراحةً.
        const string permsOpen = "{\"accounting\":{\"collections\":{\"view\":true},\"view\":true}}";
        var userId = SeedUser(_fx, CompanyA, UserRole.Employee, permsOpen);

        var tenant = new TestTenant { CompanyId = CompanyA };
        await using var db = _fx.CreateContext(tenant);
        var controller = BuildController(db, tenant, userId: userId, roleClaim: RoleEmployee);

        var res = Unwrap(await controller.GetSummary());

        Assert.Equal(150m, res.Collections.TotalCollected);
        Assert.Equal(2, res.Collections.Count);
    }

    // ══════════════════════════════════════════════════════════════════════
    // 6) فلترة assignee (technician أو createdByName)
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task Assignee_Filter_Restricts_To_That_Persons_Tasks()
    {
        _fx.SkipIfUnavailable();
        ResetRequests();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);

        SeedRequests(_fx, svc, op, new[]
        {
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Completed,
                Details = new() { ["technician"] = "علي", ["department"] = "الصيانة" } },
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Pending,
                Details = new() { ["technician"] = "علي", ["department"] = "الصيانة" } },
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Completed,
                Details = new() { ["technician"] = "حسن", ["department"] = "التركيب" } },
            // مهمة يطابقها assignee عبر createdByName (لا technician).
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.InProgress,
                Details = new() { ["createdByName"] = "علي", ["department"] = "المبيعات" } },
        });

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var controller = BuildController(db, new TestTenant { CompanyId = CompanyA }, roleClaim: RoleEmployee);

        // assignee=علي => يجب أن يقصر byTechnician/byDepartment على مهام علي (3 مهام: technician×2 + createdByName×1).
        var res = Unwrap(await controller.GetSummary(assignee: "علي"));

        // byStatus في Q1 يطبّق assignee أيضاً => الإجمالي = 3.
        Assert.Equal(3, res.Total);

        // لا أثر لحسن في التجميع حسب الفني.
        Assert.DoesNotContain(res.ByTechnician, t => t.Technician == "حسن");

        // مجموع مهام "علي" عبر byDepartment = 3 (الصيانة×2 + المبيعات×1 عبر createdByName).
        var totalForAli = res.ByDepartment.Sum(d => d.Total);
        Assert.Equal(3, totalForAli);
    }

    [SkippableFact]
    public async Task Assignee_Filter_Excludes_NonJson_Details()
    {
        _fx.SkipIfUnavailable();
        ResetRequests();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);

        SeedRequests(_fx, svc, op, new[]
        {
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Pending,
                Details = new() { ["technician"] = "علي" } },
            // Details ليست JSON (لا تبدأ بـ {[) => يجب أن يُقصيها شرط regex ~ '^\s*[{[]'.
            new RequestSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Pending, RawDetails = "علي طلب نصي حر" },
        });

        await using var db = _fx.CreateContext(new TestTenant { CompanyId = CompanyA });
        var controller = BuildController(db, new TestTenant { CompanyId = CompanyA }, roleClaim: RoleEmployee);

        var res = Unwrap(await controller.GetSummary(assignee: "علي"));

        // فقط الطلب ذو الـ JSON الصالح يُحتسب في byStatus (Q1) — لا انهيار على النص الحر.
        Assert.Equal(1, res.Total);
    }
}
