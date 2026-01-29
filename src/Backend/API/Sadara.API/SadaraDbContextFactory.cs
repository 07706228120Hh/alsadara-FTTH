using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using Microsoft.Extensions.Configuration;
using Sadara.Infrastructure.Data;

namespace Sadara.API;

/// <summary>
/// Design-time factory for creating SadaraDbContext during migrations
/// This is used by EF Core tools when running migrations from command line
/// </summary>
public class SadaraDbContextFactory : IDesignTimeDbContextFactory<SadaraDbContext>
{
    public SadaraDbContext CreateDbContext(string[] args)
    {
        // Build configuration
        var configuration = new ConfigurationBuilder()
            .SetBasePath(Directory.GetCurrentDirectory())
            .AddJsonFile("appsettings.json", optional: false)
            .AddJsonFile("appsettings.Development.json", optional: true)
            .AddEnvironmentVariables()
            .Build();

        var optionsBuilder = new DbContextOptionsBuilder<SadaraDbContext>();
        
        var connectionString = configuration.GetConnectionString("DefaultConnection");
        
        if (!string.IsNullOrEmpty(connectionString))
        {
            // Use PostgreSQL in production/development
            optionsBuilder.UseNpgsql(connectionString);
        }
        else
        {
            // Fallback: Use a default PostgreSQL connection for migrations
            // This is typically used when no appsettings.json connection string exists
            optionsBuilder.UseNpgsql("Host=localhost;Port=5432;Database=SadaraDb;Username=postgres;Password=postgres");
        }

        return new SadaraDbContext(optionsBuilder.Options);
    }
}
