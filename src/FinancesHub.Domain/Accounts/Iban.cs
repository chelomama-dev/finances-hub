using FinancesHub.Domain.Common;

namespace FinancesHub.Domain.Accounts;

/// <summary>
/// An IBAN, stored without spaces and in uppercase. Only its masked form leaves the backend.
/// </summary>
public readonly record struct Iban
{
    public string Value { get; }

    public Iban(string? value)
    {
        var normalized = string.Concat((value ?? "").Where(c => !char.IsWhiteSpace(c))).ToUpperInvariant();

        // Format only (country, check digits, alphanumeric BBAN): the bank is the source, not user input
        if (normalized.Length is < 15 or > 34
            || !normalized[..2].All(char.IsAsciiLetterUpper)
            || !normalized[2..4].All(char.IsAsciiDigit)
            || !normalized.All(char.IsAsciiLetterOrDigit))
            throw new DomainException("Invalid IBAN.");

        Value = normalized;
    }

    /// <summary>Country and check digits, then only the last four characters: <c>ES62 **** 9421</c>.</summary>
    public string Masked => $"{Value[..4]} **** {Value[^4..]}";

    public override string ToString() => Masked;
}
