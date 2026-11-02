using FinancesHub.Domain.Accounts;
using FinancesHub.Domain.Connections;
using FinancesHub.Domain.Transactions;

namespace FinancesHub.Application.Abstractions;

public interface IConnectionRepository
{
    Task<IReadOnlyList<Connection>> ListAsync(CancellationToken cancellationToken);

    Task<Connection?> GetAsync(Guid id, CancellationToken cancellationToken);

    void Add(Connection connection);
}

public interface ILinkRequestRepository
{
    Task<LinkRequest?> GetAsync(Guid id, CancellationToken cancellationToken);

    void Add(LinkRequest request);

    void Remove(LinkRequest request);

    /// <summary>Deletes, right away, requests created before <paramref name="createdBefore"/> that never came back.</summary>
    Task RemoveCreatedBeforeAsync(DateTimeOffset createdBefore, CancellationToken cancellationToken);
}

public interface IAccountRepository
{
    Task<IReadOnlyList<Account>> ListByConnectionAsync(Guid connectionId, CancellationToken cancellationToken);

    void Add(Account account);
}

public interface ITransactionRepository
{
    /// <summary>
    /// Deletes the account's transactions booked on or after <paramref name="from"/> (all of them if it is
    /// <c>null</c>) and adds <paramref name="transactions"/> instead (ADR 0001). The deletion runs right away, so
    /// call it inside <see cref="IUnitOfWork.ExecuteInTransactionAsync"/>.
    /// </summary>
    Task ReplaceAsync(Guid accountId, DateOnly? from, IReadOnlyList<Transaction> transactions, CancellationToken cancellationToken);
}
