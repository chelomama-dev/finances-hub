using FinancesHub.Domain.Common;

namespace FinancesHub.Application.Queries;

/// <summary>
/// The statistics screen: income and expenses of a date range, the descriptions with the most expenses, and the
/// totals of each day. A range is at most a year of transactions, so they are added up here rather than in SQL.
/// </summary>
public sealed class GetStatistics(IFinanceQueries queries)
{
    public const int MaxDays = 366;
    public const int TopCount = 5;

    public async Task<Statistics> RunAsync(DateOnly from, DateOnly to, CancellationToken cancellationToken)
    {
        // Every account is in euros for now, as in the summary (docs/api.md)
        const string currency = GetSummary.Currency;
        var movements = await queries.ListMovementsAsync(from, to, currency, cancellationToken);

        var expenses = movements.Where(m => m.Amount < 0).ToList();
        var groups = expenses
            .GroupBy(m => m.Description)
            .Select(g => new ExpenseGroup(g.Key, new Money(g.Sum(m => m.Amount), currency), g.Count()))
            // Ties in a stable order, so the chart doesn't reshuffle between two loads of the same data
            .OrderBy(g => g.Total.Amount)
            .ThenBy(g => g.Description, StringComparer.Ordinal)
            .ToList();
        var top = groups.Take(TopCount).ToList();

        var days = movements
            .GroupBy(m => m.BookingDate)
            .OrderBy(g => g.Key)
            .Select(g => new DayTotals(g.Key, Sum(g.Where(m => m.Amount >= 0), currency), Sum(g.Where(m => m.Amount < 0), currency)))
            .ToList();

        return new Statistics(
            from,
            to,
            Sum(movements.Where(m => m.Amount >= 0), currency),
            Sum(expenses, currency),
            top,
            new Money(groups.Skip(TopCount).Sum(g => g.Total.Amount), currency),
            days);
    }

    private static Money Sum(IEnumerable<MovementView> movements, string currency) => new(movements.Sum(m => m.Amount), currency);
}

public sealed record Statistics(
    DateOnly From, DateOnly To, Money Income, Money Expenses, IReadOnlyList<ExpenseGroup> TopExpenses, Money OtherExpenses,
    IReadOnlyList<DayTotals> Days);

/// <param name="Description"><c>null</c> groups the transactions that have none.</param>
public sealed record ExpenseGroup(string? Description, Money Total, int Count);

public sealed record DayTotals(DateOnly Date, Money Income, Money Expenses);
