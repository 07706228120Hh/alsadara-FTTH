using Microsoft.EntityFrameworkCore;
using Npgsql;
using Sadara.API.Startup;
using Sadara.Domain.Entities;
using Sadara.Infrastructure.Data;
using Sadara.Integration.Tests.Support;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// Proves on a real Postgres that the startup strategy behaves correctly end-to-end by invoking the
/// actual <see cref="StartupDatabasePolicy.ApplyAsync"/> the application runs at boot:
///   • None (Production/Staging) touches neither the schema nor __EFMigrationsHistory;
///   • Migrate (Development) really applies migrations to a fresh database;
///   • SeedData.SeedAsync is a no-op on a populated database.
/// Together with <see cref="StartupDatabasePolicyTests"/> this guards against a regression that
/// re-introduces an auto-migration on a Production restart. Skipped cleanly when Docker is unavailable.
/// </summary>
[Collection("Postgres")]
public class StartupMigrationSafetyTests
{
    private readonly PostgresFixture _fx;

    public StartupMigrationSafetyTests(PostgresFixture fx) => _fx = fx;

    /// <summary>
    /// The Production strategy applied for real: ApplyAsync(None) must not create, alter, or remove any
    /// row in a history table — i.e. a restart cannot mutate __EFMigrationsHistory. If someone regresses
    /// the None branch into a Migrate/EnsureCreated call, this test fails (that call would hit the
    /// already-created schema and throw). Runs inside a rolled-back transaction, so nothing persists.
    /// </summary>
    [SkippableFact]
    public async Task ProductionStrategy_None_AppliedForReal_DoesNotTouch_EFMigrationsHistory()
    {
        _fx.SkipIfUnavailable();

        await using var db = _fx.CreateContext(PostgresFixture.SystemTenant);
        await using var tx = await db.Database.BeginTransactionAsync();

        // Arrange: a history table resembling Production — two "already applied" migration rows.
        await db.Database.ExecuteSqlRawAsync(
            "CREATE TABLE \"__EFMigrationsHistory\" (" +
            "\"MigrationId\" varchar(150) NOT NULL PRIMARY KEY, \"ProductVersion\" varchar(32) NOT NULL);");
        await db.Database.ExecuteSqlRawAsync(
            "INSERT INTO \"__EFMigrationsHistory\" (\"MigrationId\", \"ProductVersion\") VALUES " +
            "('20200101000000_A', '9.0.0'), ('20200102000000_B', '9.0.0');");

        // Act: the Production decision, then its real application.
        var strategy = StartupDatabasePolicy.Decide(isInMemory: false, isDevelopment: false);
        Assert.Equal(StartupDbStrategy.None, strategy);
        await StartupDatabasePolicy.ApplyAsync(db.Database, strategy); // the actual startup call — must be a no-op

        // Assert: the history is byte-for-byte unchanged — no row added, removed, or rewritten.
        var ids = await db.Database
            .SqlQueryRaw<string>(
                "SELECT \"MigrationId\" AS \"Value\" FROM \"__EFMigrationsHistory\" ORDER BY \"MigrationId\"")
            .ToListAsync();

        Assert.Equal(new[] { "20200101000000_A", "20200102000000_B" }, ids);

        await tx.RollbackAsync();
    }

    /// <summary>
    /// The Development strategy applied for real: ApplyAsync(Migrate) actually applies the migrations to a
    /// fresh, empty database and records them in __EFMigrationsHistory. Proves Development still follows the
    /// migration policy (and that ApplyAsync routes Migrate correctly). Uses a throwaway database that is
    /// dropped afterwards, so the shared collection database is untouched.
    /// </summary>
    [SkippableFact]
    public async Task DevelopmentStrategy_Migrate_AppliedForReal_PopulatesSchemaAndHistory_OnFreshDatabase()
    {
        _fx.SkipIfUnavailable();

        var dbName = "startup_migrate_test_" + Guid.NewGuid().ToString("N")[..12];
        var targetConnString = new NpgsqlConnectionStringBuilder(_fx.ConnectionString) { Database = dbName }.ToString();

        // CREATE DATABASE cannot run inside a transaction → use a raw connection to the default database.
        await using (var raw = new NpgsqlConnection(_fx.ConnectionString))
        {
            await raw.OpenAsync();
            await using var create = new NpgsqlCommand($"CREATE DATABASE \"{dbName}\";", raw);
            await create.ExecuteNonQueryAsync();
        }

        try
        {
            var strategy = StartupDatabasePolicy.Decide(isInMemory: false, isDevelopment: true);
            Assert.Equal(StartupDbStrategy.Migrate, strategy);

            var options = new DbContextOptionsBuilder<SadaraDbContext>().UseNpgsql(targetConnString).Options;
            await using (var fresh = new SadaraDbContext(options, PostgresFixture.SystemTenant))
                await StartupDatabasePolicy.ApplyAsync(fresh.Database, strategy); // the actual startup call — must migrate

            // __EFMigrationsHistory now exists and records the applied migrations.
            await using (var verify = new SadaraDbContext(options, PostgresFixture.SystemTenant))
            {
                var applied = await verify.Database
                    .SqlQueryRaw<int>("SELECT count(*)::int AS \"Value\" FROM \"__EFMigrationsHistory\"")
                    .SingleAsync();
                Assert.True(applied > 0, "Migrate must record applied migrations in __EFMigrationsHistory.");
            }
        }
        finally
        {
            await using var raw = new NpgsqlConnection(_fx.ConnectionString);
            await raw.OpenAsync();
            await using (var term = new NpgsqlCommand(
                "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = @db AND pid <> pg_backend_pid();", raw))
            {
                term.Parameters.AddWithValue("db", dbName);
                await term.ExecuteNonQueryAsync();
            }
            await using var drop = new NpgsqlCommand($"DROP DATABASE IF EXISTS \"{dbName}\";", raw);
            await drop.ExecuteNonQueryAsync();
        }
    }

    /// <summary>
    /// SeedData.SeedAsync runs on every startup; on a populated database it must change nothing — no new
    /// row, no SuperAdmin re-creation, no password reset. Proven by running it twice (the first run
    /// populates, the second must be a no-op) inside a rolled-back transaction so the shared DB is untouched.
    /// </summary>
    [SkippableFact]
    public async Task SeedData_IsNoOp_OnPopulatedDatabase()
    {
        _fx.SkipIfUnavailable();

        await using var db = _fx.CreateContext(PostgresFixture.SystemTenant);
        await using var tx = await db.Database.BeginTransactionAsync();

        // First seed: brings the database to a populated state (idempotent seeders).
        await SeedData.SeedAsync(db);

        var groups1 = await db.Set<PermissionGroup>().CountAsync();
        var perms1 = await db.Set<Permission>().CountAsync();
        var users1 = await db.Set<User>().IgnoreQueryFilters().CountAsync();
        var adminHash1 = await db.Set<User>().IgnoreQueryFilters()
            .Where(u => u.Email == "admin@sadara.iq")
            .Select(u => u.PasswordHash)
            .FirstOrDefaultAsync();

        // Second seed: must be a complete no-op on the already-populated database.
        await SeedData.SeedAsync(db);

        Assert.Equal(groups1, await db.Set<PermissionGroup>().CountAsync());
        Assert.Equal(perms1, await db.Set<Permission>().CountAsync());
        // No new user (in particular no second SuperAdmin) was created by the re-seed.
        Assert.Equal(users1, await db.Set<User>().IgnoreQueryFilters().CountAsync());
        // The seeded SuperAdmin password is never rewritten (no "Admin@123!" reset on restart).
        var adminHash2 = await db.Set<User>().IgnoreQueryFilters()
            .Where(u => u.Email == "admin@sadara.iq")
            .Select(u => u.PasswordHash)
            .FirstOrDefaultAsync();
        Assert.Equal(adminHash1, adminHash2);

        await tx.RollbackAsync();
    }
}
