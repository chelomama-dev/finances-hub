using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using FinancesHub.Api.Common;
using FinancesHub.Domain.Accounts;
using FinancesHub.Domain.Banks;
using FinancesHub.Domain.Common;
using FinancesHub.Domain.Connections;
using FinancesHub.Domain.Transactions;
using FinancesHub.Infrastructure.Persistence;
using Microsoft.Extensions.DependencyInjection;

namespace FinancesHub.Api.Tests;

// Its own API and database: the summary adds up everything stored, so other tests' data would change the totals
public sealed class FinanceEndpointsTests(ApiFactory factory) : IClassFixture<ApiFactory>, IAsyncLifetime
{
    private static readonly DateTimeOffset Now = DateTimeOffset.UtcNow;
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    private readonly HttpClient _client = factory.CreateClient();
    private Account _cajaRural = null!;

    public async ValueTask InitializeAsync()
    {
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<FinancesDbContext>();
        if (db.Accounts.Any())
        {
            _cajaRural = db.Accounts.Single(a => a.ProviderAccountId == "uid-cr");
            return;
        }

        var cr = Connection.Create(Bank.CajaRuralDeNavarra, "s-cr", Now.AddDays(180), Now.AddDays(-1));
        var tr = Connection.Create(Bank.TradeRepublic, "s-tr", Now.AddDays(10), Now.AddDays(-80));
        _cajaRural = Account.Create(cr.Id, "uid-cr", new Iban("ES9121000418450200051332"), "MI CUENTA", "EUR");
        var tradeRepublic = Account.Create(tr.Id, "uid-tr", null, null, "EUR");
        _cajaRural.RecordSync(new Money(987.76m, "EUR"), Now.AddHours(-2));
        tradeRepublic.RecordSync(new Money(9366.87m, "EUR"), Now.AddHours(-1));

        db.AddRange(cr, tr, _cajaRural, tradeRepublic);
        db.Transactions.AddRange(
            Tx(2026, 11, 1, -23.40m, "SUPERMERCADO"), Tx(2026, 11, 1, -5.00m, "CAFE"), Tx(2026, 11, 1, -5.00m, "CAFE"),
            Tx(2026, 10, 31, 1650.00m, "NOMINA"), Tx(2026, 10, 15, -60.00m, null, TransactionStatus.Pending),
            Transaction.Create(tradeRepublic.Id, new DateOnly(2026, 10, 20), null, new Money(250.00m, "EUR"), null, null, TransactionStatus.Booked));
        await db.SaveChangesAsync(Ct);
    }

    public ValueTask DisposeAsync() => ValueTask.CompletedTask;

    [Fact]
    public async Task Summary_adds_up_every_bank()
    {
        var summary = await _client.GetFromJsonAsync<JsonElement>("/api/summary", Ct);

        Assert.Equal("10354.63", summary.GetProperty("totalBalance").GetProperty("amount").GetString());
        Assert.Equal("EUR", summary.GetProperty("totalBalance").GetProperty("currency").GetString());
        var banks = summary.GetProperty("banks").EnumerateArray().ToList();
        Assert.Equal(["caja-rural-navarra", "trade-republic"], banks.Select(b => b.GetProperty("id").GetString()));
        Assert.Equal("987.76", banks[0].GetProperty("balance").GetProperty("amount").GetString());
        Assert.Equal("active", banks[0].GetProperty("connectionStatus").GetString());
        Assert.Equal("expiring", banks[1].GetProperty("connectionStatus").GetString());
        Assert.True(summary.GetProperty("lastSyncedAt").GetDateTimeOffset() > Now.AddHours(-1.5));
    }

    [Fact]
    public async Task A_banks_accounts_show_a_masked_iban()
    {
        var response = await _client.GetFromJsonAsync<JsonElement>("/api/banks/caja-rural-navarra/accounts", Ct);

        var account = Assert.Single(response.GetProperty("accounts").EnumerateArray());
        Assert.Equal("ES91 **** 1332", account.GetProperty("maskedIban").GetString());
        Assert.Equal("MI CUENTA", account.GetProperty("name").GetString());
        Assert.DoesNotContain("21000418450200051332", response.GetRawText());
    }

    [Fact]
    public async Task An_unknown_bank_is_not_found()
    {
        Assert.Equal(HttpStatusCode.NotFound, (await _client.GetAsync("/api/banks/unknown/accounts", Ct)).StatusCode);
    }

    [Fact]
    public async Task Pages_cover_every_banks_transactions_once_newest_first()
    {
        var seen = new List<JsonElement>();
        string? cursor = null;
        do
        {
            var url = "/api/transactions?limit=2&to=2026-11-02" + (cursor is null ? "" : $"&cursor={cursor}");
            var page = await _client.GetFromJsonAsync<JsonElement>(url, Ct);
            seen.AddRange(page.GetProperty("items").EnumerateArray());
            cursor = page.GetProperty("nextCursor").GetString();
        } while (cursor is not null);

        Assert.Equal(6, seen.Count);
        Assert.Equal(6, seen.Select(t => t.GetProperty("id").GetString()).Distinct().Count());
        var dates = seen.Select(t => t.GetProperty("bookingDate").GetString()).ToList();
        Assert.Equal(dates.OrderDescending(), dates);
        Assert.Equal("-23.40", seen.First(t => t.GetProperty("description").GetString() == "SUPERMERCADO").GetProperty("amount").GetProperty("amount").GetString());
        Assert.Contains(seen, t => t.GetProperty("status").GetString() == "pending" && t.GetProperty("description").ValueKind == JsonValueKind.Null);
        var banks = seen.Select(t => t.GetProperty("bank")).ToList();
        Assert.Equal(5, banks.Count(b => b.GetProperty("id").GetString() == "caja-rural-navarra"));
        Assert.Equal("Trade Republic", Assert.Single(banks, b => b.GetProperty("id").GetString() == "trade-republic").GetProperty("name").GetString());
    }

    [Theory]
    [InlineData("income", 2)]
    [InlineData("expense", 4)]
    public async Task Filters_by_direction(string direction, int expected)
    {
        var page = await _client.GetFromJsonAsync<JsonElement>($"/api/transactions?direction={direction}&to=2026-11-02", Ct);

        Assert.Equal(expected, page.GetProperty("items").GetArrayLength());
    }

    [Fact]
    public async Task Filters_by_date_range()
    {
        var page = await _client.GetFromJsonAsync<JsonElement>("/api/transactions?from=2026-10-31&to=2026-10-31", Ct);

        Assert.Equal("NOMINA", Assert.Single(page.GetProperty("items").EnumerateArray()).GetProperty("description").GetString());
    }

    [Theory]
    [InlineData("from=2026-11-02&to=2026-11-01", "from")]
    [InlineData("direction=both", "direction")]
    [InlineData("limit=0", "limit")]
    [InlineData("limit=101", "limit")]
    [InlineData("cursor=not-a-cursor", "cursor")]
    public async Task Invalid_queries_are_validation_errors(string query, string field)
    {
        var response = await _client.GetAsync($"/api/transactions?{query}", Ct);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.True((await response.Content.ReadFromJsonAsync<JsonElement>(Ct)).GetProperty("errors").TryGetProperty(field, out _));
    }

    [Fact]
    public async Task Statistics_add_up_every_banks_transactions_in_the_range()
    {
        var statistics = await _client.GetFromJsonAsync<JsonElement>("/api/statistics?from=2026-10-01&to=2026-11-02", Ct);

        Assert.Equal("2026-10-01", statistics.GetProperty("from").GetString());
        Assert.Equal("1900.00", Amount(statistics.GetProperty("income")));
        Assert.Equal("-93.40", Amount(statistics.GetProperty("expenses")));
        var top = statistics.GetProperty("topExpenses").EnumerateArray().ToList();
        Assert.Equal([null, "SUPERMERCADO", "CAFE"], top.Select(g => g.GetProperty("description").GetString()));
        Assert.Equal("-10.00", Amount(top[2].GetProperty("amount")));
        Assert.Equal(2, top[2].GetProperty("count").GetInt32());
        Assert.Equal("0.00", Amount(statistics.GetProperty("otherExpenses")));
        Assert.Equal(["2026-10-15", "2026-10-20", "2026-10-31", "2026-11-01"],
            statistics.GetProperty("days").EnumerateArray().Select(d => d.GetProperty("date").GetString()));
    }

    [Theory]
    [InlineData("to=2026-11-02")]
    [InlineData("from=2026-11-03&to=2026-11-02")]
    [InlineData("from=2025-11-01&to=2026-11-02")]
    public async Task Invalid_statistics_ranges_are_validation_errors(string query)
    {
        var response = await _client.GetAsync($"/api/statistics?{query}", Ct);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.True((await response.Content.ReadFromJsonAsync<JsonElement>(Ct)).GetProperty("errors").TryGetProperty("from", out _));
    }

    private static string? Amount(JsonElement money) => money.GetProperty("amount").GetString();

    [Theory]
    [InlineData("987.76", "987.76")]
    [InlineData("1650", "1650.00")]
    [InlineData("-0.005", "-0.005")]
    public void Amounts_are_decimal_strings_with_at_least_two_decimals(string amount, string expected)
    {
        Assert.Equal(expected, MoneyResponse.From(new Money(decimal.Parse(amount, System.Globalization.CultureInfo.InvariantCulture), "EUR")).Amount);
    }

    private Transaction Tx(int year, int month, int day, decimal amount, string? description, TransactionStatus status = TransactionStatus.Booked) =>
        Transaction.Create(_cajaRural.Id, new DateOnly(year, month, day), null, new Money(amount, "EUR"), description, null, status);
}
