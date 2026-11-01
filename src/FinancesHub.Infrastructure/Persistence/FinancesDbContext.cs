using Microsoft.EntityFrameworkCore;

namespace FinancesHub.Infrastructure.Persistence;

public sealed class FinancesDbContext(DbContextOptions<FinancesDbContext> options) : DbContext(options)
{
    protected override void OnModelCreating(ModelBuilder modelBuilder) =>
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(FinancesDbContext).Assembly);
}
