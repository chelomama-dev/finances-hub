namespace FinancesHub.Domain.Common;

/// <summary>
/// An amount in a currency. Negative amounts are money going out of an account.
/// </summary>
public readonly record struct Money
{
    public decimal Amount { get; }

    /// <summary>ISO 4217 code, uppercase (EUR).</summary>
    public string Currency { get; }

    public Money(decimal amount, string currency)
    {
        Amount = amount;
        Currency = ValidateCurrency(currency);
    }

    internal static string ValidateCurrency(string? currency)
    {
        if (currency is not { Length: 3 } || !currency.All(char.IsAsciiLetterUpper))
            throw new DomainException($"\"{currency}\" is not an ISO 4217 currency code.");

        return currency;
    }

    public static Money Zero(string currency) => new(0m, currency);

    public Money Add(Money other)
    {
        if (other.Currency != Currency)
            throw new DomainException($"Can't add {other.Currency} to {Currency}.");

        return new Money(Amount + other.Amount, Currency);
    }

    public override string ToString() => $"{Amount:0.00} {Currency}";
}
