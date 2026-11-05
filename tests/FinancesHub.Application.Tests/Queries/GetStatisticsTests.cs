using FinancesHub.Application.Queries;
using FinancesHub.Domain.Common;

namespace FinancesHub.Application.Tests.Queries;

public sealed class GetStatisticsTests
{
    private static readonly DateOnly From = new(2026, 10, 1);
    private static readonly DateOnly To = new(2026, 10, 31);

    [Fact]
    public async Task Adds_up_income_expenses_and_each_day()
    {
        var statistics = await RunAsync(
            new(new DateOnly(2026, 10, 1), 1650m, "NOMINA"),
            new(new DateOnly(2026, 10, 1), -23.40m, "SUPERMERCADO"),
            new(new DateOnly(2026, 10, 3), -5m, "CAFE"),
            new(new DateOnly(2026, 10, 3), 10m, null));

        Assert.Equal(new Money(1660m, "EUR"), statistics.Income);
        Assert.Equal(new Money(-28.40m, "EUR"), statistics.Expenses);
        Assert.Equal(
            [
                new DayTotals(new DateOnly(2026, 10, 1), new Money(1650m, "EUR"), new Money(-23.40m, "EUR")),
                new DayTotals(new DateOnly(2026, 10, 3), new Money(10m, "EUR"), new Money(-5m, "EUR"))
            ],
            statistics.Days);
    }

    [Fact]
    public async Task Groups_expenses_by_description_and_folds_the_rest_into_other()
    {
        var day = new DateOnly(2026, 10, 10);
        var statistics = await RunAsync(
            new(day, -10m, "A"), new(day, -10m, "A"), new(day, -30m, "B"), new(day, -15m, null), new(day, -1m, "C"),
            new(day, -2m, "D"), new(day, -3m, "E"), new(day, -4m, "F"), new(day, 100m, "A"));

        Assert.Equal(["B", "A", null, "F", "E"], statistics.TopExpenses.Select(g => g.Description));
        Assert.Equal(new ExpenseGroup("A", new Money(-20m, "EUR"), 2), statistics.TopExpenses[1]);
        Assert.Equal(new Money(-3m, "EUR"), statistics.OtherExpenses);
        Assert.Equal(statistics.Expenses.Amount, statistics.TopExpenses.Sum(g => g.Total.Amount) + statistics.OtherExpenses.Amount);
    }

    [Fact]
    public async Task Ties_come_in_description_order()
    {
        var day = new DateOnly(2026, 10, 10);
        var statistics = await RunAsync(new(day, -5m, "B"), new(day, -5m, "A"));

        Assert.Equal(["A", "B"], statistics.TopExpenses.Select(g => g.Description));
    }

    [Fact]
    public async Task No_transactions_is_all_zeros()
    {
        var statistics = await RunAsync();

        Assert.Equal(Money.Zero("EUR"), statistics.Income);
        Assert.Equal(Money.Zero("EUR"), statistics.Expenses);
        Assert.Equal(Money.Zero("EUR"), statistics.OtherExpenses);
        Assert.Empty(statistics.TopExpenses);
        Assert.Empty(statistics.Days);
    }

    private static Task<Statistics> RunAsync(params MovementView[] movements) =>
        new GetStatistics(new FakeQueries(movements)).RunAsync(From, To, TestContext.Current.CancellationToken);

    private sealed class FakeQueries(IReadOnlyList<MovementView> movements) : IFinanceQueries
    {
        public Task<IReadOnlyList<MovementView>> ListMovementsAsync(DateOnly from, DateOnly to, string currency, CancellationToken cancellationToken) =>
            Task.FromResult(movements);

        public Task<IReadOnlyList<AccountView>> ListAccountsAsync(string? bankCode, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<IReadOnlyList<TransactionView>> ListTransactionsAsync(
            TransactionFilter filter, TransactionCursor? after, int limit, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }
}
