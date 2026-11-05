using FinancesHub.Api.Common;
using FinancesHub.Application.Queries;
using FinancesHub.Domain.Banks;
using FinancesHub.Domain.Common;
using FinancesHub.Domain.Connections;
using FinancesHub.Domain.Transactions;
using Microsoft.AspNetCore.Http.HttpResults;

namespace FinancesHub.Api.Finances;

// See docs/api.md → "Get the summary", "List a bank's accounts", "List transactions" and "Get statistics"
public static class FinanceEndpoints
{
    public const int DefaultLimit = 50;
    public const int MaxLimit = 100;

    public static IEndpointRouteBuilder MapFinances(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api").WithTags("Finances");

        group.MapGet("/summary", GetSummaryAsync);
        group.MapGet("/banks/{bankId}/accounts", ListAccountsAsync);
        group.MapGet("/transactions", ListTransactionsAsync);
        group.MapGet("/statistics", GetStatisticsAsync);

        return app;
    }

    private static async Task<Ok<SummaryResponse>> GetSummaryAsync(GetSummary getSummary, CancellationToken cancellationToken)
    {
        var summary = await getSummary.RunAsync(cancellationToken);

        return TypedResults.Ok(new SummaryResponse(
            MoneyResponse.From(summary.TotalBalance),
            summary.LastSyncedAt,
            summary.Banks.Select(b => new BankSummaryResponse(b.Bank.Code, b.Bank.Name, MoneyResponse.From(b.Balance), ToContract(b.ConnectionStatus))).ToList()));
    }

    private static async Task<Results<Ok<BankAccountsResponse>, NotFound>> ListAccountsAsync(
        string bankId, IFinanceQueries queries, CancellationToken cancellationToken)
    {
        if (Bank.FromCode(bankId) is not { } bank)
            return TypedResults.NotFound();

        var accounts = await queries.ListAccountsAsync(bank.Code, cancellationToken);

        return TypedResults.Ok(new BankAccountsResponse(
            new BankResponse(bank.Code, bank.Name),
            accounts.Select(a => new AccountResponse(a.Id, a.Name, a.Iban?.Masked,
                MoneyResponse.From(a.Balance ?? Money.Zero(a.Currency)))).ToList()));
    }

    private static async Task<Results<Ok<TransactionPageResponse>, ValidationProblem>> ListTransactionsAsync(
        DateOnly? from, DateOnly? to, string? direction, int? limit, string? cursor,
        IFinanceQueries queries, TimeProvider timeProvider, CancellationToken cancellationToken)
    {
        var errors = new Dictionary<string, string[]>();

        to ??= DateOnly.FromDateTime(timeProvider.GetUtcNow().UtcDateTime);
        if (from > to)
            errors["from"] = ["Must not be after 'to'."];

        TransactionDirection? parsedDirection = direction switch
        {
            null => null,
            "income" => TransactionDirection.Income,
            "expense" => TransactionDirection.Expense,
            _ => null
        };
        if (direction is not null && parsedDirection is null)
            errors["direction"] = ["Must be 'income' or 'expense'."];

        var pageSize = limit ?? DefaultLimit;
        if (pageSize is < 1 or > MaxLimit)
            errors["limit"] = [$"Must be between 1 and {MaxLimit}."];

        TransactionCursor? after = null;
        if (cursor is not null && !TransactionCursor.TryParse(cursor, out after))
            errors["cursor"] = ["Not a cursor from this API."];

        if (errors.Count > 0)
            return TypedResults.ValidationProblem(errors);

        var rows = await queries.ListTransactionsAsync(new TransactionFilter(from, to, parsedDirection), after, pageSize, cancellationToken);

        // One row more than asked tells there is a next page; it is not returned
        var page = rows.Take(pageSize).ToList();
        var nextCursor = rows.Count > pageSize ? new TransactionCursor(page[^1].BookingDate, page[^1].Id).Encode() : null;

        return TypedResults.Ok(new TransactionPageResponse(
            page.Select(t => new TransactionResponse(t.Id, t.BookingDate, MoneyResponse.From(t.Amount), t.Description, t.Counterparty,
                t.Status == TransactionStatus.Pending ? "pending" : "booked", ToBank(t.BankCode))).ToList(),
            nextCursor));
    }

    private static async Task<Results<Ok<StatisticsResponse>, ValidationProblem>> GetStatisticsAsync(
        DateOnly? from, DateOnly? to, GetStatistics getStatistics, TimeProvider timeProvider, CancellationToken cancellationToken)
    {
        to ??= DateOnly.FromDateTime(timeProvider.GetUtcNow().UtcDateTime);
        var error = from switch
        {
            null => "Required.",
            _ when from > to => "Must not be after 'to'.",
            _ when to.Value.DayNumber - from.Value.DayNumber >= GetStatistics.MaxDays => $"Must be at most {GetStatistics.MaxDays} days before 'to'.",
            _ => null
        };
        if (error is not null)
            return TypedResults.ValidationProblem(new Dictionary<string, string[]> { ["from"] = [error] });

        var statistics = await getStatistics.RunAsync(from!.Value, to.Value, cancellationToken);

        return TypedResults.Ok(new StatisticsResponse(
            statistics.From,
            statistics.To,
            MoneyResponse.From(statistics.Income),
            MoneyResponse.From(statistics.Expenses),
            statistics.TopExpenses.Select(g => new ExpenseGroupResponse(g.Description, MoneyResponse.From(g.Total), g.Count)).ToList(),
            MoneyResponse.From(statistics.OtherExpenses),
            statistics.Days.Select(d => new DayTotalsResponse(d.Date, MoneyResponse.From(d.Income), MoneyResponse.From(d.Expenses))).ToList()));
    }

    // Every stored account belongs to a known bank; the code alone is the fallback name if one is ever dropped
    private static BankResponse ToBank(string code) =>
        Bank.FromCode(code) is { } bank ? new BankResponse(bank.Code, bank.Name) : new BankResponse(code, code);

    private static string ToContract(ConnectionStatus status) => status switch
    {
        ConnectionStatus.Active => "active",
        ConnectionStatus.Expiring => "expiring",
        _ => "expired"
    };
}

public sealed record SummaryResponse(MoneyResponse TotalBalance, DateTimeOffset? LastSyncedAt, IReadOnlyList<BankSummaryResponse> Banks);

public sealed record BankSummaryResponse(string Id, string Name, MoneyResponse Balance, string ConnectionStatus);

public sealed record BankAccountsResponse(BankResponse Bank, IReadOnlyList<AccountResponse> Accounts);

public sealed record BankResponse(string Id, string Name);

public sealed record AccountResponse(Guid Id, string? Name, string? MaskedIban, MoneyResponse Balance);

public sealed record TransactionPageResponse(IReadOnlyList<TransactionResponse> Items, string? NextCursor);

public sealed record TransactionResponse(
    Guid Id, DateOnly BookingDate, MoneyResponse Amount, string? Description, string? Counterparty, string Status, BankResponse Bank);

public sealed record StatisticsResponse(
    DateOnly From, DateOnly To, MoneyResponse Income, MoneyResponse Expenses, IReadOnlyList<ExpenseGroupResponse> TopExpenses,
    MoneyResponse OtherExpenses, IReadOnlyList<DayTotalsResponse> Days);

public sealed record ExpenseGroupResponse(string? Description, MoneyResponse Amount, int Count);

public sealed record DayTotalsResponse(DateOnly Date, MoneyResponse Income, MoneyResponse Expenses);
