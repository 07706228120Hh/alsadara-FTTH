using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;

namespace Sadara.API.Startup;

/// <summary>
/// What the application does to the database at boot. Centralized so the decision is explicit,
/// auditable, and unit-testable — and so Production can NEVER auto-migrate.
/// </summary>
public enum StartupDbStrategy
{
    /// <summary>In-memory provider (tests): materialize the schema from the current model.</summary>
    EnsureCreated,

    /// <summary>Development only: apply pending EF Core migrations for developer convenience.</summary>
    Migrate,

    /// <summary>
    /// Production / Staging / any non-Development relational database: do nothing to the schema at
    /// startup. Migrations are applied out-of-band by a deliberate, reviewed process — never by the
    /// running application, so a restart can never mutate the schema or __EFMigrationsHistory.
    /// </summary>
    None
}

/// <summary>
/// Pure decision logic for <see cref="StartupDbStrategy"/>. No framework dependencies so it can be
/// exercised directly in unit tests.
/// </summary>
public static class StartupDatabasePolicy
{
    /// <summary>
    /// Decides the startup database strategy.
    /// <para>
    /// Rules (in order): in-memory ⇒ <see cref="StartupDbStrategy.EnsureCreated"/>;
    /// Development ⇒ <see cref="StartupDbStrategy.Migrate"/>;
    /// everything else (Production, Staging, or an unset environment which ASP.NET Core treats as
    /// Production) ⇒ <see cref="StartupDbStrategy.None"/>.
    /// </para>
    /// </summary>
    /// <param name="isInMemory">True when the configured EF Core provider is the in-memory one.</param>
    /// <param name="isDevelopment">True only for the Development hosting environment.</param>
    public static StartupDbStrategy Decide(bool isInMemory, bool isDevelopment)
    {
        if (isInMemory) return StartupDbStrategy.EnsureCreated;
        if (isDevelopment) return StartupDbStrategy.Migrate;
        return StartupDbStrategy.None;
    }

    /// <summary>
    /// Applies the chosen strategy to <paramref name="database"/>. This is the single place in the
    /// codebase allowed to call EnsureCreated/Migrate at startup, so the behavior — in particular that
    /// <see cref="StartupDbStrategy.None"/> performs no schema or __EFMigrationsHistory mutation — is
    /// covered by real integration tests rather than an inline, untested block.
    /// </summary>
    public static async Task ApplyAsync(DatabaseFacade database, StartupDbStrategy strategy)
    {
        switch (strategy)
        {
            case StartupDbStrategy.EnsureCreated:
                await database.EnsureCreatedAsync();
                break;
            case StartupDbStrategy.Migrate:
                await database.MigrateAsync();
                break;
            case StartupDbStrategy.None:
                // Intentionally nothing: in Production/Staging, migrations are applied out-of-band by a
                // deliberate, reviewed process — never by the running application. Restarting the service
                // therefore cannot mutate the schema or __EFMigrationsHistory.
                break;
        }
    }
}
