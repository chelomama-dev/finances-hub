using FinancesHub.Application.Queries;

namespace FinancesHub.Application.Tests.Queries;

public sealed class TransactionCursorTests
{
    [Fact]
    public void Round_trips()
    {
        var cursor = new TransactionCursor(new DateOnly(2026, 11, 1), Guid.NewGuid());

        Assert.True(TransactionCursor.TryParse(cursor.Encode(), out var parsed));
        Assert.Equal(cursor, parsed);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("not-a-cursor")]
    [InlineData("MjAyNi0xMS0wMQ")]
    public void Rejects_anything_it_did_not_make(string? value)
    {
        Assert.False(TransactionCursor.TryParse(value, out _));
    }
}
