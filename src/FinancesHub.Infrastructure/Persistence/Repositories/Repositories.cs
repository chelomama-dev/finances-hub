using FinancesHub.Application.Abstractions;
using FinancesHub.Domain.Accounts;
using FinancesHub.Domain.Connections;
using FinancesHub.Domain.Transactions;
using Microsoft.EntityFrameworkCore;

namespace FinancesHub.Infrastructure.Persistence.Repositories;

internal sealed class ConnectionRepository(FinancesDbContext db) : IConnectionRepository
{
    public async Task<IReadOnlyList<Connection>> ListAsync(CancellationToken cancellationToken) =>
        await db.Connections.OrderBy(c => c.CreatedAt).ToListAsync(cancellationToken);

    public async Task<Connection?> GetAsync(Guid id, CancellationToken cancellationToken) =>
        await db.Connections.FindAsync([id], cancellationToken);

    public void Add(Connection connection) => db.Connections.Add(connection);
}

internal sealed class LinkRequestRepository(FinancesDbContext db) : ILinkRequestRepository
{
    public async Task<LinkRequest?> GetAsync(Guid id, CancellationToken cancellationToken) =>
        await db.LinkRequests.FindAsync([id], cancellationToken);

    public void Add(LinkRequest request) => db.LinkRequests.Add(request);

    public void Remove(LinkRequest request) => db.LinkRequests.Remove(request);
}

internal sealed class AccountRepository(FinancesDbContext db) : IAccountRepository
{
    public async Task<IReadOnlyList<Account>> ListByConnectionAsync(Guid connectionId, CancellationToken cancellationToken) =>
        await db.Accounts.Where(a => a.ConnectionId == connectionId).ToListAsync(cancellationToken);

    public void Add(Account account) => db.Accounts.Add(account);
}

internal sealed class TransactionRepository(FinancesDbContext db) : ITransactionRepository
{
    public async Task ReplaceAsync(Guid accountId, DateOnly? from, IReadOnlyList<Transaction> transactions, CancellationToken cancellationToken)
    {
        var stored = db.Transactions.Where(t => t.AccountId == accountId);
        if (from is { } start)
            stored = stored.Where(t => t.BookingDate >= start);

        await stored.ExecuteDeleteAsync(cancellationToken);

        // If the unit of work retries, these are already tracked as added and adding them again does nothing
        db.Transactions.AddRange(transactions);
    }
}
