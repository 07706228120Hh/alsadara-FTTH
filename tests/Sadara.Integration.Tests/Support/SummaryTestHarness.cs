using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Sadara.API.Controllers;
using Sadara.Application.Interfaces;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Data;

namespace Sadara.Integration.Tests.Support;

/// <summary>
/// أدوات مساعدة لاختبار <c>ServiceRequestsController.GetSummary</c> على Postgres حقيقي:
///   - بناء الكونترولر الحقيقي بأقل تبعيات (GetSummary يستعمل فقط <c>SadaraDbContext</c> +
///     <c>ICurrentTenant</c> + مطالبات المستخدم؛ باقي التبعيات لا تُمسّ فيمرّ null! بأمان).
///   - زرع شركات/خدمات/طلبات خدمة بقيم Details JSON واقعية.
///   - تفكيك الاستجابة (ObjectResult) إلى <c>ServiceRequestSummaryResponse</c>.
/// </summary>
public static class SummaryTestHarness
{
    /// <summary>يبني الكونترولر الحقيقي بسياق مستأجر ومطالبات مستخدم محدّدة.</summary>
    public static ServiceRequestsController BuildController(
        SadaraDbContext db,
        ICurrentTenant tenant,
        Guid? userId = null,
        string? roleClaim = null)
    {
        // GetSummary لا يستدعي أياً من هذه التبعيات إطلاقاً => null! آمن ويُبقي البناء بسيطاً.
        var controller = new ServiceRequestsController(
            unitOfWork: null!,
            logger: null!,
            fcmService: null!,
            taskHubNotifier: null!,
            db: db,
            tenant: tenant);

        var claims = new List<Claim>();
        if (userId.HasValue)
            claims.Add(new Claim(ClaimTypes.NameIdentifier, userId.Value.ToString()));
        if (roleClaim is not null)
            claims.Add(new Claim(ClaimTypes.Role, roleClaim));

        var identity = new ClaimsIdentity(claims, authenticationType: "TestAuth");
        var principal = new ClaimsPrincipal(identity);

        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext { User = principal }
        };
        return controller;
    }

    /// <summary>يفكّك ناتج الأكشن إلى عقد الاستجابة (يفشل بوضوح إن لم يكن 200/ObjectResult).</summary>
    public static ServiceRequestSummaryResponse Unwrap(IActionResult result)
    {
        var ok = result as ObjectResult
            ?? throw new Xunit.Sdk.XunitException(
                $"توقّعت ObjectResult (200) لكن حصلت على {result.GetType().Name}.");
        return ok.Value as ServiceRequestSummaryResponse
            ?? throw new Xunit.Sdk.XunitException(
                $"توقّعت ServiceRequestSummaryResponse لكن حصلت على {ok.Value?.GetType().Name ?? "null"}.");
    }

    // ═══════ الزرع ═══════

    public static readonly Guid CompanyA = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    public static readonly Guid CompanyB = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");

    /// <summary>يزرع شركتي الاختبار (أ، ب) عبر سياق النظام.</summary>
    public static void SeedCompanies(PostgresFixture fx)
    {
        using var ctx = fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<Company>().AddRange(
            new Company { Id = CompanyA, Name = "شركة أ", Code = "CO-A" },
            new Company { Id = CompanyB, Name = "شركة ب", Code = "CO-B" });
        ctx.SaveChanges();
    }

    /// <summary>يزرع خدمة ونوع عملية (لازمان لقيود FK)، ويُعيد معرّفيهما.</summary>
    public static (int serviceId, int operationTypeId) SeedServiceAndOperation(PostgresFixture fx)
    {
        using var ctx = fx.CreateContext(PostgresFixture.SystemTenant);
        var service = new Service { Name = "Internet", NameAr = "إنترنت" };
        var op = new OperationType { Name = "Task", NameAr = "مهمة" };
        ctx.Set<Service>().Add(service);
        ctx.Set<OperationType>().Add(op);
        ctx.SaveChanges();
        return (service.Id, op.Id);
    }

    /// <summary>واصف مبسّط لطلب خدمة للزرع.</summary>
    public sealed class RequestSpec
    {
        public Guid? CompanyId { get; init; }
        public ServiceRequestStatus Status { get; init; } = ServiceRequestStatus.Pending;
        public DateTime CreatedAt { get; init; } = DateTime.UtcNow;
        public Guid? AgentId { get; init; }
        public decimal? FinalCost { get; init; }
        public bool IsDeleted { get; init; }
        /// <summary>حقول Details JSON (technician/department/createdByName/taskType...). null => Details=null.</summary>
        public Dictionary<string, object?>? Details { get; init; }
        /// <summary>لتغطية حالة Details ليست JSON صالحة (سلسلة خام لا تبدأ بـ {[).</summary>
        public string? RawDetails { get; init; }
    }

    /// <summary>يزرع مجموعة طلبات خدمة عبر سياق النظام (يحترم CompanyId الصريح).</summary>
    public static void SeedRequests(
        PostgresFixture fx, int serviceId, int operationTypeId, IEnumerable<RequestSpec> specs)
    {
        using var ctx = fx.CreateContext(PostgresFixture.SystemTenant);
        var n = 0;
        foreach (var s in specs)
        {
            string? details = s.RawDetails;
            if (details is null && s.Details is not null)
                details = JsonSerializer.Serialize(s.Details,
                    new JsonSerializerOptions
                    {
                        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
                    });

            ctx.Set<ServiceRequest>().Add(new ServiceRequest
            {
                Id = Guid.NewGuid(),
                RequestNumber = $"SR-TEST-{Guid.NewGuid():N}".Substring(0, 20) + (n++),
                ServiceId = serviceId,
                OperationTypeId = operationTypeId,
                CompanyId = s.CompanyId,
                Status = s.Status,
                CreatedAt = DateTime.SpecifyKind(s.CreatedAt, DateTimeKind.Utc),
                AgentId = s.AgentId,
                FinalCost = s.FinalCost,
                IsDeleted = s.IsDeleted,
                Details = details,
                RequestedAt = DateTime.UtcNow,
            });
        }
        ctx.SaveChanges();
    }

    /// <summary>يزرع مستخدماً بصلاحيات V2 محدّدة (لبوابة التحصيلات).</summary>
    public static Guid SeedUser(PostgresFixture fx, Guid companyId, UserRole role, string? firstSystemPermsV2)
    {
        var id = Guid.NewGuid();
        using var ctx = fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<User>().Add(new User
        {
            Id = id,
            Username = $"user-{id:N}".Substring(0, 12),
            FullName = "مستخدم اختبار",
            CompanyId = companyId,
            Role = role,
            FirstSystemPermissionsV2 = firstSystemPermsV2,
        });
        ctx.SaveChanges();
        return id;
    }
}
