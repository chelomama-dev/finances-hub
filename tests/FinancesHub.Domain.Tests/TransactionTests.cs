using FinancesHub.Domain.Common;
using FinancesHub.Domain.Transactions;

namespace FinancesHub.Domain.Tests;

public sealed class TransactionTests
{
    [Theory]
    [InlineData("-23.40", TransactionDirection.Expense)]
    [InlineData("1650.00", TransactionDirection.Income)]
    public void Direction_comes_from_the_sign(string amount, TransactionDirection expected)
    {
        Assert.Equal(expected, Create(new Money(decimal.Parse(amount, System.Globalization.CultureInfo.InvariantCulture), "EUR")).Direction);
    }

    [Fact]
    public void Collapses_the_spacing_banks_pad_texts_with()
    {
        var transaction = Transaction.Create(Guid.NewGuid(), new DateOnly(2026, 11, 1), null, new Money(-1m, "EUR"),
            "  COMPRA   TARJ.  \n MERCADONA ", "   ", TransactionStatus.Booked);

        Assert.Equal("COMPRA TARJ. MERCADONA", transaction.Description);
        Assert.Null(transaction.Counterparty);
    }

    [Fact]
    public void Cuts_a_description_that_is_too_long_instead_of_losing_the_transaction()
    {
        var transaction = Transaction.Create(Guid.NewGuid(), new DateOnly(2026, 11, 1), null, new Money(-1m, "EUR"),
            new string('x', Transaction.MaxDescriptionLength + 50), null, TransactionStatus.Booked);

        Assert.Equal(Transaction.MaxDescriptionLength, transaction.Description!.Length);
    }

    private static Transaction Create(Money amount) =>
        Transaction.Create(Guid.NewGuid(), new DateOnly(2026, 11, 1), null, amount, null, null, TransactionStatus.Booked);
}
