using FinancesHub.Domain.Accounts;
using FinancesHub.Domain.Common;
using FinancesHub.Domain.Transactions;

namespace FinancesHub.Application.Banking;

public sealed record BankAuthorization(Uri Url, DateTimeOffset ConsentValidUntil);

public sealed record BankSession(string SessionId, DateTimeOffset ValidUntil, IReadOnlyList<BankAccount> Accounts);

/// <param name="ProviderAccountId">The account's <c>uid</c>, valid only within this session.</param>
public sealed record BankAccount(string ProviderAccountId, Iban? Iban, string? Name, string Currency);

/// <param name="Amount">Signed: negative is an expense, whatever sign the bank used.</param>
public sealed record BankTransaction(
    DateOnly BookingDate,
    DateOnly? ValueDate,
    Money Amount,
    string? Description,
    string? Counterparty,
    TransactionStatus Status);

/// <summary>
/// The bank provider answered with an error. Whether the consent is still valid is checked separately with
/// <see cref="IBankingProvider.IsSessionAuthorizedAsync"/>, not guessed from the error.
/// </summary>
public sealed class BankingProviderException(string message, int? statusCode = null, Exception? inner = null)
    : Exception(message, inner)
{
    public int? StatusCode { get; } = statusCode;
}
