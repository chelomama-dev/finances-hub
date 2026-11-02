using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace FinancesHub.Infrastructure.Persistence;

/// <summary>
/// Used only by the dotnet-ef tooling. At runtime Aspire provides the real connection string.
/// </summary>
internal sealed class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<FinancesDbContext>
{
    public FinancesDbContext CreateDbContext(string[] args) =>
        new(new DbContextOptionsBuilder<FinancesDbContext>().UseSqlServer("Server=localhost;Database=financesdb").Options);
}
