using FinancesHub.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Testcontainers.MsSql;

namespace FinancesHub.Infrastructure.Tests.Persistence;

// One SQL Server container for all the persistence tests, with the real migrations applied. Needs Docker
public sealed class SqlServerFixture : IAsyncLifetime
{
    private readonly MsSqlContainer _container = new MsSqlBuilder("mcr.microsoft.com/mssql/server:2022-latest").Build();

    public async ValueTask InitializeAsync()
    {
        await _container.StartAsync();
        await using var db = CreateContext();
        await db.Database.MigrateAsync();
    }

    // Retries on, as Aspire configures them at runtime, so the unit of work runs under the same strategy
    public FinancesDbContext CreateContext() =>
        new(new DbContextOptionsBuilder<FinancesDbContext>()
            .UseSqlServer(_container.GetConnectionString(), sql => sql.EnableRetryOnFailure())
            .Options);

    public ValueTask DisposeAsync() => _container.DisposeAsync();
}

[CollectionDefinition(nameof(SqlServerCollection))]
public sealed class SqlServerCollection : ICollectionFixture<SqlServerFixture>;
