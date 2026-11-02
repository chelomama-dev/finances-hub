using FinancesHub.Domain.Common;

namespace FinancesHub.Domain.Tests;

public sealed class MoneyTests
{
    [Theory]
    [InlineData("eur")]
    [InlineData("EURO")]
    [InlineData("")]
    [InlineData(null)]
    public void Currency_must_be_an_uppercase_ISO_code(string? currency)
    {
        Assert.Throws<DomainException>(() => new Money(1m, currency!));
    }

    [Fact]
    public void Adds_amounts_in_the_same_currency()
    {
        Assert.Equal(new Money(964.36m, "EUR"), new Money(987.76m, "EUR").Add(new Money(-23.40m, "EUR")));
    }

    [Fact]
    public void Does_not_add_different_currencies()
    {
        Assert.Throws<DomainException>(() => new Money(1m, "EUR").Add(new Money(1m, "USD")));
    }
}
