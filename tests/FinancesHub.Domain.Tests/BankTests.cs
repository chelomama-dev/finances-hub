using FinancesHub.Domain.Banks;

namespace FinancesHub.Domain.Tests;

public sealed class BankTests
{
    [Fact]
    public void Finds_a_bank_by_its_code()
    {
        Assert.Same(Bank.TradeRepublic, Bank.FromCode("trade-republic"));
        Assert.Null(Bank.FromCode("unknown"));
    }

    [Fact]
    public void Codes_are_unique()
    {
        Assert.Equal(Bank.All.Count, Bank.All.Select(b => b.Code).Distinct().Count());
    }
}
