namespace FinancesHub.Domain.Banks;

/// <summary>
/// A bank the app can read. The list is fixed: adding a bank means checking first what it sends through
/// Enable Banking, as the spike did for these two.
/// </summary>
public sealed record Bank
{
    public static readonly Bank CajaRuralDeNavarra = new("caja-rural-navarra", "Caja Rural de Navarra", "ES");

    // Listed in Germany, the country of its banking licence, even though Spanish accounts have a Spanish IBAN
    public static readonly Bank TradeRepublic = new("trade-republic", "Trade Republic", "DE");

    public static IReadOnlyList<Bank> All { get; } = [CajaRuralDeNavarra, TradeRepublic];

    /// <summary>Stable identifier used in the database and in the API (<c>caja-rural-navarra</c>).</summary>
    public string Code { get; }

    /// <summary>Display name, which is also the bank's exact name in Enable Banking.</summary>
    public string Name { get; }

    /// <summary>Country where Enable Banking lists the bank (ISO 3166 alpha-2).</summary>
    public string Country { get; }

    private Bank(string code, string name, string country)
    {
        Code = code;
        Name = name;
        Country = country;
    }

    public static Bank? FromCode(string? code) => All.FirstOrDefault(b => b.Code == code);
}
