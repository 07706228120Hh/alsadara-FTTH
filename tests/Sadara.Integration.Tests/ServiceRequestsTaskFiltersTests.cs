using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Sadara.API.Controllers;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Data;
using Sadara.Infrastructure.Repositories;
using Sadara.Integration.Tests.Support;
using Xunit;
using static Sadara.Integration.Tests.Support.SummaryTestHarness;

namespace Sadara.Integration.Tests;

/// <summary>
/// Task list (<c>GetAll</c>), statistics and update paths on real Postgres:
///  - date-only filters are Baghdad calendar days and no longer throw (Kind=Unspecified);
///  - technician / creator filters match the exact Details value, not any substring;
///  - department filter falls back to Details when the column is empty;
///  - <c>assignedTo</c> filters by employee id;
///  - "today" in statistics starts at 00:00 Baghdad;
///  - technician lookup on update stays inside the task's company;
///  - reopening a completed task clears CompletedAt.
/// Skipped (not failed) when Docker is unavailable.
/// </summary>
[Collection("Postgres")]
public class ServiceRequestsTaskFiltersTests
{
    private readonly PostgresFixture _fx;

    public ServiceRequestsTaskFiltersTests(PostgresFixture fx) => _fx = fx;

    private static readonly JsonSerializerOptions Relaxed = new()
    {
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    private void Reset()
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Database.ExecuteSqlRaw(
            "DELETE FROM \"ServiceRequestStatusHistories\"; DELETE FROM \"ServiceRequests\"; " +
            "DELETE FROM \"Users\"; DELETE FROM \"Companies\";");
    }

    private static ServiceRequestsController Build(SadaraDbContext db, TestTenant tenant, Guid? userId = null)
    {
        var controller = new ServiceRequestsController(
            unitOfWork: new UnitOfWork(db),
            logger: NullLogger<ServiceRequestsController>.Instance,
            fcmService: null!,
            taskHubNotifier: null!,
            db: db,
            tenant: tenant,
            configuration: null!);
        var claims = new List<Claim>();
        if (userId.HasValue)
            claims.Add(new Claim(ClaimTypes.NameIdentifier, userId.Value.ToString()));
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(new ClaimsIdentity(claims, "TestAuth"))
            }
        };
        return controller;
    }

    /// Seeds one task. <paramref name="detailsJson"/> is stored verbatim; the
    /// Department/TechnicianName columns are set only when given (to test fallbacks).
    private Guid Seed(int svc, int op, Guid companyId, string detailsJson,
        DateTime? createdAtUtc = null, ServiceRequestStatus status = ServiceRequestStatus.Pending,
        string? departmentColumn = null, string? technicianColumn = null,
        Guid? technicianId = null, Guid? assignedToId = null, DateTime? completedAt = null)
    {
        var id = Guid.NewGuid();
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<ServiceRequest>().Add(new ServiceRequest
        {
            Id = id,
            RequestNumber = $"T{id:N}".Substring(0, 18),
            ServiceId = svc,
            OperationTypeId = op,
            CompanyId = companyId,
            Status = status,
            CreatedAt = createdAtUtc ?? DateTime.UtcNow,
            Details = detailsJson,
            Department = departmentColumn,
            TechnicianName = technicianColumn,
            TechnicianId = technicianId,
            AssignedToId = assignedToId,
            CompletedAt = completedAt,
            RequestedAt = DateTime.UtcNow,
        });
        ctx.SaveChanges();
        // SaveChanges stamps CreatedAt = UtcNow on insert — set the wanted value afterwards.
        if (createdAtUtc.HasValue)
            ctx.Database.ExecuteSqlInterpolated(
                $"UPDATE \"ServiceRequests\" SET \"CreatedAt\" = {createdAtUtc.Value} WHERE \"Id\" = {id}");
        return id;
    }

    private Guid SeedUser(Guid companyId, string fullName)
    {
        var id = Guid.NewGuid();
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<User>().Add(new User
        {
            Id = id,
            Username = $"u{id:N}".Substring(0, 12),
            FullName = fullName,
            CompanyId = companyId,
            PhoneNumber = $"07{Random.Shared.NextInt64(100_000_000, 999_999_999)}", // unique per company
            Role = UserRole.Employee,
        });
        ctx.SaveChanges();
        return id;
    }

    private static string Json(Dictionary<string, object?> d) => JsonSerializer.Serialize(d, Relaxed);

    private static List<ServiceRequestResponse> Items(IActionResult result)
    {
        var ok = Assert.IsAssignableFrom<ObjectResult>(result);
        Assert.True(ok.StatusCode is null or 200, $"status {ok.StatusCode}");
        var data = ok.Value!.GetType().GetProperty("data")!.GetValue(ok.Value);
        return Assert.IsAssignableFrom<List<ServiceRequestResponse>>(data);
    }

    // ── date-only filter = Baghdad calendar day ──────────────────────────────

    [SkippableFact]
    public async Task DateOnly_Filter_Is_A_Baghdad_Day_And_Does_Not_Throw()
    {
        _fx.SkipIfUnavailable();
        Reset();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);

        // 2026-10-25 22:30 UTC = 2026-10-26 01:30 Baghdad → belongs to the 26th.
        var lateNight = Seed(svc, op, CompanyA, Json(new() { ["technician"] = "x" }),
            createdAtUtc: new DateTime(2026, 10, 25, 22, 30, 0, DateTimeKind.Utc));
        // 2026-10-25 20:30 UTC = 23:30 Baghdad on the 25th.
        var evening = Seed(svc, op, CompanyA, Json(new() { ["technician"] = "x" }),
            createdAtUtc: new DateTime(2026, 10, 25, 20, 30, 0, DateTimeKind.Utc));

        var tenant = new TestTenant { CompanyId = CompanyA };
        await using var db = _fx.CreateContext(tenant);
        var c = Build(db, tenant);

        // Model binding of "2026-10-26" yields Kind=Unspecified.
        var day26 = new DateTime(2026, 10, 26, 0, 0, 0, DateTimeKind.Unspecified);
        var day25 = new DateTime(2026, 10, 25, 0, 0, 0, DateTimeKind.Unspecified);

        var on26 = Items(await c.GetAll(pageSize: 100, fromDate: day26, toDate: day26));
        Assert.Equal(new[] { lateNight }, on26.Select(r => r.Id));

        var on25 = Items(await c.GetAll(pageSize: 100, fromDate: day25, toDate: day25));
        Assert.Equal(new[] { evening }, on25.Select(r => r.Id));
    }

    // ── exact technician / creator matching ──────────────────────────────────

    [SkippableFact]
    public async Task Technician_Filter_Matches_Exact_Name_Not_Substrings()
    {
        _fx.SkipIfUnavailable();
        Reset();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);

        var mine = Seed(svc, op, CompanyA, Json(new() { ["technician"] = "علي", ["createdByName"] = "مدير" }));
        var createdByMe = Seed(svc, op, CompanyA, Json(new() { ["technician"] = "حسن", ["createdByName"] = "علي" }));
        // Legacy spaced format, technician column not backfilled.
        var legacy = Seed(svc, op, CompanyA, "{\"technician\": \"علي\", \"department\": \"الصيانة\"}");
        // Must NOT match: longer name, customer name, notes.
        Seed(svc, op, CompanyA, Json(new() { ["technician"] = "علي حسين", ["createdByName"] = "مدير" }));
        Seed(svc, op, CompanyA, Json(new() { ["technician"] = "حسن", ["customerName"] = "علي كاظم" }));
        Seed(svc, op, CompanyA, Json(new() { ["technician"] = "حسن", ["notes"] = "اتصل بعلي" }));

        var tenant = new TestTenant { CompanyId = CompanyA };
        await using var db = _fx.CreateContext(tenant);
        var c = Build(db, tenant);

        var both = Items(await c.GetAll(pageSize: 100, technician: "علي", createdByName: "علي"));
        Assert.Equal(new[] { mine, createdByMe, legacy }.OrderBy(x => x), both.Select(r => r.Id).OrderBy(x => x));

        var techOnly = Items(await c.GetAll(pageSize: 100, technician: "علي"));
        Assert.Equal(new[] { mine, legacy }.OrderBy(x => x), techOnly.Select(r => r.Id).OrderBy(x => x));
    }

    // ── department fallback to Details ───────────────────────────────────────

    [SkippableFact]
    public async Task Department_Filter_Uses_Details_When_Column_Is_Empty()
    {
        _fx.SkipIfUnavailable();
        Reset();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);

        var column = Seed(svc, op, CompanyA, Json(new() { ["department"] = "الصيانة" }), departmentColumn: "الصيانة");
        var detailsOnly = Seed(svc, op, CompanyA, Json(new() { ["department"] = "الصيانة" }));
        var otherDept = Seed(svc, op, CompanyA, Json(new() { ["department"] = "الحسابات" }));
        // Another company's task with the same department must stay invisible.
        Seed(svc, op, CompanyB, Json(new() { ["department"] = "الصيانة" }));

        var tenant = new TestTenant { CompanyId = CompanyA };
        await using var db = _fx.CreateContext(tenant);
        var c = Build(db, tenant);

        var one = Items(await c.GetAll(pageSize: 100, department: "الصيانة"));
        Assert.Equal(new[] { column, detailsOnly }.OrderBy(x => x), one.Select(r => r.Id).OrderBy(x => x));

        var many = Items(await c.GetAll(pageSize: 100, department: "الصيانة,الحسابات"));
        Assert.Equal(3, many.Count);
        Assert.Contains(many, r => r.Id == otherDept);
    }

    // ── assignedTo (HR employee tab) ─────────────────────────────────────────

    [SkippableFact]
    public async Task AssignedTo_Filters_By_Employee_Id()
    {
        _fx.SkipIfUnavailable();
        Reset();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var emp = SeedUser(CompanyA, "فني أ");
        var other = SeedUser(CompanyA, "فني ب");

        var byTech = Seed(svc, op, CompanyA, Json(new() { ["technician"] = "فني أ" }), technicianId: emp);
        var byAssign = Seed(svc, op, CompanyA, Json(new() { ["technician"] = "x" }), assignedToId: emp);
        Seed(svc, op, CompanyA, Json(new() { ["technician"] = "فني ب" }), technicianId: other, assignedToId: other);

        var tenant = new TestTenant { CompanyId = CompanyA };
        await using var db = _fx.CreateContext(tenant);
        var res = Items(await Build(db, tenant).GetAll(pageSize: 100, assignedTo: emp));
        Assert.Equal(new[] { byTech, byAssign }.OrderBy(x => x), res.Select(r => r.Id).OrderBy(x => x));
    }

    // ── statistics: today starts at 00:00 Baghdad ────────────────────────────

    [SkippableFact]
    public async Task Statistics_Today_Starts_At_Baghdad_Midnight()
    {
        _fx.SkipIfUnavailable();
        Reset();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);

        var baghdadNow = DateTime.UtcNow.AddHours(3);
        var midnightUtc = DateTime.SpecifyKind(baghdadNow.Date, DateTimeKind.Utc).AddHours(-3);
        Seed(svc, op, CompanyA, "{}", createdAtUtc: midnightUtc.AddMinutes(1));   // today
        Seed(svc, op, CompanyA, "{}", createdAtUtc: midnightUtc.AddMinutes(-1));  // yesterday

        var tenant = new TestTenant { CompanyId = CompanyA };
        await using var db = _fx.CreateContext(tenant);
        var ok = Assert.IsAssignableFrom<ObjectResult>(await Build(db, tenant).GetStatistics());
        var data = ok.Value!.GetType().GetProperty("data")!.GetValue(ok.Value)!;
        var todayCreated = (int)data.GetType().GetProperty("TodayCreated")!.GetValue(data)!;
        Assert.Equal(1, todayCreated);
    }

    // ── update: company-scoped technician lookup + reopen clears CompletedAt ──

    [SkippableFact]
    public async Task UpdateTask_Links_Technician_Of_Same_Company_And_Reopen_Clears_CompletedAt()
    {
        _fx.SkipIfUnavailable();
        Reset();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);

        // Same name in both companies — company B's user is seeded first.
        var foreign = SeedUser(CompanyB, "كرار حيدر");
        var local = SeedUser(CompanyA, "كرار حيدر");
        var editor = SeedUser(CompanyA, "مدير");

        var taskId = Seed(svc, op, CompanyA, Json(new() { ["technician"] = "قديم" }),
            status: ServiceRequestStatus.Completed, completedAt: DateTime.UtcNow.AddHours(-1));

        var tenant = new TestTenant { CompanyId = CompanyA };
        await using (var db = _fx.CreateContext(tenant))
        {
            var res = await Build(db, tenant, editor).UpdateTask(taskId, new UpdateTaskDto
            {
                Technician = "كرار حيدر",
                Status = "InProgress",
            });
            Assert.IsAssignableFrom<OkObjectResult>(res);
        }

        await using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        var task = await check.Set<ServiceRequest>().AsNoTracking().SingleAsync(r => r.Id == taskId);
        Assert.Equal(local, task.TechnicianId);
        Assert.Equal(local, task.AssignedToId);
        Assert.NotEqual(foreign, task.TechnicianId);
        Assert.Equal(ServiceRequestStatus.InProgress, task.Status);
        Assert.Null(task.CompletedAt);
    }

    [SkippableFact]
    public async Task UpdateTask_With_Same_Technician_Keeps_AssignedTo()
    {
        _fx.SkipIfUnavailable();
        Reset();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var tech = SeedUser(CompanyA, "فني ثابت");
        var leader = SeedUser(CompanyA, "ليدر");

        // Assigned to the leader on purpose; technician unchanged by the edit dialog.
        var taskId = Seed(svc, op, CompanyA, Json(new() { ["technician"] = "فني ثابت" }),
            technicianId: tech, assignedToId: leader);

        var tenant = new TestTenant { CompanyId = CompanyA };
        await using (var db = _fx.CreateContext(tenant))
            Assert.IsAssignableFrom<OkObjectResult>(await Build(db, tenant, leader)
                .UpdateTask(taskId, new UpdateTaskDto { Technician = "فني ثابت", Notes = "تعديل" }));

        await using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        var task = await check.Set<ServiceRequest>().AsNoTracking().SingleAsync(r => r.Id == taskId);
        Assert.Equal(tech, task.TechnicianId);
        Assert.Equal(leader, task.AssignedToId);
    }

    [SkippableFact]
    public async Task Create_Ignores_Client_CreatedById_And_Stamps_Caller()
    {
        _fx.SkipIfUnavailable();
        Reset();
        SeedCompanies(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var foreign = SeedUser(CompanyB, "ضحية");
        var caller = SeedUser(CompanyA, "منشئ");

        var tenant = new TestTenant { CompanyId = CompanyA };
        Guid createdId;
        await using (var db = _fx.CreateContext(tenant))
        {
            var res = await Build(db, tenant, caller).Create(new CreateServiceRequestDto
            {
                ServiceId = svc,
                OperationTypeId = op,
                Details = new Dictionary<string, object>
                {
                    ["taskType"] = "شراء اشتراك",
                    ["createdById"] = foreign.ToString(), // forged
                },
            });
            var created = Assert.IsType<CreatedAtActionResult>(res);
            var data = created.Value!.GetType().GetProperty("data")!.GetValue(created.Value)!;
            createdId = (Guid)data.GetType().GetProperty("Id")!.GetValue(data)!;
        }

        await using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        var task = await check.Set<ServiceRequest>().AsNoTracking().SingleAsync(r => r.Id == createdId);
        Assert.Contains($"\"createdById\":\"{caller}\"", task.Details);
        Assert.DoesNotContain(foreign.ToString(), task.Details);
    }

    [SkippableFact]
    public async Task OutOfRange_Date_Returns_400()
    {
        _fx.SkipIfUnavailable();
        var tenant = new TestTenant { CompanyId = CompanyA };
        await using var db = _fx.CreateContext(tenant);
        var res = await Build(db, tenant).GetAll(fromDate: DateTime.MinValue);
        Assert.IsType<BadRequestObjectResult>(res);
    }
}
