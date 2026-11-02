using FinancesHub.Domain.Banks;
using FinancesHub.Domain.Common;

namespace FinancesHub.Application.Banking;

/// <summary>
/// Read-only access to the banks (PSD2 account information). Implemented with Enable Banking in Infrastructure;
/// what each bank sends differently is normalised there, so callers get the same shapes for every bank.
/// </summary>
public interface IBankingProvider
{
    /// <summary>
    /// Starts linking a bank, asking for the longest consent the bank allows. The owner opens the returned URL,
    /// logs in to the bank, and is sent back to the app's configured callback with a code and
    /// <paramref name="state"/>.
    /// </summary>
    Task<BankAuthorization> StartAuthorizationAsync(Bank bank, string state, CancellationToken cancellationToken);

    /// <summary>Exchanges the code from the redirect for a session with the accounts the owner shared.</summary>
    Task<BankSession> CreateSessionAsync(string code, CancellationToken cancellationToken);

    /// <summary>Whether the session can still read data (it may have been revoked from the bank).</summary>
    Task<bool> IsSessionAuthorizedAsync(string sessionId, CancellationToken cancellationToken);

    /// <summary>The account's current balance: the available one if the bank sends it, otherwise the booked one.</summary>
    Task<Money> GetBalanceAsync(string providerAccountId, CancellationToken cancellationToken);

    /// <summary>
    /// Transactions booked from <paramref name="from"/>, or the longest history the bank gives if it is <c>null</c>,
    /// newest first. Either every page is read or it throws: a partial list would make the sync delete
    /// transactions that exist (ADR 0001).
    /// </summary>
    Task<IReadOnlyList<BankTransaction>> GetTransactionsAsync(string providerAccountId, DateOnly? from, CancellationToken cancellationToken);
}
