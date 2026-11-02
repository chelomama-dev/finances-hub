using FinancesHub.Application.Abstractions;
using FinancesHub.Application.Banking;
using FinancesHub.Domain.Accounts;
using FinancesHub.Domain.Banks;
using FinancesHub.Domain.Common;
using FinancesHub.Domain.Connections;
using FinancesHub.Domain.Transactions;

namespace FinancesHub.Application.Tests.Sync;

// In-memory stand-ins for the database: transactions are committed only when the unit of work finishes
internal sealed class FakeStore : IConnectionRepository, IAccountRepository, ITransactionRepository, IUnitOfWork
{
    public List<Connection> Connections { get; } = [];
    public List<Account> Accounts { get; } = [];
    public List<Transaction> Transactions { get; } = [];
    public int Saves { get; private set; }

    public Task<IReadOnlyList<Connection>> ListAsync(CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<Connection>>(Connections.ToList());

    public void Add(Connection connection) => Connections.Add(connection);

    public Task<IReadOnlyList<Account>> ListByConnectionAsync(Guid connectionId, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<Account>>(Accounts.Where(a => a.ConnectionId == connectionId).ToList());

    public void Add(Account account) => Accounts.Add(account);

    public Task ReplaceAsync(Guid accountId, DateOnly? from, IReadOnlyList<Transaction> transactions, CancellationToken cancellationToken)
    {
        Transactions.RemoveAll(t => t.AccountId == accountId && (from is null || t.BookingDate >= from));
        Transactions.AddRange(transactions);
        return Task.CompletedTask;
    }

    public Task SaveChangesAsync(CancellationToken cancellationToken)
    {
        Saves++;
        return Task.CompletedTask;
    }

    public async Task ExecuteInTransactionAsync(Func<CancellationToken, Task> work, CancellationToken cancellationToken)
    {
        await work(cancellationToken);
        Saves++;
    }
}

internal sealed class FakeBanking : IBankingProvider
{
    public Dictionary<string, bool> AuthorizedSessions { get; } = [];
    public Dictionary<string, Money> Balances { get; } = [];
    public Dictionary<string, List<BankTransaction>> TransactionsByAccount { get; } = [];
    public HashSet<string> FailingAccounts { get; } = [];
    public List<(string Account, DateOnly? From)> TransactionRequests { get; } = [];
    public int Calls { get; private set; }

    public Task<BankAuthorization> StartAuthorizationAsync(Bank bank, Uri redirectUrl, string state, CancellationToken cancellationToken) =>
        throw new NotSupportedException();

    public Task<BankSession> CreateSessionAsync(string code, CancellationToken cancellationToken) =>
        throw new NotSupportedException();

    public Task<bool> IsSessionAuthorizedAsync(string sessionId, CancellationToken cancellationToken)
    {
        Calls++;
        return Task.FromResult(AuthorizedSessions.GetValueOrDefault(sessionId, true));
    }

    public Task<Money> GetBalanceAsync(string providerAccountId, CancellationToken cancellationToken)
    {
        Calls++;
        return FailingAccounts.Contains(providerAccountId)
            ? throw new BankingProviderException("The bank is down.", 503)
            : Task.FromResult(Balances[providerAccountId]);
    }

    public Task<IReadOnlyList<BankTransaction>> GetTransactionsAsync(string providerAccountId, DateOnly? from, CancellationToken cancellationToken)
    {
        Calls++;
        TransactionRequests.Add((providerAccountId, from));
        return Task.FromResult<IReadOnlyList<BankTransaction>>(TransactionsByAccount.GetValueOrDefault(providerAccountId, []));
    }
}

internal sealed class ManualTimeProvider(DateTimeOffset now) : TimeProvider
{
    public DateTimeOffset Now { get; set; } = now;

    public override DateTimeOffset GetUtcNow() => Now;
}
