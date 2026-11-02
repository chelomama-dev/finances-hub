using FinancesHub.Domain.Accounts;
using FinancesHub.Domain.Connections;
using FinancesHub.Domain.Transactions;
using Microsoft.EntityFrameworkCore;

namespace FinancesHub.Infrastructure.Persistence;

public sealed class FinancesDbContext(DbContextOptions<FinancesDbContext> options) : DbContext(options)
{
    public DbSet<Connection> Connections => Set<Connection>();
    public DbSet<Account> Accounts => Set<Account>();
    public DbSet<Transaction> Transactions => Set<Transaction>();

    protected override void OnModelCreating(ModelBuilder modelBuilder) =>
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(FinancesDbContext).Assembly);
}
