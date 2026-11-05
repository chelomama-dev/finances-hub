using FinancesHub.Domain.Accounts;
using FinancesHub.Domain.Common;
using FinancesHub.Domain.Transactions;

namespace FinancesHub.Application.Queries;

/// <summary>Read-only queries for the app's screens. Nothing read through here is tracked or changed.</summary>
public interface IFinanceQueries
{
    /// <summary>Accounts of every linked bank, or only of <paramref name="bankCode"/>.</summary>
    Task<IReadOnlyList<AccountView>> ListAccountsAsync(string? bankCode, CancellationToken cancellationToken);

    /// <summary>
    /// Up to <paramref name="limit"/> transactions of every account newest first, after <paramref name="after"/>
    /// if given, plus one more to know whether there is a next page.
    /// </summary>
    Task<IReadOnlyList<TransactionView>> ListTransactionsAsync(
        TransactionFilter filter, TransactionCursor? after, int limit, CancellationToken cancellationToken);

    /// <summary>Date, amount and description of every transaction in <paramref name="currency"/> between two dates, inclusive.</summary>
    Task<IReadOnlyList<MovementView>> ListMovementsAsync(DateOnly from, DateOnly to, string currency, CancellationToken cancellationToken);
}

public sealed record AccountView(Guid Id, string BankCode, string? Name, Iban? Iban, string Currency, Money? Balance, DateTimeOffset? LastSyncedAt);

public sealed record TransactionView(
    Guid Id, string BankCode, DateOnly BookingDate, Money Amount, string? Description, string? Counterparty, TransactionStatus Status);

/// <param name="Amount">Signed: negative is an expense.</param>
public sealed record MovementView(DateOnly BookingDate, decimal Amount, string? Description);

/// <param name="From">Inclusive.</param>
/// <param name="To">Inclusive.</param>
/// <param name="Direction"><c>null</c> for both.</param>
public sealed record TransactionFilter(DateOnly? From, DateOnly? To, TransactionDirection? Direction);
