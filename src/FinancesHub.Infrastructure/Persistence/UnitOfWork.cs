using FinancesHub.Application.Abstractions;
using Microsoft.EntityFrameworkCore;

namespace FinancesHub.Infrastructure.Persistence;

internal sealed class UnitOfWork(FinancesDbContext db) : IUnitOfWork
{
    public Task SaveChangesAsync(CancellationToken cancellationToken) => db.SaveChangesAsync(cancellationToken);

    public Task ExecuteInTransactionAsync(Func<CancellationToken, Task> work, CancellationToken cancellationToken)
    {
        // Aspire turns on retries for transient SQL errors, and a retrying strategy only allows an explicit
        // transaction when the whole block runs through it, so a retry repeats the block from the start
        var strategy = db.Database.CreateExecutionStrategy();
        return strategy.ExecuteAsync(async ct =>
        {
            await using var transaction = await db.Database.BeginTransactionAsync(ct);
            await work(ct);
            await db.SaveChangesAsync(ct);
            await transaction.CommitAsync(ct);
        }, cancellationToken);
    }
}
