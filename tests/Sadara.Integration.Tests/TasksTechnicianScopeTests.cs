using System.Text.Json;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Integration.Tests.Support;
using Xunit;
using static Sadara.Integration.Tests.Support.TasksIsolationHarness;

namespace Sadara.Integration.Tests;

/// <summary>
/// Phase 0-D follow-up — server-side technician scope (ApplyTechnicianScope):
///  - Details rewritten in the spaced JSON format (<c>"key": "value"</c>) stay visible to their owner;
///  - a stale AssignedToId (TechnicianId = another technician) does NOT expose the task;
///  - AssignedToId still counts when TechnicianId is null.
/// </summary>
[Collection("PostgresTasksIsolation")]
public class TasksTechnicianScopeTests
{
    private readonly PostgresFixture _fx;

    public TasksTechnicianScopeTests(PostgresFixture fx) => _fx = fx;

    private const string Technician = "Technician";

    private static HashSet<Guid> Ids(JsonElement json) =>
        json.GetProperty("data").EnumerateArray().Select(e => e.GetProperty("Id").GetGuid()).ToHashSet();

    /// <summary>Overwrites Details with a raw string (simulates the old jsonb::text rewrite).</summary>
    private void SetRawDetails(Guid taskId, string raw)
    {
        using var ctx = _fx.CreateContext(PostgresFixture.SystemTenant);
        var task = ctx.Set<ServiceRequest>().Single(r => r.Id == taskId);
        task.Details = raw;
        ctx.SaveChanges();
    }

    [SkippableFact]
    public async Task Technician_Scope_SpacedJson_And_AssignedToId_Rules()
    {
        _fx.SkipIfUnavailable();
        Reset(_fx);
        var (svc, op) = SeedServiceAndOperation(_fx);
        var ali = SeedUser(_fx, CompanyA, UserRole.Technician, "علي");
        var hassan = SeedUser(_fx, CompanyA, UserRole.Technician, "حسن");

        // 1) Created by Ali, Details in spaced format, assigned (by name) to Hassan ⇒ visible to Ali via createdById.
        var spacedCreatedById = SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Completed });
        SetRawDetails(spacedCreatedById,
            "{\"technician\": \"حسن\", \"createdById\": \"" + ali + "\", \"createdByName\": \"منشئ آخر\"}");

        // 2) Spaced technician name only ⇒ visible.
        var spacedTechnician = SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA, Status = ServiceRequestStatus.Completed });
        SetRawDetails(spacedTechnician, "{\"taskType\": \"صيانة\", \"technician\": \"علي\"}");

        // 3) Spaced createdByName only ⇒ visible.
        var spacedCreatorName = SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA });
        SetRawDetails(spacedCreatorName, "{\"technician\": \"حسن\", \"createdByName\": \"علي\"}");

        // 4) Technician name stored with a trailing space ⇒ visible.
        var trailingSpace = SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA, Details = new() { ["technician"] = "علي " } });

        // 5) Stale AssignedToId: reassigned to Hassan (TechnicianId + Details) but AssignedToId still Ali ⇒ NOT visible.
        var staleAssigned = SeedTask(_fx, svc, op, new TaskSpec
        {
            CompanyId = CompanyA,
            TechnicianId = hassan,
            AssignedToId = ali,
            TechnicianNameColumn = "حسن",
            Details = new() { ["technician"] = "حسن" },
        });

        // 6) AssignedToId = Ali with no TechnicianId ⇒ visible.
        var assignedNoTechnician = SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA, AssignedToId = ali });

        // 7) A spaced-format task of someone else ⇒ NOT visible.
        var othersSpaced = SeedTask(_fx, svc, op, new TaskSpec { CompanyId = CompanyA });
        SetRawDetails(othersSpaced, "{\"technician\": \"حسن\", \"createdByName\": \"حسن\"}");

        await using var db = _fx.CreateContext(TenantOf(CompanyA));
        var c = ServiceRequests(db, TenantOf(CompanyA), ali, Technician);

        var visible = Ids(Json(await c.GetAll(pageSize: 100)));

        Assert.Contains(spacedCreatedById, visible);
        Assert.Contains(spacedTechnician, visible);
        Assert.Contains(spacedCreatorName, visible);
        Assert.Contains(trailingSpace, visible);
        Assert.Contains(assignedNoTechnician, visible);
        Assert.DoesNotContain(staleAssigned, visible);
        Assert.DoesNotContain(othersSpaced, visible);
        Assert.Equal(5, visible.Count);

        // Same predicate drives statistics and my-assigned.
        var stats = Json(await c.GetStatistics()).GetProperty("data");
        Assert.Equal(5, stats.GetProperty("Total").GetInt32());

        var mine = Ids(Json(await c.GetMyAssigned(pageSize: 100, includeCompleted: true)));
        Assert.DoesNotContain(staleAssigned, mine);
        Assert.Contains(assignedNoTechnician, mine);

        // Hassan still sees the reassigned task (by TechnicianId).
        await using var dbH = _fx.CreateContext(TenantOf(CompanyA));
        var hassanVisible = Ids(Json(await ServiceRequests(dbH, TenantOf(CompanyA), hassan, Technician).GetAll(pageSize: 100)));
        Assert.Contains(staleAssigned, hassanVisible);
    }
}
