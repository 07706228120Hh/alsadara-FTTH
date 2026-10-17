using System.Reflection;
using System.Text;
using DotNet.Testcontainers.Containers;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Data;
using Sadara.Infrastructure.Data.Migrations;
using Sadara.Integration.Tests.Support;
using Testcontainers.PostgreSql;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// Own Postgres container for the Phase 1 / Stream F double-posting indexes.
/// Needs container access (psql inside the container) to run the EF idempotent migration script exactly
/// like deploy/deploy-backend.sh does (single psql run, ON_ERROR_STOP=1), so it cannot reuse PostgresFixture.
/// </summary>
public sealed class DoublePostingFixture : IAsyncLifetime
{
    private const string User = "sadara";
    private PostgreSqlContainer? _container;

    public bool Available { get; private set; }
    public string? SkipReason { get; private set; }
    public string ConnectionString { get; private set; } = string.Empty;

    public async Task InitializeAsync()
    {
        try
        {
            _container = new PostgreSqlBuilder()
                .WithImage("postgres:16-alpine")
                .WithDatabase("sadara_dp")
                .WithUsername(User)
                .WithPassword("sadara_test_pwd")
                .Build();
            await _container.StartAsync();
            ConnectionString = _container.GetConnectionString();
            await using var ctx = CreateContext(ConnectionString);
            await ctx.Database.EnsureCreatedAsync();
            Available = true;
        }
        catch (Exception ex)
        {
            Available = false;
            SkipReason = "Postgres via Testcontainers unavailable (Docker not running?): " + ex.GetType().Name + " — " + ex.Message;
            if (_container is not null)
            {
                try { await _container.DisposeAsync(); } catch { /* ignore */ }
                _container = null;
            }
        }
    }

    public async Task DisposeAsync()
    {
        if (_container is not null) await _container.DisposeAsync();
    }

    public void SkipIfUnavailable() => Skip.IfNot(Available, SkipReason ?? "Postgres test database unavailable.");

    public static SadaraDbContext CreateContext(string connectionString) =>
        new(new DbContextOptionsBuilder<SadaraDbContext>().UseNpgsql(connectionString).Options, PostgresFixture.SystemTenant);

    /// <summary>Creates an empty database in the same container; returns (name, connection string).</summary>
    public async Task<(string Name, string ConnectionString)> CreateDatabaseAsync()
    {
        var name = "dp_" + Guid.NewGuid().ToString("N")[..12];
        await using (var conn = new NpgsqlConnection(ConnectionString))
        {
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand($"CREATE DATABASE \"{name}\"", conn);
            await cmd.ExecuteNonQueryAsync();
        }
        var csb = new NpgsqlConnectionStringBuilder(ConnectionString) { Database = name };
        return (name, csb.ConnectionString);
    }

    /// <summary>Runs a SQL script with psql inside the container, same flags as the production deploy.</summary>
    public async Task<ExecResult> RunPsqlAsync(string database, string sql)
    {
        var path = $"/tmp/{Guid.NewGuid():N}.sql";
        await _container!.CopyAsync(Encoding.UTF8.GetBytes(sql), path);
        return await _container.ExecAsync(new[] { "psql", "-U", User, "-d", database, "-v", "ON_ERROR_STOP=1", "-q", "-f", path });
    }
}

[CollectionDefinition(Name)]
public sealed class DoublePostingCollection : ICollectionFixture<DoublePostingFixture>
{
    public const string Name = "PostgresDoublePosting";
}

/// <summary>
/// Phase 1 / Stream F — DB-level safeguards against double posting:
///  A) UX_SubscriptionLogs_Company_FtthTx          (CompanyId, FtthTransactionId) WHERE FtthTransactionId IS NOT NULL AND NOT IsDeleted
///  B) UX_TechnicianTransactions_ServiceRequest_Category_Charge (ServiceRequestId, Category) WHERE ... AND Type = Charge
/// Part 1 checks the constraint semantics on a schema built from the EF model (as the other suites do).
/// Part 2 runs the real idempotent migration script (as deploy-backend.sh does) against a "pre-migration" database:
/// clean data ⇒ applied; duplicates ⇒ loud abort with nothing applied; re-run ⇒ no-op; rollback script ⇒ indexes dropped.
/// </summary>
[Collection(DoublePostingCollection.Name)]
public class DoublePostingIndexTests
{
    private const string PreviousMigration = "20261012203130_AddPropertyQrTokens";
    private static readonly string MigrationA = MigrationId(typeof(AddUniqueSubscriptionLogFtthTransaction));
    private static readonly string MigrationB = MigrationId(typeof(AddUniqueTechnicianChargePerServiceRequest));

    private readonly DoublePostingFixture _fx;

    public DoublePostingIndexTests(DoublePostingFixture fx) => _fx = fx;

    private static string MigrationId(Type t) => t.GetCustomAttribute<MigrationAttribute>()!.Id;

    // ═══════════════════════════ seeding helpers ═══════════════════════════

    private sealed record Seed(Guid CompanyId, Guid TechnicianId, Guid ServiceRequestId);

    private static Seed SeedBasics(string connectionString)
    {
        using var ctx = DoublePostingFixture.CreateContext(connectionString);
        var companyId = Guid.NewGuid();
        var techId = Guid.NewGuid();
        var srId = Guid.NewGuid();
        ctx.Set<Company>().Add(new Company { Id = companyId, Name = "شركة اختبار", Code = "DP-" + companyId.ToString("N")[..8] });
        var service = new Service { Name = "Internet", NameAr = "إنترنت" };
        var op = new OperationType { Name = "Task", NameAr = "مهمة" };
        ctx.Set<Service>().Add(service);
        ctx.Set<OperationType>().Add(op);
        ctx.Set<User>().Add(new User
        {
            Id = techId,
            Username = $"u{techId:N}"[..12],
            FullName = "فني اختبار",
            PhoneNumber = "07" + Random.Shared.NextInt64(100_000_000, 999_999_999),
            CompanyId = companyId,
            Role = UserRole.Technician,
            IsActive = true,
        });
        ctx.SaveChanges();
        ctx.Set<ServiceRequest>().Add(new ServiceRequest
        {
            Id = srId,
            RequestNumber = "T" + srId.ToString("N")[..12],
            ServiceId = service.Id,
            OperationTypeId = op.Id,
            CompanyId = companyId,
            Status = ServiceRequestStatus.Completed,
            RequestedAt = DateTime.UtcNow,
        });
        ctx.SaveChanges();
        return new Seed(companyId, techId, srId);
    }

    private static SubscriptionLog Log(Guid? companyId, string? ftthTx, bool deleted = false) => new()
    {
        CompanyId = companyId,
        FtthTransactionId = ftthTx,
        CustomerName = "مشترك",
        OperationType = "renewal",
        IsDeleted = deleted,
        DeletedAt = deleted ? DateTime.UtcNow : null,
        CreatedAt = DateTime.UtcNow,
    };

    private static TechnicianTransaction Charge(Seed s, Guid? serviceRequestId, TechnicianTransactionCategory category,
        TechnicianTransactionType type = TechnicianTransactionType.Charge, bool deleted = false) => new()
    {
        TechnicianId = s.TechnicianId,
        CompanyId = s.CompanyId,
        ServiceRequestId = serviceRequestId,
        Type = type,
        Category = category,
        Amount = 1000m,
        Description = "أجور صيانة",
        IsDeleted = deleted,
        DeletedAt = deleted ? DateTime.UtcNow : null,
        CreatedAt = DateTime.UtcNow,
    };

    private static void Insert(string connectionString, params object[] rows)
    {
        using var ctx = DoublePostingFixture.CreateContext(connectionString);
        foreach (var row in rows) ctx.Add(row);
        ctx.SaveChanges();
    }

    private static void AssertUniqueViolation(Action act, string indexName)
    {
        var ex = Assert.Throws<DbUpdateException>(act);
        var pg = Assert.IsType<PostgresException>(ex.InnerException);
        Assert.Equal(PostgresErrorCodes.UniqueViolation, pg.SqlState);
        Assert.Equal(indexName, pg.ConstraintName);
    }

    // ═══════════════════ Part 1 — constraint semantics (EF model schema) ═══════════════════

    [SkippableFact]
    public void SubscriptionLog_SameCompanyAndFtthTransaction_IsRejected()
    {
        _fx.SkipIfUnavailable();
        var s = SeedBasics(_fx.ConnectionString);
        var tx = "ftth-" + Guid.NewGuid().ToString("N");
        Insert(_fx.ConnectionString, Log(s.CompanyId, tx));

        AssertUniqueViolation(() => Insert(_fx.ConnectionString, Log(s.CompanyId, tx)),
            AddUniqueSubscriptionLogFtthTransaction.IndexName);
    }

    [SkippableFact]
    public void SubscriptionLog_NullCompany_DoesNotBypassTheGuard()
    {
        _fx.SkipIfUnavailable();
        var tx = "ftth-" + Guid.NewGuid().ToString("N");
        Insert(_fx.ConnectionString, Log(null, tx));

        AssertUniqueViolation(() => Insert(_fx.ConnectionString, Log(null, tx)),
            AddUniqueSubscriptionLogFtthTransaction.IndexName);
    }

    [SkippableFact]
    public void SubscriptionLog_NonDuplicates_AreAccepted()
    {
        _fx.SkipIfUnavailable();
        var s = SeedBasics(_fx.ConnectionString);
        var other = SeedBasics(_fx.ConnectionString);
        var tx = "ftth-" + Guid.NewGuid().ToString("N");

        Insert(_fx.ConnectionString,
            Log(s.CompanyId, tx),
            Log(other.CompanyId, tx),                              // same operation id, other tenant
            Log(s.CompanyId, tx + "-2"),                           // other operation id
            Log(s.CompanyId, null), Log(s.CompanyId, null));       // legacy rows without FtthTransactionId

        using var ctx = DoublePostingFixture.CreateContext(_fx.ConnectionString);
        Assert.Equal(2, ctx.SubscriptionLogs.Count(l => l.FtthTransactionId == tx));
    }

    [SkippableFact]
    public void SubscriptionLog_SoftDeletedRow_DoesNotConflict()
    {
        _fx.SkipIfUnavailable();
        var s = SeedBasics(_fx.ConnectionString);
        var tx = "ftth-" + Guid.NewGuid().ToString("N");

        Insert(_fx.ConnectionString, Log(s.CompanyId, tx, deleted: true), Log(s.CompanyId, tx, deleted: true));
        Insert(_fx.ConnectionString, Log(s.CompanyId, tx));   // re-post after void is allowed

        // Restoring a deleted duplicate while a live one exists must be rejected.
        using var ctx = DoublePostingFixture.CreateContext(_fx.ConnectionString);
        var deletedRow = ctx.SubscriptionLogs.IgnoreQueryFilters().First(l => l.FtthTransactionId == tx && l.IsDeleted);
        deletedRow.IsDeleted = false;
        AssertUniqueViolation(() => ctx.SaveChanges(), AddUniqueSubscriptionLogFtthTransaction.IndexName);
    }

    [SkippableFact]
    public void TechnicianCharge_SameTaskAndCategory_IsRejected()
    {
        _fx.SkipIfUnavailable();
        var s = SeedBasics(_fx.ConnectionString);
        Insert(_fx.ConnectionString, Charge(s, s.ServiceRequestId, TechnicianTransactionCategory.Maintenance));

        AssertUniqueViolation(
            () => Insert(_fx.ConnectionString, Charge(s, s.ServiceRequestId, TechnicianTransactionCategory.Maintenance)),
            AddUniqueTechnicianChargePerServiceRequest.IndexName);
    }

    [SkippableFact]
    public void TechnicianTransactions_NonDuplicates_AreAccepted()
    {
        _fx.SkipIfUnavailable();
        var s = SeedBasics(_fx.ConnectionString);

        Insert(_fx.ConnectionString,
            Charge(s, s.ServiceRequestId, TechnicianTransactionCategory.Maintenance),
            Charge(s, s.ServiceRequestId, TechnicianTransactionCategory.DeliveryFee),        // other fee category
            Charge(s, s.ServiceRequestId, TechnicianTransactionCategory.Maintenance,
                   TechnicianTransactionType.Payment),                                         // payments are not limited
            Charge(s, s.ServiceRequestId, TechnicianTransactionCategory.Maintenance,
                   TechnicianTransactionType.Adjustment),
            Charge(s, null, TechnicianTransactionCategory.Subscription),                       // no task link
            Charge(s, null, TechnicianTransactionCategory.Subscription));

        using var ctx = DoublePostingFixture.CreateContext(_fx.ConnectionString);
        Assert.Equal(6, ctx.TechnicianTransactions.Count(t => t.TechnicianId == s.TechnicianId));
    }

    [SkippableFact]
    public void TechnicianCharge_SoftDeletedRow_DoesNotConflict()
    {
        _fx.SkipIfUnavailable();
        var s = SeedBasics(_fx.ConnectionString);

        Insert(_fx.ConnectionString,
            Charge(s, s.ServiceRequestId, TechnicianTransactionCategory.Maintenance, deleted: true),
            Charge(s, s.ServiceRequestId, TechnicianTransactionCategory.Maintenance, deleted: true));
        // Cancel → reopen → complete again: the fee is charged again after the old one was reversed.
        Insert(_fx.ConnectionString, Charge(s, s.ServiceRequestId, TechnicianTransactionCategory.Maintenance));

        using var ctx = DoublePostingFixture.CreateContext(_fx.ConnectionString);
        Assert.Equal(1, ctx.TechnicianTransactions.Count(t => t.ServiceRequestId == s.ServiceRequestId));
    }

    [SkippableFact]
    public void ForeignKeyIndex_OnServiceRequestId_IsKept()
    {
        _fx.SkipIfUnavailable();
        using var ctx = DoublePostingFixture.CreateContext(_fx.ConnectionString);
        var count = ctx.Database.SqlQueryRaw<int>(
            "SELECT count(*)::int AS \"Value\" FROM pg_indexes WHERE indexname = 'IX_TechnicianTransactions_ServiceRequestId'")
            .AsEnumerable().Single();
        Assert.Equal(1, count);
    }

    // ═══════════════════ Part 2 — the real migration script (deploy path) ═══════════════════

    /// <summary>Fresh database in the "production before this release" state: no new indexes, history table present.</summary>
    private async Task<(string Name, string Cs, Seed Seed)> PreMigrationDatabaseAsync()
    {
        var (name, cs) = await _fx.CreateDatabaseAsync();
        await using (var ctx = DoublePostingFixture.CreateContext(cs))
        {
            await ctx.Database.EnsureCreatedAsync();
            await ctx.Database.ExecuteSqlRawAsync(
                "DROP INDEX \"UX_SubscriptionLogs_Company_FtthTx\"; " +
                "DROP INDEX \"UX_TechnicianTransactions_ServiceRequest_Category_Charge\"; " +
                "CREATE TABLE \"__EFMigrationsHistory\" (\"MigrationId\" varchar(150) PRIMARY KEY, \"ProductVersion\" varchar(32) NOT NULL); " +
                $"INSERT INTO \"__EFMigrationsHistory\" VALUES ('{PreviousMigration}', '9.0.2');");
        }
        return (name, cs, SeedBasics(cs));
    }

    private static string Script(string cs, string? from, string? to)
    {
        using var ctx = DoublePostingFixture.CreateContext(cs);
        return ctx.GetService<IMigrator>().GenerateScript(from, to, MigrationsSqlGenerationOptions.Idempotent);
    }

    private static string DeployScript(string cs) => Script(cs, PreviousMigration, null);

    private static async Task<(bool A, bool B, int HistoryRows)> StateAsync(string cs)
    {
        await using var conn = new NpgsqlConnection(cs);
        await conn.OpenAsync();
        await using var cmd = new NpgsqlCommand(
            "SELECT " +
            " EXISTS(SELECT 1 FROM pg_index WHERE indexrelid = to_regclass('\"UX_SubscriptionLogs_Company_FtthTx\"') AND indisvalid), " +
            " EXISTS(SELECT 1 FROM pg_index WHERE indexrelid = to_regclass('\"UX_TechnicianTransactions_ServiceRequest_Category_Charge\"') AND indisvalid), " +
            " (SELECT count(*)::int FROM \"__EFMigrationsHistory\" WHERE \"MigrationId\" IN (@a, @b))", conn);
        cmd.Parameters.AddWithValue("a", MigrationA);
        cmd.Parameters.AddWithValue("b", MigrationB);
        await using var r = await cmd.ExecuteReaderAsync();
        await r.ReadAsync();
        return (r.GetBoolean(0), r.GetBoolean(1), r.GetInt32(2));
    }

    [SkippableFact]
    public async Task MigrationScript_CleanData_CreatesBothIndexes_AndRerunIsNoOp()
    {
        _fx.SkipIfUnavailable();
        var (db, cs, s) = await PreMigrationDatabaseAsync();
        var tx = "ftth-" + Guid.NewGuid().ToString("N");
        // Tolerated shapes that exist in production: deleted duplicates, NULL operation ids, duplicate payments.
        Insert(cs, Log(s.CompanyId, tx, deleted: true), Log(s.CompanyId, tx), Log(s.CompanyId, null), Log(s.CompanyId, null),
            Charge(s, s.ServiceRequestId, TechnicianTransactionCategory.Maintenance, deleted: true),
            Charge(s, s.ServiceRequestId, TechnicianTransactionCategory.Maintenance),
            Charge(s, s.ServiceRequestId, TechnicianTransactionCategory.Maintenance, TechnicianTransactionType.Payment),
            Charge(s, s.ServiceRequestId, TechnicianTransactionCategory.Maintenance, TechnicianTransactionType.Payment));

        var script = DeployScript(cs);
        Assert.DoesNotContain("CONCURRENTLY ON", script); // never inside the transactional deploy script

        var first = await _fx.RunPsqlAsync(db, script);
        Assert.True(first.ExitCode == 0, first.Stderr);
        Assert.Equal((true, true, 2), await StateAsync(cs));

        var second = await _fx.RunPsqlAsync(db, DeployScript(cs));
        Assert.True(second.ExitCode == 0, second.Stderr);
        Assert.Equal((true, true, 2), await StateAsync(cs));

        // The applied index really guards the data.
        AssertUniqueViolation(() => Insert(cs, Log(s.CompanyId, tx)), AddUniqueSubscriptionLogFtthTransaction.IndexName);
    }

    [SkippableFact]
    public async Task MigrationScript_DuplicateSubscriptionLogs_AbortsLoudly_NothingApplied()
    {
        _fx.SkipIfUnavailable();
        var (db, cs, s) = await PreMigrationDatabaseAsync();
        var tx = "ftth-" + Guid.NewGuid().ToString("N");
        Insert(cs, Log(s.CompanyId, tx), Log(s.CompanyId, tx), Log(s.CompanyId, tx));

        var result = await _fx.RunPsqlAsync(db, DeployScript(cs));

        Assert.NotEqual(0, result.ExitCode);
        Assert.Contains("UX_SubscriptionLogs_Company_FtthTx: 1 duplicate live (CompanyId, FtthTransactionId) groups (3 rows)", result.Stderr);
        Assert.Contains("Migration aborted, nothing applied", result.Stderr);
        Assert.Equal((false, false, 0), await StateAsync(cs)); // B not applied either: one deploy transaction
    }

    [SkippableFact]
    public async Task MigrationScript_DuplicateTaskFee_AbortsLoudly_AndRollsBackMigrationA()
    {
        _fx.SkipIfUnavailable();
        var (db, cs, s) = await PreMigrationDatabaseAsync();
        Insert(cs,
            Charge(s, s.ServiceRequestId, TechnicianTransactionCategory.Maintenance),
            Charge(s, s.ServiceRequestId, TechnicianTransactionCategory.Maintenance));

        var result = await _fx.RunPsqlAsync(db, DeployScript(cs));

        Assert.NotEqual(0, result.ExitCode);
        Assert.Contains("UX_TechnicianTransactions_ServiceRequest_Category_Charge: 1 duplicate live task-fee charge groups (2 rows)", result.Stderr);
        Assert.Equal((false, false, 0), await StateAsync(cs)); // A (which succeeded) was rolled back too
    }

    /// <summary>Marks every migration before this release as applied, so MigrateAsync only runs A and B.</summary>
    private static async Task MarkAllEarlierMigrationsAppliedAsync(string cs)
    {
        await using var ctx = DoublePostingFixture.CreateContext(cs);
        foreach (var id in ctx.Database.GetMigrations().Where(m => string.CompareOrdinal(m, PreviousMigration) < 0))
            await ctx.Database.ExecuteSqlRawAsync(
                "INSERT INTO \"__EFMigrationsHistory\" VALUES ({0}, '9.0.2') ON CONFLICT DO NOTHING", id);
    }

    [SkippableFact]
    public async Task MigrateAsync_CleanData_Applies_DuplicateData_ThrowsClearError()
    {
        _fx.SkipIfUnavailable();

        var (_, cleanCs, _) = await PreMigrationDatabaseAsync();
        await MarkAllEarlierMigrationsAppliedAsync(cleanCs);
        await using (var ctx = DoublePostingFixture.CreateContext(cleanCs))
            await ctx.Database.MigrateAsync();
        Assert.Equal((true, true, 2), await StateAsync(cleanCs));

        var (_, dupCs, s) = await PreMigrationDatabaseAsync();
        await MarkAllEarlierMigrationsAppliedAsync(dupCs);
        Insert(dupCs,
            Charge(s, s.ServiceRequestId, TechnicianTransactionCategory.InstallationFee),
            Charge(s, s.ServiceRequestId, TechnicianTransactionCategory.InstallationFee));
        await using (var ctx = DoublePostingFixture.CreateContext(dupCs))
        {
            var ex = await Assert.ThrowsAsync<PostgresException>(() => ctx.Database.MigrateAsync());
            Assert.Contains("UX_TechnicianTransactions_ServiceRequest_Category_Charge", ex.MessageText);
            Assert.Contains("Migration aborted", ex.MessageText);
        }
        // EF Core 9 runs all pending migrations in ONE transaction ⇒ A is rolled back too; Program.cs logs the
        // error ("Migration note: ...") and the API keeps running on the old schema.
        Assert.Equal((false, false, 0), await StateAsync(dupCs));
    }

    [SkippableFact]
    public async Task MigrationScript_IndexPreBuiltConcurrently_IsKept()
    {
        _fx.SkipIfUnavailable();
        var (db, cs, _) = await PreMigrationDatabaseAsync();
        // Owner's optional zero-blocking path: build the index CONCURRENTLY (outside any transaction) before deploying.
        var manual = await _fx.RunPsqlAsync(db,
            "CREATE UNIQUE INDEX CONCURRENTLY \"UX_SubscriptionLogs_Company_FtthTx\" ON \"SubscriptionLogs\" " +
            "(\"CompanyId\", \"FtthTransactionId\") NULLS NOT DISTINCT WHERE \"FtthTransactionId\" IS NOT NULL AND NOT \"IsDeleted\";");
        Assert.True(manual.ExitCode == 0, manual.Stderr);

        var result = await _fx.RunPsqlAsync(db, DeployScript(cs));
        Assert.True(result.ExitCode == 0, result.Stderr);
        Assert.Equal((true, true, 2), await StateAsync(cs));
    }

    [SkippableFact]
    public async Task RollbackScript_DropsBothIndexes_AndHistoryRows()
    {
        _fx.SkipIfUnavailable();
        var (db, cs, _) = await PreMigrationDatabaseAsync();
        var up = await _fx.RunPsqlAsync(db, DeployScript(cs));
        Assert.True(up.ExitCode == 0, up.Stderr);

        var rollback = Script(cs, MigrationB, PreviousMigration);
        var down = await _fx.RunPsqlAsync(db, rollback);
        Assert.True(down.ExitCode == 0, down.Stderr);
        Assert.Equal((false, false, 0), await StateAsync(cs));

        // The pre-existing FK index survives the rollback.
        await using var ctx = DoublePostingFixture.CreateContext(cs);
        Assert.Equal(1, ctx.Database.SqlQueryRaw<int>(
            "SELECT count(*)::int AS \"Value\" FROM pg_indexes WHERE indexname = 'IX_TechnicianTransactions_ServiceRequestId'")
            .AsEnumerable().Single());
    }

    // ═══════════════════ Part 3 — the owner-run SQL scripts (docs/tasks-finance-fix/sql) ═══════════════════

    private static string SqlScript(string fileName)
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "SadaraPlatform.sln")))
            dir = dir.Parent;
        Assert.NotNull(dir);
        return File.ReadAllText(Path.Combine(dir!.FullName, "docs", "tasks-finance-fix", "sql", fileName));
    }

    private static string Replace(string script, string marker, string replacement)
    {
        Assert.Contains(marker, script);
        return script.Replace(marker, replacement);
    }

    private static int LiveCount(string cs, Func<IQueryable<TechnicianTransaction>, IQueryable<TechnicianTransaction>> q)
    {
        using var ctx = DoublePostingFixture.CreateContext(cs);
        return q(ctx.TechnicianTransactions).Count();
    }

    [SkippableFact]
    public async Task Script01_DryRunChangesNothing_CommitResolvesDuplicate_ThenMigrationApplies()
    {
        _fx.SkipIfUnavailable();
        var (db, cs, s) = await PreMigrationDatabaseAsync();
        var first = Charge(s, s.ServiceRequestId, TechnicianTransactionCategory.Maintenance);
        Insert(cs, first);
        var second = Charge(s, s.ServiceRequestId, TechnicianTransactionCategory.Maintenance);
        second.CreatedAt = first.CreatedAt.AddMilliseconds(3);
        Insert(cs, second, Charge(s, s.ServiceRequestId, TechnicianTransactionCategory.Maintenance, TechnicianTransactionType.Payment));

        var script01 = SqlScript("01_resolve_duplicate_task_fee.sql");

        var dry = await _fx.RunPsqlAsync(db, script01);
        Assert.True(dry.ExitCode == 0, dry.Stderr);
        Assert.Equal(2, LiveCount(cs, q => q.Where(t => t.ServiceRequestId == s.ServiceRequestId && t.Type == TechnicianTransactionType.Charge)));

        var commit = Replace(script01, "ROLLBACK;   -- dry run by default.", "COMMIT;   --");
        var applied = await _fx.RunPsqlAsync(db, commit);
        Assert.True(applied.ExitCode == 0, applied.Stderr);

        await using (var ctx = DoublePostingFixture.CreateContext(cs))
        {
            var rows = ctx.TechnicianTransactions.IgnoreQueryFilters()
                .Where(t => t.ServiceRequestId == s.ServiceRequestId && t.Type == TechnicianTransactionType.Charge)
                .OrderBy(t => t.Id).ToList();
            Assert.False(rows[0].IsDeleted);                       // earliest kept
            Assert.True(rows[1].IsDeleted);                        // later one soft-deleted with a reversal note
            Assert.Contains("#" + rows[0].Id, rows[1].Notes);
            var audited = ctx.Database.SqlQueryRaw<string>(
                "SELECT row_id AS \"Value\" FROM finance_fix_audit.affected_rows WHERE script = '01_resolve_duplicate_task_fee'")
                .ToList();
            Assert.Equal(new[] { rows[1].Id.ToString() }, audited);
        }

        // Re-running finds 0 rows ≠ expected 1 ⇒ aborts loudly instead of silently "succeeding".
        var rerun = await _fx.RunPsqlAsync(db, commit);
        Assert.NotEqual(0, rerun.ExitCode);
        Assert.Contains("01 aborted", rerun.Stderr);

        var deploy = await _fx.RunPsqlAsync(db, DeployScript(cs));
        Assert.True(deploy.ExitCode == 0, deploy.Stderr);
        Assert.Equal((true, true, 2), await StateAsync(cs));
    }

    [SkippableFact]
    public async Task Script02_ReadOnlyReport_Runs_AndScript03Draft_RefusesWithoutApproval()
    {
        _fx.SkipIfUnavailable();
        var (db, cs, s) = await PreMigrationDatabaseAsync();
        var (postedJe, voidedJe) = SeedJournalEntries(cs, s);
        Insert(cs,
            SubCharge(s, "500", postedJe), SubCharge(s, "500", Guid.NewGuid() /* JE hard-deleted */), SubCharge(s, "500", voidedJe),
            SubCharge(s, "600", Guid.NewGuid()), SubCharge(s, "600", Guid.NewGuid()));   // ambiguous: no live posting

        var report = await _fx.RunPsqlAsync(db, "SET default_transaction_read_only = on;\n" + SqlScript("02_report_duplicate_subscription_charges_readonly.sql"));
        Assert.True(report.ExitCode == 0, report.Stderr);
        Assert.Contains("MANUAL REVIEW (ambiguous group)", report.Stdout);

        var draft = await _fx.RunPsqlAsync(db, SqlScript("03_DRAFT_cleanup_duplicate_subscription_charges.sql"));
        Assert.NotEqual(0, draft.ExitCode);
        Assert.Contains("DRAFT and is not approved", draft.Stderr);
        Assert.Equal(5, LiveCount(cs, q => q.Where(t => t.TechnicianId == s.TechnicianId)));

        // Approved + committed variant (as the owner would run it after the Phase 4 decision): only the two
        // reversed rows of log 500 go; the posted one and the ambiguous group stay.
        var approved = SqlScript("03_DRAFT_cleanup_duplicate_subscription_charges.sql");
        approved = Replace(approved, "\\set expected_rows 247", "\\set expected_rows 2");
        approved = Replace(approved, "\\set approve 'NOT-APPROVED'", "\\set approve 'yes-owner-approved'");
        approved = Replace(approved, "ROLLBACK;   -- DRAFT:", "COMMIT;   --");
        var run = await _fx.RunPsqlAsync(db, approved);
        Assert.True(run.ExitCode == 0, run.Stderr);
        await using (var ctx = DoublePostingFixture.CreateContext(cs))
        {
            var kept = Assert.Single(ctx.TechnicianTransactions.Where(t => t.ReferenceNumber == "500"));
            Assert.Equal(postedJe, kept.JournalEntryId);
        }
        Assert.Equal(2, LiveCount(cs, q => q.Where(t => t.ReferenceNumber == "600")));
    }

    [SkippableFact]
    public async Task Script99_EmergencyRollback_DropsIndexes_KeepsHistory()
    {
        _fx.SkipIfUnavailable();
        var (db, cs, _) = await PreMigrationDatabaseAsync();
        var up = await _fx.RunPsqlAsync(db, DeployScript(cs));
        Assert.True(up.ExitCode == 0, up.Stderr);

        var drop = await _fx.RunPsqlAsync(db, SqlScript("99_rollback_indexes.sql"));
        Assert.True(drop.ExitCode == 0, drop.Stderr);
        Assert.Equal((false, false, 2), await StateAsync(cs)); // history kept ⇒ startup MigrateAsync won't re-create
    }

    private static TechnicianTransaction SubCharge(Seed s, string subscriptionLogId, Guid journalEntryId)
    {
        var tx = Charge(s, null, TechnicianTransactionCategory.Subscription);
        tx.ReferenceNumber = subscriptionLogId;
        tx.JournalEntryId = journalEntryId;
        return tx;
    }

    private static (Guid Posted, Guid Voided) SeedJournalEntries(string cs, Seed s)
    {
        using var ctx = DoublePostingFixture.CreateContext(cs);
        var posted = new JournalEntry { Id = Guid.NewGuid(), EntryNumber = "JE-P", CompanyId = s.CompanyId, CreatedById = s.TechnicianId, Status = JournalEntryStatus.Posted };
        var voided = new JournalEntry { Id = Guid.NewGuid(), EntryNumber = "JE-V", CompanyId = s.CompanyId, CreatedById = s.TechnicianId, Status = JournalEntryStatus.Voided, IsDeleted = true };
        ctx.AddRange(posted, voided);
        ctx.SaveChanges();
        return (posted.Id, voided.Id);
    }
}
