using FinancesHub.Domain.Transactions;

namespace FinancesHub.Domain.Tests;

public sealed class TransactionWindowTests
{
    [Fact]
    public void An_account_never_synced_loads_its_whole_history()
    {
        Assert.Null(TransactionWindow.StartFor(null));
    }

    [Fact]
    public void Starts_ten_days_before_the_last_sync()
    {
        var lastSync = new DateTimeOffset(2026, 11, 2, 7, 0, 0, TimeSpan.Zero);

        Assert.Equal(new DateOnly(2026, 10, 23), TransactionWindow.StartFor(lastSync));
    }

    [Fact]
    public void Uses_the_UTC_date_of_the_last_sync()
    {
        // 00:30 in Spain on 2 November is still 1 November in UTC
        var lastSync = new DateTimeOffset(2026, 11, 2, 0, 30, 0, TimeSpan.FromHours(1));

        Assert.Equal(new DateOnly(2026, 10, 22), TransactionWindow.StartFor(lastSync));
    }
}
