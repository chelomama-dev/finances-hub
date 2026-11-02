namespace FinancesHub.Infrastructure.EnableBanking.Api;

// Only the fields we use, as Enable Banking names them (snake_case, mapped by the serializer options).
// Every field is nullable: what is filled depends on the bank, as the spike showed

internal sealed record AspspsResponse(List<AspspDto>? Aspsps);

internal sealed record AspspDto(string? Name, string? Country, long? MaximumConsentValidity);

internal sealed record AuthRequest(AuthAccess Access, AuthAspsp Aspsp, string State, Uri RedirectUrl, string PsuType);

internal sealed record AuthAccess(DateTimeOffset ValidUntil);

internal sealed record AuthAspsp(string Name, string Country);

internal sealed record AuthResponse(Uri? Url);

internal sealed record SessionRequest(string Code);

internal sealed record SessionResponse(string? SessionId, SessionAccess? Access, List<AccountDto>? Accounts);

internal sealed record SessionAccess(DateTimeOffset? ValidUntil);

internal sealed record SessionStatusResponse(string? Status);

internal sealed record AccountDto(string? Uid, AccountIdDto? AccountId, string? Name, string? Currency);

internal sealed record AccountIdDto(string? Iban);

internal sealed record BalancesResponse(List<BalanceDto>? Balances);

internal sealed record BalanceDto(AmountDto? BalanceAmount, string? BalanceType);

internal sealed record AmountDto(string? Amount, string? Currency);

internal sealed record TransactionsResponse(List<TransactionDto>? Transactions, string? ContinuationKey);

internal sealed record TransactionDto(
    AmountDto? TransactionAmount,
    string? CreditDebitIndicator,
    string? Status,
    DateOnly? BookingDate,
    DateOnly? ValueDate,
    DateOnly? TransactionDate,
    List<string>? RemittanceInformation,
    PartyDto? Creditor,
    PartyDto? Debtor);

internal sealed record PartyDto(string? Name);

internal sealed record ErrorResponse(int? Code, string? Message, string? Error);
