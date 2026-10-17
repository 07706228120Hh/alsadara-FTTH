using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Sadara.API.Controllers;
using Sadara.Application.Interfaces;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Data;
using Sadara.Infrastructure.Repositories;
using Xunit;

namespace Sadara.Integration.Tests.Support;

/// <summary>
/// Dedicated Postgres collection for the Phase 0-D tasks/finance isolation tests. It owns its own
/// container so its broader data (users, accounts, transactions, logs, audits) never collides with
/// the summary tests' "DELETE FROM Users" reset in the shared "Postgres" collection.
/// </summary>
[CollectionDefinition("PostgresTasksIsolation")]
public sealed class PostgresTasksIsolationCollection : ICollectionFixture<PostgresFixture>
{
}

/// <summary>No-op FCM sender (the real one needs Firebase).</summary>
public sealed class NoopFcm : IFcmNotificationService
{
    public Task SendToUserAsync(Guid userId, string title, string body, Dictionary<string, string>? data = null) => Task.CompletedTask;
    public Task SendToUsersAsync(IEnumerable<Guid> userIds, string title, string body, Dictionary<string, string>? data = null) => Task.CompletedTask;
}

/// <summary>
/// Builders/seeders for the Phase 0-D isolation tests: real controllers over a real UnitOfWork on
/// Postgres, with the tenant and token claims under test control.
/// </summary>
public static class TasksIsolationHarness
{
    public static readonly Guid CompanyA = Guid.Parse("aaaaaaaa-0000-0000-0000-00000000000a");
    public static readonly Guid CompanyB = Guid.Parse("bbbbbbbb-0000-0000-0000-00000000000b");

    // ═══════ tenants ═══════

    public static TestTenant TenantOf(Guid companyId) => new() { CompanyId = companyId };
    public static TestTenant SuperTenant => new() { IsSuperAdmin = true, BypassTenantFilter = true };
    public static TestTenant NoCompanyTenant => new() { CompanyId = null };

    // ═══════ controllers ═══════

    private static ControllerContext Context(Guid? userId, string? role)
    {
        // Deliberately no "company_id" claim: the controllers read the company from ICurrentTenant,
        // and SignalR notifications (TaskHubNotifier, passed as null) are only sent when that claim exists.
        var claims = new List<Claim>();
        if (userId.HasValue)
            claims.Add(new Claim(ClaimTypes.NameIdentifier, userId.Value.ToString()));
        if (role is not null)
            claims.Add(new Claim(ClaimTypes.Role, role));
        return new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(new ClaimsIdentity(claims, authenticationType: "TestAuth"))
            }
        };
    }

    public static ServiceRequestsController ServiceRequests(SadaraDbContext db, ICurrentTenant tenant, Guid? userId, string? role)
        => new(
            unitOfWork: new UnitOfWork(db),
            logger: NullLogger<ServiceRequestsController>.Instance,
            fcmService: new NoopFcm(),
            taskHubNotifier: null!,
            db: db,
            tenant: tenant,
            configuration: new ConfigurationBuilder().Build())
        {
            ControllerContext = Context(userId, role)
        };

    public static TechnicianTransactionsController TechTx(SadaraDbContext db, ICurrentTenant tenant, Guid? userId, string? role)
        => new(new UnitOfWork(db), NullLogger<TechnicianTransactionsController>.Instance, tenant)
        {
            ControllerContext = Context(userId, role)
        };

    public static SubscriptionLogsController SubLogs(SadaraDbContext db, ICurrentTenant tenant, Guid? userId, string? role)
        => new(new UnitOfWork(db), NullLogger<SubscriptionLogsController>.Instance, tenant)
        {
            ControllerContext = Context(userId, role)
        };

    public static TaskAuditsController Audits(SadaraDbContext db, ICurrentTenant tenant, Guid? userId, string? role)
        => new(new UnitOfWork(db), NullLogger<TaskAuditsController>.Instance, tenant)
        {
            ControllerContext = Context(userId, role)
        };

    // ═══════ results ═══════

    public static int StatusOf(IActionResult result) => result switch
    {
        ObjectResult o => o.StatusCode ?? 200,
        StatusCodeResult s => s.StatusCode,
        _ => throw new Xunit.Sdk.XunitException($"Unexpected result {result.GetType().Name}")
    };

    /// <summary>Serialises the ObjectResult value to JSON (anonymous types keep their property names).</summary>
    public static JsonElement Json(IActionResult result)
    {
        var o = result as ObjectResult
            ?? throw new Xunit.Sdk.XunitException($"Expected ObjectResult, got {result.GetType().Name}");
        return JsonSerializer.SerializeToElement(o.Value);
    }

    // ═══════ reset / seed ═══════

    public static void Reset(PostgresFixture fx)
    {
        using var ctx = fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Database.ExecuteSqlRaw(
            "TRUNCATE \"TaskAudits\", \"SubscriptionLogs\", \"TechnicianTransactions\", \"JournalEntryLines\", " +
            "\"JournalEntries\", \"Accounts\", \"Notifications\", \"ServiceRequestStatusHistories\", " +
            "\"ServiceRequests\", \"DepartmentTasks\", \"Departments\", \"Users\", \"Companies\" CASCADE;");
        ctx.Set<Company>().AddRange(
            new Company { Id = CompanyA, Name = "شركة أ", Code = "ISO-A" },
            new Company { Id = CompanyB, Name = "شركة ب", Code = "ISO-B" });
        ctx.SaveChanges();
    }

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

    public static Guid SeedUser(PostgresFixture fx, Guid? companyId, UserRole role, string fullName,
        decimal techTotalCharges = 0, decimal techTotalPayments = 0)
    {
        var id = Guid.NewGuid();
        using var ctx = fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<User>().Add(new User
        {
            Id = id,
            Username = $"u{id:N}".Substring(0, 12),
            FullName = fullName,
            PhoneNumber = "07" + Random.Shared.NextInt64(100_000_000, 999_999_999),
            CompanyId = companyId,
            Role = role,
            IsActive = true,
            TechTotalCharges = techTotalCharges,
            TechTotalPayments = techTotalPayments,
            TechNetBalance = techTotalPayments - techTotalCharges,
        });
        ctx.SaveChanges();
        return id;
    }

    public sealed class TaskSpec
    {
        public Guid? CompanyId { get; init; }
        public ServiceRequestStatus Status { get; init; } = ServiceRequestStatus.Pending;
        public Guid? TechnicianId { get; init; }
        public Guid? AssignedToId { get; init; }
        /// <summary>Normalized column. Left null to simulate the ~28% backfill gap.</summary>
        public string? TechnicianNameColumn { get; init; }
        public Dictionary<string, object?>? Details { get; init; }
        public string? ContactPhone { get; init; }
    }

    public static Guid SeedTask(PostgresFixture fx, int serviceId, int operationTypeId, TaskSpec spec)
    {
        var id = Guid.NewGuid();
        using var ctx = fx.CreateContext(PostgresFixture.SystemTenant);
        ctx.Set<ServiceRequest>().Add(new ServiceRequest
        {
            Id = id,
            RequestNumber = "T" + id.ToString("N").Substring(0, 12),
            ServiceId = serviceId,
            OperationTypeId = operationTypeId,
            CompanyId = spec.CompanyId,
            Status = spec.Status,
            TechnicianId = spec.TechnicianId,
            AssignedToId = spec.AssignedToId,
            TechnicianName = spec.TechnicianNameColumn,
            ContactPhone = spec.ContactPhone,
            Details = spec.Details is null
                ? null
                : JsonSerializer.Serialize(spec.Details, new JsonSerializerOptions
                {
                    Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
                }),
            RequestedAt = DateTime.UtcNow,
            CreatedAt = DateTime.UtcNow,
        });
        ctx.SaveChanges();
        return id;
    }

    public static string RequestNumberOf(PostgresFixture fx, Guid taskId)
    {
        using var ctx = fx.CreateContext(PostgresFixture.SystemTenant);
        return ctx.Set<ServiceRequest>().Where(r => r.Id == taskId).Select(r => r.RequestNumber).Single();
    }
}
