using Sadara.API.Startup;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// Pure-logic tests for the startup database strategy — no database or Docker required, so they always
/// run (never skipped). They lock in the critical invariant: a Production (non-Development) relational
/// database is NEVER auto-migrated by the application at boot. This is the regression guard for the
/// fix that stops the service from running Database.MigrateAsync() on every Production restart.
/// </summary>
public class StartupDatabasePolicyTests
{
    [Fact]
    public void Production_RelationalDb_IsNeverMigratedAtStartup()
    {
        // Production hosting environment (IsDevelopment == false), a real relational database.
        var strategy = StartupDatabasePolicy.Decide(isInMemory: false, isDevelopment: false);

        Assert.Equal(StartupDbStrategy.None, strategy);
        Assert.NotEqual(StartupDbStrategy.Migrate, strategy);
    }

    [Fact]
    public void Development_RelationalDb_AppliesMigrations()
    {
        var strategy = StartupDatabasePolicy.Decide(isInMemory: false, isDevelopment: true);

        Assert.Equal(StartupDbStrategy.Migrate, strategy);
    }

    [Fact]
    public void InMemory_CreatesSchema_RegardlessOfEnvironment()
    {
        Assert.Equal(StartupDbStrategy.EnsureCreated,
            StartupDatabasePolicy.Decide(isInMemory: true, isDevelopment: false));
        Assert.Equal(StartupDbStrategy.EnsureCreated,
            StartupDatabasePolicy.Decide(isInMemory: true, isDevelopment: true));
    }

    [Theory]
    // The ONLY combination that may migrate is (relational + Development). Everything else must not.
    [InlineData(false, false, false)] // Production, relational  → must NOT migrate
    [InlineData(false, true, true)]   // Development, relational → migrates
    [InlineData(true, false, false)]  // in-memory               → EnsureCreated, not migrate
    [InlineData(true, true, false)]   // in-memory               → EnsureCreated, not migrate
    public void OnlyDevelopmentRelational_Migrates(bool isInMemory, bool isDevelopment, bool expectMigrate)
    {
        var strategy = StartupDatabasePolicy.Decide(isInMemory, isDevelopment);

        Assert.Equal(expectMigrate, strategy == StartupDbStrategy.Migrate);
    }
}
