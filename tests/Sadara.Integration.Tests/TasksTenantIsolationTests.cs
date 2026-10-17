using System.Reflection;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using Sadara.API.Controllers;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Integration.Tests.Support;
using Xunit;
using static Sadara.Integration.Tests.Support.TasksIsolationHarness;

namespace Sadara.Integration.Tests;

/// <summary>
/// Phase 0-D — tenant isolation and authorization for tasks (ServiceRequests), technician
/// transactions, subscription logs and task audits. Real controllers over real Postgres
/// (Testcontainers); skipped (not failed) when Docker is unavailable. Never touches production.
/// </summary>
[Collection("PostgresTasksIsolation")]
public class TasksTenantIsolationTests
{
    private readonly PostgresFixture _fx;

    public TasksTenantIsolationTests(PostgresFixture fx) => _fx = fx;

    private const string Employee = "Employee";
    private const string Technician = "Technician";
    private const string Leader = "TechnicalLeader";
    private const string CompanyAdmin = "CompanyAdmin";
    private const string SuperAdmin = "SuperAdmin";

    private static Dictionary<string, object?> D(params (string k, object? v)[] kv) =>
        kv.ToDictionary(x => x.k, x => x.v);

    private static HashSet<Guid> Ids(JsonElement json) =>
        json.GetProperty("data").EnumerateArray().Select(e => e.GetProperty("Id").GetGuid()).ToHashSet();

    // ══════════════════════════════════════════════════════════════════════
    // ServiceRequests — company scope of list / statistics
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task GetAll_CompanyUser_SeesOnlyOwnCompany_AndClientCompanyIdIsIgnored()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var a1 = SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA });
        var a2 = SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA });
        for (var i = 0; i < 3; i++) SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyB });
        var user = SeedUser(_fx, CompanyA, UserRole.Employee, "موظف أ");

        await using var db = _fx.CreateContext(TenantOf(CompanyA));
        var res = await ServiceRequests(db, TenantOf(CompanyA), user, Employee).GetAll(companyId: CompanyB);

        var json = Json(res);
        Assert.Equal(2, json.GetProperty("total").GetInt32());
        Assert.Equal(new HashSet<Guid> { a1, a2 }, Ids(json));
    }

    [SkippableFact]
    public async Task GetAll_SuperAdmin_SeesAllCompanies_AndMayFilterByCompany()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA });
        for (var i = 0; i < 3; i++) SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyB });

        await using var db = _fx.CreateContext(SuperTenant);
        var all = Json(await ServiceRequests(db, SuperTenant, null, SuperAdmin).GetAll());
        var onlyB = Json(await ServiceRequests(db, SuperTenant, null, SuperAdmin).GetAll(companyId: CompanyB));

        Assert.Equal(4, all.GetProperty("total").GetInt32());
        Assert.Equal(3, onlyB.GetProperty("total").GetInt32());
    }

    [SkippableFact]
    public async Task GetAll_And_Statistics_TokenWithoutCompany_Return403()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA });

        await using var db = _fx.CreateContext(NoCompanyTenant);
        var controller = ServiceRequests(db, NoCompanyTenant, Guid.NewGuid(), Employee);

        Assert.Equal(403, StatusOf(await controller.GetAll()));
        Assert.Equal(403, StatusOf(await controller.GetStatistics()));
        Assert.Equal(403, StatusOf(await controller.GetMyAssigned()));
        Assert.Equal(403, StatusOf(await controller.GetTaskStaff()));
        Assert.False(Json(await controller.GetAll()).GetProperty("success").GetBoolean());
    }

    [SkippableFact]
    public async Task GetStatistics_IsCompanyScoped_EvenWithForeignCompanyId()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Pending });
        SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Completed });
        for (var i = 0; i < 4; i++)
            SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyB, Status = ServiceRequestStatus.Pending });
        var user = SeedUser(_fx, CompanyA, UserRole.Manager, "مدير أ");

        await using var db = _fx.CreateContext(TenantOf(CompanyA));
        var data = Json(await ServiceRequests(db, TenantOf(CompanyA), user, "Manager").GetStatistics(companyId: CompanyB))
            .GetProperty("data");

        Assert.Equal(2, data.GetProperty("Total").GetInt32());
        Assert.Equal(1, data.GetProperty("Pending").GetInt32());
        Assert.Equal(1, data.GetProperty("Completed").GetInt32());
    }

    [SkippableFact]
    public async Task ById_Endpoints_CrossCompany_Return404()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var bTask = SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyB, Details = D(("technician", "حسن")) });
        var admin = SeedUser(_fx, CompanyA, UserRole.CompanyAdmin, "مدير شركة أ");

        await using var db = _fx.CreateContext(TenantOf(CompanyA));
        var c = ServiceRequests(db, TenantOf(CompanyA), admin, CompanyAdmin);

        Assert.Equal(404, StatusOf(await c.GetById(bTask)));
        Assert.Equal(404, StatusOf(await c.GetByNumber(RequestNumberOf(_fx, bTask))));
        Assert.Equal(404, StatusOf(await c.UpdateStatus(bTask, new UpdateStatusDto { Status = "Cancelled" })));
        Assert.Equal(404, StatusOf(await c.AssignTask(bTask, new AssignTaskDto { Technician = "حسن" })));
        Assert.Equal(404, StatusOf(await c.UpdateTask(bTask, new UpdateTaskDto { Notes = "x" })));
        Assert.Equal(404, StatusOf(await c.GetComments(bTask)));
        Assert.Equal(404, StatusOf(await c.GetAttachments(bTask)));

        // The foreign task is untouched.
        using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        Assert.Equal(ServiceRequestStatus.Pending, check.Set<ServiceRequest>().Single(r => r.Id == bTask).Status);
    }

    // ══════════════════════════════════════════════════════════════════════
    // ServiceRequests — delete authorization
    // ══════════════════════════════════════════════════════════════════════

    [Fact]
    public void Delete_RequiresCompanyAdminOrAbovePolicy()
    {
        var attr = typeof(ServiceRequestsController)
            .GetMethod(nameof(ServiceRequestsController.DeleteRequest))!
            .GetCustomAttributes<AuthorizeAttribute>()
            .Single();
        Assert.Equal("CompanyAdminOrAbove", attr.Policy);
    }

    [SkippableFact]
    public async Task Delete_CrossCompany_IsDenied_SameCompany_Succeeds()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var aTask = SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA });
        var bTask = SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyB });
        var admin = SeedUser(_fx, CompanyA, UserRole.CompanyAdmin, "مدير شركة أ");

        await using (var db = _fx.CreateContext(TenantOf(CompanyA)))
        {
            var c = ServiceRequests(db, TenantOf(CompanyA), admin, CompanyAdmin);
            Assert.Equal(404, StatusOf(await c.DeleteRequest(bTask)));
        }
        await using (var db = _fx.CreateContext(TenantOf(CompanyA)))
        {
            var c = ServiceRequests(db, TenantOf(CompanyA), admin, CompanyAdmin);
            Assert.Equal(200, StatusOf(await c.DeleteRequest(aTask)));
        }

        using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        Assert.True(check.Set<ServiceRequest>().IgnoreQueryFilters().Any(r => r.Id == bTask));
        Assert.False(check.Set<ServiceRequest>().IgnoreQueryFilters().Any(r => r.Id == aTask));
    }

    // ══════════════════════════════════════════════════════════════════════
    // ServiceRequests — technician role scope (server-side)
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task Technician_SeesOnlyOwnTasks_AndCannotWidenWithClientFilters()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var ali = SeedUser(_fx, CompanyA, UserRole.Technician, "علي");
        var hassan = SeedUser(_fx, CompanyA, UserRole.Technician, "حسن");

        // Own tasks — by id, by Details name only (column not backfilled), and created by him.
        var byId = SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA, TechnicianId = ali });
        var byDetailsName = SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA, Details = D(("technician", "علي")) });
        var createdByHim = SeedTask(_fx, svc, op, new TaskSpec
        {
            CompanyId = CompanyA,
            Details = D(("technician", "حسن"), ("createdByName", "علي"), ("createdById", ali.ToString()))
        });
        // Not his — another technician, and a longer name that merely contains his.
        SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA, TechnicianId = hassan, TechnicianNameColumn = "حسن", Details = D(("technician", "حسن")) });
        SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA, TechnicianNameColumn = "علي حسين", Details = D(("technician", "علي حسين")) });
        // Same name in another company — never visible.
        SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyB, TechnicianNameColumn = "علي", Details = D(("technician", "علي")) });

        await using var db = _fx.CreateContext(TenantOf(CompanyA));
        var c = ServiceRequests(db, TenantOf(CompanyA), ali, Technician);

        var own = Json(await c.GetAll(pageSize: 100));
        Assert.Equal(new HashSet<Guid> { byId, byDetailsName, createdByHim }, Ids(own));

        // A client filter for someone else is ANDed with the scope ⇒ nothing leaks.
        var widened = Json(await c.GetAll(pageSize: 100, technician: "حسن"));
        Assert.DoesNotContain(widened.GetProperty("data").EnumerateArray(),
            e => e.GetProperty("TechnicianId").ValueKind == JsonValueKind.String
                 && e.GetProperty("TechnicianId").GetGuid() == hassan);
        Assert.Equal(0, Ids(widened).Except(new[] { byId, byDetailsName, createdByHim }).Count());

        var stats = Json(await c.GetStatistics()).GetProperty("data");
        Assert.Equal(3, stats.GetProperty("Total").GetInt32());

        var mine = Json(await c.GetMyAssigned(pageSize: 100, technicianName: "حسن", includeCompleted: true));
        Assert.True(Ids(mine).IsSubsetOf(new[] { byId, byDetailsName, createdByHim }));
        Assert.Contains(byId, Ids(mine));
    }

    [SkippableFact]
    public async Task Leader_And_Manager_StillSeeWholeCompany()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA, Details = D(("technician", "حسن")) });
        SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA, Details = D(("technician", "علي")) });
        var leader = SeedUser(_fx, CompanyA, UserRole.TechnicalLeader, "ليدر");
        var manager = SeedUser(_fx, CompanyA, UserRole.Manager, "مدير");

        await using var db = _fx.CreateContext(TenantOf(CompanyA));
        Assert.Equal(2, Json(await ServiceRequests(db, TenantOf(CompanyA), leader, Leader).GetAll()).GetProperty("total").GetInt32());
        Assert.Equal(2, Json(await ServiceRequests(db, TenantOf(CompanyA), manager, "Manager").GetAll()).GetProperty("total").GetInt32());
    }

    [SkippableFact]
    public async Task Technician_Summary_IsForcedToOwnName()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var ali = SeedUser(_fx, CompanyA, UserRole.Technician, "علي");
        SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA, TechnicianNameColumn = "علي", Details = D(("technician", "علي")) });
        SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA, TechnicianNameColumn = "حسن", Details = D(("technician", "حسن")) });
        SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA, TechnicianNameColumn = "حسن", Details = D(("technician", "حسن")) });

        await using var db = _fx.CreateContext(TenantOf(CompanyA));
        var c = ServiceRequests(db, TenantOf(CompanyA), ali, Technician);

        Assert.Equal(1, SummaryTestHarness.Unwrap(await c.GetSummary()).Total);
        Assert.Equal(1, SummaryTestHarness.Unwrap(await c.GetSummary(assignee: "حسن")).Total);
    }

    // ══════════════════════════════════════════════════════════════════════
    // ServiceRequests — company from token on create
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task Create_IgnoresClientCompanyId()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var user = SeedUser(_fx, CompanyA, UserRole.Employee, "موظف أ");

        await using var db = _fx.CreateContext(TenantOf(CompanyA));
        var res = await ServiceRequests(db, TenantOf(CompanyA), user, Employee).Create(new CreateServiceRequestDto
        {
            ServiceId = svc,
            OperationTypeId = op,
            CompanyId = CompanyB,
        });

        var id = Json(res).GetProperty("data").GetProperty("Id").GetGuid();
        using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        Assert.Equal(CompanyA, check.Set<ServiceRequest>().Single(r => r.Id == id).CompanyId);
    }

    // ══════════════════════════════════════════════════════════════════════
    // ServiceRequests — technician name resolution never crosses companies
    // ══════════════════════════════════════════════════════════════════════

    private async Task<ServiceRequest> CreateTaskAs(Guid caller, string technician, string phone, int svc, int op)
    {
        await using var db = _fx.CreateContext(TenantOf(CompanyA));
        var res = await ServiceRequests(db, TenantOf(CompanyA), caller, CompanyAdmin).CreateTask(new CreateTaskDto
        {
            TaskType = "صيانة",
            Technician = technician,
            CustomerName = "زبون",
            CustomerPhone = phone,
            ServiceId = svc,
            OperationTypeId = op,
        });
        Assert.Equal(201, StatusOf(res));
        var id = Json(res).GetProperty("data").GetProperty("Id").GetGuid();
        using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        return check.Set<ServiceRequest>().Single(r => r.Id == id);
    }

    [SkippableFact]
    public async Task CreateTask_SameNameTechnicianInOtherCompany_IsNeverResolved()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var admin = SeedUser(_fx, CompanyA, UserRole.CompanyAdmin, "مدير شركة أ");
        SeedUser(_fx, CompanyB, UserRole.Technician, "سالم"); // exists only in company B

        var task = await CreateTaskAs(admin, "سالم", "07700000001", svc, op);

        Assert.Equal(CompanyA, task.CompanyId);       // company stamped from the token
        Assert.Null(task.TechnicianId);               // B's "سالم" is never picked
        Assert.Null(task.AssignedToId);
        Assert.Equal(ServiceRequestStatus.Pending, task.Status);
    }

    [SkippableFact]
    public async Task CreateTask_ResolvesTechnicianInsideCompany_AndLeavesAmbiguousUnresolved()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var admin = SeedUser(_fx, CompanyA, UserRole.CompanyAdmin, "مدير شركة أ");
        var aliA = SeedUser(_fx, CompanyA, UserRole.Technician, "علي");
        SeedUser(_fx, CompanyB, UserRole.Technician, "علي");          // same name, other company
        SeedUser(_fx, CompanyA, UserRole.Technician, "كرار");
        SeedUser(_fx, CompanyA, UserRole.Technician, "كرار");         // ambiguous inside company A

        var resolved = await CreateTaskAs(admin, "علي", "07700000002", svc, op);
        Assert.Equal(aliA, resolved.TechnicianId);
        Assert.Equal(ServiceRequestStatus.Assigned, resolved.Status);

        var ambiguous = await CreateTaskAs(admin, "كرار", "07700000003", svc, op);
        Assert.Null(ambiguous.TechnicianId);
        Assert.Equal(ServiceRequestStatus.Pending, ambiguous.Status);
    }

    [SkippableFact]
    public async Task AssignTask_And_UpdateTask_ResolveOnlyInsideTaskCompany()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var admin = SeedUser(_fx, CompanyA, UserRole.CompanyAdmin, "مدير شركة أ");
        var bSalem = SeedUser(_fx, CompanyB, UserRole.Technician, "سالم");
        var aTask = SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA });
        var aTask2 = SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA });

        await using (var db = _fx.CreateContext(TenantOf(CompanyA)))
        {
            var c = ServiceRequests(db, TenantOf(CompanyA), admin, CompanyAdmin);
            Assert.Equal(200, StatusOf(await c.AssignTask(aTask, new AssignTaskDto { Technician = "سالم", EmployeeId = bSalem })));
        }
        await using (var db = _fx.CreateContext(TenantOf(CompanyA)))
        {
            var c = ServiceRequests(db, TenantOf(CompanyA), admin, CompanyAdmin);
            Assert.Equal(200, StatusOf(await c.UpdateTask(aTask2, new UpdateTaskDto { Technician = "سالم", TechnicianId = bSalem })));
        }

        using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        var t1 = check.Set<ServiceRequest>().Single(r => r.Id == aTask);
        var t2 = check.Set<ServiceRequest>().Single(r => r.Id == aTask2);
        Assert.Null(t1.TechnicianId);
        Assert.NotEqual(bSalem, t1.AssignedToId);
        Assert.Null(t2.TechnicianId);
    }

    [SkippableFact]
    public async Task CompletionFee_GoesToSameCompanyTechnician_NeverToOtherCompanyNamesake()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var admin = SeedUser(_fx, CompanyA, UserRole.CompanyAdmin, "مدير شركة أ");
        var aliB = SeedUser(_fx, CompanyB, UserRole.Technician, "علي"); // created first (old code picked any)
        var aliA = SeedUser(_fx, CompanyA, UserRole.Technician, "علي");
        var task = SeedTask(_fx, svc, op, new TaskSpec
        {
            CompanyId = CompanyA,
            Status = ServiceRequestStatus.InProgress,
            Details = D(("technician", "علي"), ("taskType", "صيانة"), ("deliveryFee", 5000)),
        });

        await using (var db = _fx.CreateContext(TenantOf(CompanyA)))
        {
            var c = ServiceRequests(db, TenantOf(CompanyA), admin, CompanyAdmin);
            Assert.Equal(200, StatusOf(await c.UpdateStatus(task, new UpdateStatusDto { Status = "Completed" })));
        }

        using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        var txs = check.Set<TechnicianTransaction>().Where(t => t.ServiceRequestId == task).ToList();
        Assert.Single(txs);
        Assert.Equal(aliA, txs[0].TechnicianId);
        Assert.Equal(0m, check.Set<User>().Single(u => u.Id == aliB).TechTotalCharges);
    }

    [SkippableFact]
    public async Task CompletionFee_OnlyOtherCompanyNamesake_NoCharge()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var admin = SeedUser(_fx, CompanyA, UserRole.CompanyAdmin, "مدير شركة أ");
        var salemB = SeedUser(_fx, CompanyB, UserRole.Technician, "سالم");
        var task = SeedTask(_fx, svc, op, new TaskSpec
        {
            CompanyId = CompanyA,
            Status = ServiceRequestStatus.InProgress,
            // Even a (corrupt) TechnicianId pointing at company B must not be charged.
            TechnicianId = salemB,
            Details = D(("technician", "سالم"), ("taskType", "صيانة"), ("deliveryFee", 5000)),
        });

        await using (var db = _fx.CreateContext(TenantOf(CompanyA)))
        {
            var c = ServiceRequests(db, TenantOf(CompanyA), admin, CompanyAdmin);
            Assert.Equal(200, StatusOf(await c.UpdateStatus(task, new UpdateStatusDto { Status = "Completed" })));
        }

        using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        Assert.False(check.Set<TechnicianTransaction>().Any(t => t.ServiceRequestId == task));
        Assert.Equal(0m, check.Set<User>().Single(u => u.Id == salemB).TechTotalCharges);
    }

    [SkippableFact]
    public async Task TaskStaff_ReturnsOnlyCallerCompanyStaff()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var tech = SeedUser(_fx, CompanyA, UserRole.Technician, "علي");
        SeedUser(_fx, CompanyA, UserRole.TechnicalLeader, "ليدر أ");
        var foreign = SeedUser(_fx, CompanyB, UserRole.Technician, "فني ب");

        await using var db = _fx.CreateContext(TenantOf(CompanyA));
        var data = Json(await ServiceRequests(db, TenantOf(CompanyA), tech, Technician).GetTaskStaff()).GetProperty("data");
        var ids = data.GetProperty("allStaff").EnumerateArray().Select(e => e.GetProperty("Id").GetGuid()).ToList();

        Assert.Equal(2, ids.Count);
        Assert.DoesNotContain(foreign, ids);
    }

    // ══════════════════════════════════════════════════════════════════════
    // TechnicianTransactions
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task TechTx_CrossCompanyTechnician_IsNotFound_AndUntouched()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var admin = SeedUser(_fx, CompanyA, UserRole.CompanyAdmin, "مدير شركة أ");
        var techB = SeedUser(_fx, CompanyB, UserRole.Technician, "فني ب", techTotalCharges: 100);
        long txId;
        using (var ctx = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            var tx = new TechnicianTransaction
            {
                TechnicianId = techB, Type = TechnicianTransactionType.Charge,
                Category = TechnicianTransactionCategory.Maintenance, Amount = 100,
                Description = "أجور", CompanyId = CompanyB,
            };
            ctx.Set<TechnicianTransaction>().Add(tx);
            ctx.SaveChanges();
            txId = tx.Id;
        }

        await using var db = _fx.CreateContext(TenantOf(CompanyA));
        var c = TechTx(db, TenantOf(CompanyA), admin, CompanyAdmin);

        Assert.Equal(404, StatusOf(await c.GetByTechnician(techB)));
        Assert.Equal(404, StatusOf(await c.RecordPayment(new TechPaymentRequest { TechnicianId = techB, Amount = 50 })));
        Assert.Equal(404, StatusOf(await c.UpdateTransaction(txId, new UpdateTechTransactionRequest { Amount = 1 })));
        Assert.Equal(404, StatusOf(await c.DeleteTransaction(txId)));

        using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        var b = check.Set<User>().Single(u => u.Id == techB);
        Assert.Equal(0m, b.TechTotalPayments);
        var stored = check.Set<TechnicianTransaction>().Single(t => t.Id == txId);
        Assert.Equal(100m, stored.Amount);
        Assert.False(stored.IsDeleted);
    }

    [SkippableFact]
    public async Task RecalculateBalances_CompanyAdmin_OnlyTouchesOwnCompany()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var admin = SeedUser(_fx, CompanyA, UserRole.CompanyAdmin, "مدير شركة أ");
        var techA = SeedUser(_fx, CompanyA, UserRole.Technician, "فني أ", techTotalCharges: 999);
        var techB = SeedUser(_fx, CompanyB, UserRole.Technician, "فني ب", techTotalCharges: 999);
        using (var ctx = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            foreach (var (tech, company) in new[] { (techA, CompanyA), (techB, CompanyB) })
                ctx.Set<TechnicianTransaction>().Add(new TechnicianTransaction
                {
                    TechnicianId = tech, Type = TechnicianTransactionType.Charge,
                    Category = TechnicianTransactionCategory.Maintenance, Amount = 10,
                    Description = "أجور", CompanyId = company,
                });
            ctx.SaveChanges();
        }

        await using (var db = _fx.CreateContext(TenantOf(CompanyA)))
            Assert.Equal(200, StatusOf(await TechTx(db, TenantOf(CompanyA), admin, CompanyAdmin).RecalculateAllBalances()));

        using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        Assert.Equal(10m, check.Set<User>().Single(u => u.Id == techA).TechTotalCharges);
        Assert.Equal(999m, check.Set<User>().Single(u => u.Id == techB).TechTotalCharges); // other company untouched
    }

    /// <summary>Seeds 1140 + a cash account for a company and posts one charge on the technician account.</summary>
    private async Task SeedTechnicianLedger(Guid companyId, Guid technicianId, string accountName, Guid createdBy, decimal charge)
    {
        await using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        var uow = new Sadara.Infrastructure.Repositories.UnitOfWork(ctx);
        await ServiceRequestAccountingHelper.EnsureFixedParentAccount(uow, "1140", "ذمم الفنيين", AccountType.Assets, companyId);
        var cash = await ServiceRequestAccountingHelper.EnsureFixedParentAccount(uow, "4110", "ايراد صيانة", AccountType.Revenue, companyId);
        var techAcct = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(uow, "1140", technicianId, accountName, companyId);
        await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(uow, companyId, createdBy, "أجور",
            JournalReferenceType.Manual, null,
            new() { (techAcct.Id, charge, 0m, "مدين"), (cash.Id, 0m, charge, "دائن") });
    }

    [SkippableFact]
    public async Task AllDues_And_MyTransactions_UseOwnCompanyAccountsOnly()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var adminA = SeedUser(_fx, CompanyA, UserRole.CompanyAdmin, "مدير شركة أ");
        var adminB = SeedUser(_fx, CompanyB, UserRole.CompanyAdmin, "مدير شركة ب");
        var aliA = SeedUser(_fx, CompanyA, UserRole.Technician, "علي");
        var aliB = SeedUser(_fx, CompanyB, UserRole.Technician, "علي");
        await SeedTechnicianLedger(CompanyA, aliA, "علي", adminA, 100m);
        await SeedTechnicianLedger(CompanyB, aliB, "علي", adminB, 999m);

        await using (var db = _fx.CreateContext(TenantOf(CompanyA)))
        {
            var dues = Json(await TechTx(db, TenantOf(CompanyA), adminA, CompanyAdmin).GetAllTechnicianDues(null, null));
            var techs = dues.GetProperty("technicians").EnumerateArray().ToList();
            Assert.Single(techs);
            Assert.Equal(aliA, techs[0].GetProperty("id").GetGuid());
            Assert.Equal(100m, techs[0].GetProperty("totalCharges").GetDecimal());
        }

        await using (var db = _fx.CreateContext(TenantOf(CompanyA)))
        {
            var mine = Json(await TechTx(db, TenantOf(CompanyA), aliA, Technician).GetMyTransactions());
            Assert.Equal(100m, mine.GetProperty("summary").GetProperty("totalCharges").GetDecimal());
        }
    }

    [SkippableFact]
    public async Task AllDues_SuperAdminWithoutCompany_Returns400_TokenWithoutCompany_Returns403()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        await using var db = _fx.CreateContext(SuperTenant);
        Assert.Equal(400, StatusOf(await TechTx(db, SuperTenant, null, SuperAdmin).GetAllTechnicianDues(null, null)));
        Assert.Equal(403, StatusOf(await TechTx(db, NoCompanyTenant, Guid.NewGuid(), CompanyAdmin).GetAllTechnicianDues(null, null)));
    }

    // ══════════════════════════════════════════════════════════════════════
    // SubscriptionLogs
    // ══════════════════════════════════════════════════════════════════════

    private long SeedLog(Guid? companyId, Guid? userId, string? subscriptionId = null, string operationType = "renewal")
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        var log = new SubscriptionLog
        {
            CompanyId = companyId,
            UserId = userId,
            SubscriptionId = subscriptionId,
            OperationType = operationType,
            PlanPrice = 1000,
            ActivationDate = DateTime.UtcNow,
            TechnicianName = "علي",
        };
        ctx.Set<SubscriptionLog>().Add(log);
        ctx.SaveChanges();
        return log.Id;
    }

    [SkippableFact]
    public async Task SubscriptionLogs_ReadsAreCompanyScoped_IncludingLegacyNullCompanyOfOwnUser()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var userA = SeedUser(_fx, CompanyA, UserRole.Employee, "موظف أ");
        var userB = SeedUser(_fx, CompanyB, UserRole.Employee, "موظف ب");
        var a = SeedLog(CompanyA, userA, "S1");
        var legacyA = SeedLog(null, userA, "S1");   // legacy row without company, operator in A
        var b = SeedLog(CompanyB, userB, "S1");
        SeedLog(null, userB, "S1");                 // legacy row of company B

        await using var db = _fx.CreateContext(TenantOf(CompanyA));
        var c = SubLogs(db, TenantOf(CompanyA), userA, Employee);

        var all = Json(await c.GetAll(pageSize: 100));
        var ids = all.GetProperty("data").EnumerateArray().Select(e => e.GetProperty("Id").GetInt64()).ToHashSet();
        Assert.Equal(new HashSet<long> { a, legacyA }, ids);

        var bySub = Json(await c.GetBySubscription("S1")).GetProperty("data").EnumerateArray().Count();
        Assert.Equal(2, bySub);

        // Logs were activated "now" (UTC) ⇒ querying today's UTC date counts exactly the 2 visible ones.
        var stats = Json(await c.GetStats(DateTime.UtcNow.Date)).GetProperty("data");
        Assert.Equal(2, stats.GetProperty("totalOperations").GetInt32());

        Assert.Equal(404, StatusOf(await c.GetById(b)));
        Assert.Equal(404, StatusOf(await c.UpdatePaymentStatus(b, new UpdatePaymentStatusRequest { PaymentStatus = "مسدد" })));

        var bulk = Json(await c.BulkUpdatePaymentStatus(new BulkUpdatePaymentStatusRequest { Ids = new() { a, b }, PaymentStatus = "مسدد" }));
        Assert.Equal(1, bulk.GetProperty("count").GetInt32());

        using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        Assert.Null(check.Set<SubscriptionLog>().Single(l => l.Id == b).PaymentStatus);
    }

    [SkippableFact]
    public async Task SubscriptionLogs_Create_TakesCompanyAndUserFromToken()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var userA = SeedUser(_fx, CompanyA, UserRole.Employee, "موظف أ");
        var userB = SeedUser(_fx, CompanyB, UserRole.Employee, "موظف ب");

        await using var db = _fx.CreateContext(TenantOf(CompanyA));
        var res = await SubLogs(db, TenantOf(CompanyA), userA, Employee).Create(new CreateSubscriptionLogRequest
        {
            CompanyId = CompanyB,
            UserId = userB,
            OperationType = "renewal",
            PlanName = "BASIC",
        });
        Assert.Equal(201, StatusOf(res));

        using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        var log = check.Set<SubscriptionLog>().Single();
        Assert.Equal(CompanyA, log.CompanyId);
        Assert.Equal(userA, log.UserId);
    }

    // ══════════════════════════════════════════════════════════════════════
    // TaskAudits
    // ══════════════════════════════════════════════════════════════════════

    [SkippableFact]
    public async Task TaskAudits_Bulk_IsCompanyScoped_AndForeignTaskCannotBeAudited()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var user = SeedUser(_fx, CompanyA, UserRole.Manager, "مدير أ");
        var aTaskNo = RequestNumberOf(_fx, SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA }));
        var aLegacyNo = RequestNumberOf(_fx, SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA }));
        var bTaskNo = RequestNumberOf(_fx, SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyB }));
        var bLegacyNo = RequestNumberOf(_fx, SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyB }));
        using (var ctx = _fx.CreateContext(PostgresFixture.SystemTenant))
        {
            ctx.Set<TaskAudit>().AddRange(
                new TaskAudit { RequestNumber = aTaskNo, CompanyId = CompanyA, AuditStatus = "تم التدقيق" },
                new TaskAudit { RequestNumber = aLegacyNo, CompanyId = null, AuditStatus = "تم التدقيق" },
                new TaskAudit { RequestNumber = bTaskNo, CompanyId = CompanyB, AuditStatus = "مشكلة" },
                new TaskAudit { RequestNumber = bLegacyNo, CompanyId = null, AuditStatus = "مشكلة" });
            ctx.SaveChanges();
        }

        await using var db = _fx.CreateContext(TenantOf(CompanyA));
        var c = Audits(db, TenantOf(CompanyA), user, "Manager");

        var map = Json(await c.GetBulk()).GetProperty("data");
        var keys = map.EnumerateObject().Select(p => p.Name).ToHashSet();
        Assert.Equal(new HashSet<string> { aTaskNo, aLegacyNo }, keys);

        Assert.Equal(404, StatusOf(await c.SaveAudit(new SaveTaskAuditDto { RequestNumber = bTaskNo, AuditStatus = "تم التدقيق" })));

        using var check = _fx.CreateContext(PostgresFixture.SystemTenant);
        Assert.Equal("مشكلة", check.Set<TaskAudit>().Single(a => a.RequestNumber == bTaskNo).AuditStatus);
    }
}
