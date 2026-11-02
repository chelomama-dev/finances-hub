using FinancesHub.Application.Abstractions;
using FinancesHub.Domain.Banks;
using FinancesHub.Domain.Common;
using FinancesHub.Domain.Connections;

namespace FinancesHub.Application.Queries;

/// <summary>The home screen: total balance, and balance and consent status per linked bank.</summary>
public sealed class GetSummary(IFinanceQueries queries, IConnectionRepository connections, TimeProvider timeProvider)
{
    // Every account is in euros for now (docs/api.md); a balance in another currency is left out of the totals
    public const string Currency = "EUR";

    public async Task<Summary> RunAsync(CancellationToken cancellationToken)
    {
        var now = timeProvider.GetUtcNow();
        var accounts = await queries.ListAccountsAsync(null, cancellationToken);

        // One connection per bank in practice; if a bank was linked twice, the newest one tells its status
        var banks = (await connections.ListAsync(cancellationToken))
            .GroupBy(c => c.BankCode)
            .Select(g => g.MaxBy(c => c.CreatedAt)!)
            // Always in the same order on the home screen, whichever bank was linked first
            .OrderBy(c => Bank.All.ToList().IndexOf(c.Bank))
            .Select(c => new BankSummary(c.Bank, Sum(accounts.Where(a => a.BankCode == c.BankCode).Select(a => a.Balance)), c.StatusAt(now)))
            .ToList();

        return new Summary(
            Sum(accounts.Select(a => a.Balance)),
            accounts.Max(a => a.LastSyncedAt),
            banks);
    }

    private static Money Sum(IEnumerable<Money?> balances) =>
        balances.OfType<Money>().Where(m => m.Currency == Currency).Aggregate(Money.Zero(Currency), (total, m) => total.Add(m));
}

public sealed record Summary(Money TotalBalance, DateTimeOffset? LastSyncedAt, IReadOnlyList<BankSummary> Banks);

public sealed record BankSummary(Bank Bank, Money Balance, ConnectionStatus ConnectionStatus);
