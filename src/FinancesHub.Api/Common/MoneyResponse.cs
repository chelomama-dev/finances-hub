using System.Globalization;
using FinancesHub.Domain.Common;

namespace FinancesHub.Api.Common;

/// <summary>Money as docs/api.md defines it: the amount as a decimal string, never a JSON number.</summary>
public sealed record MoneyResponse(string Amount, string Currency)
{
    // At least two decimals ("12.50"), more only if the bank sent them, so nothing is rounded away
    public static MoneyResponse From(Money money) =>
        new(money.Amount.ToString("0.00##", CultureInfo.InvariantCulture), money.Currency);
}
