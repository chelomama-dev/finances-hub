using FinancesHub.Domain.Accounts;
using FinancesHub.Domain.Common;
using FinancesHub.Domain.Transactions;

namespace FinancesHub.Application.Queries;

/// <summary>Read-only queries for the app's screens. Nothing read through here is tracked or changed.</summary>
public interface IFinanceQueries
{
    /// <summary>Accounts of every linked bank, or only of <paramref name="bankCode"/>.</summary>
    Task<IReadOnlyList<AccountView>> ListAccountsAsync(string? bankCode, CancellationToken cancellationToken);

    Task<bool> AccountExistsAsync(Guid accountId, CancellationToken cancellationToken);

    /// <summary>
    /// Up to <paramref name="limit"/> transactions newest first, after <paramref name="after"/> if given, plus
    /// one more to know whether there is a next page.
    /// </summary>
    Task<IReadOnlyList<TransactionView>> ListTransactionsAsync(
        Guid accountId, TransactionFilter filter, TransactionCursor? after, int limit, CancellationToken cancellationToken);
}

public sealed record AccountView(Guid Id, string BankCode, string? Name, Iban? Iban, string Currency, Money? Balance, DateTimeOffset? LastSyncedAt);

public sealed record TransactionView(Guid Id, DateOnly BookingDate, Money Amount, string? Description, string? Counterparty, TransactionStatus Status);

/// <param name="From">Inclusive.</param>
/// <param name="To">Inclusive.</param>
/// <param name="Direction"><c>null</c> for both.</param>
public sealed record TransactionFilter(DateOnly? From, DateOnly? To, TransactionDirection? Direction);
