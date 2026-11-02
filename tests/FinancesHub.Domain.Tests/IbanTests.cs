using FinancesHub.Domain.Accounts;
using FinancesHub.Domain.Common;

namespace FinancesHub.Domain.Tests;

public sealed class IbanTests
{
    [Fact]
    public void Is_stored_without_spaces_and_in_uppercase()
    {
        Assert.Equal("ES9121000418450200051332", new Iban("es91 2100 0418 4502 0005 1332").Value);
    }

    [Fact]
    public void Masks_all_but_the_country_check_digits_and_last_four()
    {
        Assert.Equal("ES91 **** 1332", new Iban("ES9121000418450200051332").Masked);
    }

    [Theory]
    [InlineData("")]
    [InlineData("ES91")]
    [InlineData("9121000418450200051332ES")]
    [InlineData("ES91-2100-0418-4502-0005-1332")]
    public void Rejects_what_is_not_an_IBAN(string value)
    {
        Assert.Throws<DomainException>(() => new Iban(value));
    }
}
