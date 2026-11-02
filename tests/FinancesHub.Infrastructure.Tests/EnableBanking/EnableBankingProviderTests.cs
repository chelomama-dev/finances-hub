using System.Net;
using System.Text.Json;
using FinancesHub.Application.Banking;
using FinancesHub.Domain.Banks;
using FinancesHub.Domain.Common;
using FinancesHub.Domain.Transactions;
using FinancesHub.Infrastructure.EnableBanking;

namespace FinancesHub.Infrastructure.Tests.EnableBanking;

// Made-up data shaped like what each bank sent in the spike (2 November 2026)
public sealed class EnableBankingProviderTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 2, 12, 0, 0, TimeSpan.Zero);

    private readonly FakeHttpHandler _handler = new();

    [Fact]
    public async Task Caja_Rural_debits_come_positive_and_become_expenses()
    {
        _handler.Respond("""
            {
              "transactions": [
                {
                  "transaction_amount": { "amount": "23.40", "currency": "EUR" },
                  "credit_debit_indicator": "DBIT",
                  "status": "BOOK",
                  "booking_date": "2026-11-01",
                  "value_date": "2026-10-31",
                  "remittance_information": ["COMPRA TARJ. 1234", "SUPERMERCADO EJEMPLO"],
                  "creditor": { "name": "Supermercado Ejemplo S.L." },
                  "debtor": { "name": "Titular Inventado" },
                  "entry_reference": ""
                },
                {
                  "transaction_amount": { "amount": "1650.00", "currency": "EUR" },
                  "credit_debit_indicator": "CRDT",
                  "status": "BOOK",
                  "booking_date": "2026-10-31",
                  "remittance_information": ["NOMINA OCTUBRE"],
                  "creditor": { "name": "Titular Inventado" },
                  "debtor": { "name": "Empresa Ejemplo S.A." }
                }
              ],
              "continuation_key": null
            }
            """);

        var transactions = await CreateProvider().GetTransactionsAsync("uid", null, CancellationToken.None);

        Assert.Equal(2, transactions.Count);
        var expense = transactions[0];
        Assert.Equal(new Money(-23.40m, "EUR"), expense.Amount);
        Assert.Equal(new DateOnly(2026, 11, 1), expense.BookingDate);
        Assert.Equal(new DateOnly(2026, 10, 31), expense.ValueDate);
        Assert.Equal("COMPRA TARJ. 1234 SUPERMERCADO EJEMPLO", expense.Description);
        Assert.Equal("Supermercado Ejemplo S.L.", expense.Counterparty);
        Assert.Equal(TransactionStatus.Booked, expense.Status);

        var income = transactions[1];
        Assert.Equal(new Money(1650.00m, "EUR"), income.Amount);
        Assert.Equal("Empresa Ejemplo S.A.", income.Counterparty);
    }

    [Fact]
    public async Task Trade_Republic_debits_come_negative_and_stay_expenses()
    {
        _handler.Respond("""
            {
              "transactions": [
                { "transaction_amount": { "amount": "-50.00", "currency": "EUR" }, "credit_debit_indicator": "DBIT", "status": "BOOK", "booking_date": "2026-11-02" },
                { "transaction_amount": { "amount": "200.00", "currency": "EUR" }, "credit_debit_indicator": "CRDT", "status": "BOOK", "booking_date": "2026-11-01" }
              ],
              "continuation_key": null
            }
            """);

        var transactions = await CreateProvider().GetTransactionsAsync("uid", null, CancellationToken.None);

        Assert.Equal([new Money(-50.00m, "EUR"), new Money(200.00m, "EUR")], transactions.Select(t => t.Amount));
        Assert.All(transactions, t =>
        {
            Assert.Null(t.Description);
            Assert.Null(t.Counterparty);
            Assert.Null(t.ValueDate);
        });
    }

    [Fact]
    public async Task Follows_continuation_keys_with_the_same_filters_until_there_are_none()
    {
        _handler
            .Respond("""{ "transactions": [ { "transaction_amount": { "amount": "1.00", "currency": "EUR" }, "credit_debit_indicator": "DBIT", "booking_date": "2026-11-02" } ], "continuation_key": "page/2" }""")
            .Respond("""{ "transactions": [], "continuation_key": "page3" }""")
            .Respond("""{ "transactions": [ { "transaction_amount": { "amount": "2.00", "currency": "EUR" }, "credit_debit_indicator": "DBIT", "booking_date": "2026-10-25" } ], "continuation_key": null }""");

        var transactions = await CreateProvider().GetTransactionsAsync("uid", new DateOnly(2026, 10, 23), CancellationToken.None);

        Assert.Equal(2, transactions.Count);
        Assert.Equal(
            [
                "/accounts/uid/transactions?date_from=2026-10-23",
                "/accounts/uid/transactions?date_from=2026-10-23&continuation_key=page%2F2",
                "/accounts/uid/transactions?date_from=2026-10-23&continuation_key=page3"
            ],
            _handler.Requests.Select(r => r.PathAndQuery));
    }

    [Fact]
    public async Task Without_a_start_date_asks_for_the_longest_history()
    {
        _handler.Respond("""{ "transactions": [], "continuation_key": null }""");

        await CreateProvider().GetTransactionsAsync("uid", null, CancellationToken.None);

        Assert.Equal("/accounts/uid/transactions?strategy=longest", _handler.Requests.Single().PathAndQuery);
    }

    [Fact]
    public async Task Throws_instead_of_returning_a_partial_list_when_pages_never_end()
    {
        for (var i = 0; i < EnableBankingProvider.MaxPages; i++)
            _handler.Respond("""{ "transactions": [], "continuation_key": "more" }""");

        await Assert.ThrowsAsync<BankingProviderException>(() =>
            CreateProvider().GetTransactionsAsync("uid", null, CancellationToken.None));
    }

    [Theory]
    [InlineData("CNCL")]
    [InlineData("RJCT")]
    [InlineData("SCHD")]
    public async Task Skips_transactions_that_did_not_move_money(string status)
    {
        _handler.Respond($$"""{ "transactions": [ { "transaction_amount": { "amount": "1.00", "currency": "EUR" }, "credit_debit_indicator": "DBIT", "status": "{{status}}", "booking_date": "2026-11-02" } ], "continuation_key": null }""");

        Assert.Empty(await CreateProvider().GetTransactionsAsync("uid", null, CancellationToken.None));
    }

    [Fact]
    public async Task Pending_transactions_are_kept_as_pending()
    {
        _handler.Respond("""{ "transactions": [ { "transaction_amount": { "amount": "1.00", "currency": "EUR" }, "credit_debit_indicator": "DBIT", "status": "PDNG", "booking_date": "2026-11-02" } ], "continuation_key": null }""");

        var transaction = Assert.Single(await CreateProvider().GetTransactionsAsync("uid", null, CancellationToken.None));
        Assert.Equal(TransactionStatus.Pending, transaction.Status);
    }

    [Theory]
    [InlineData("""[ { "balance_amount": { "amount": "900.00", "currency": "EUR" }, "balance_type": "CLBD" }, { "balance_amount": { "amount": "950.00", "currency": "EUR" }, "balance_type": "CLAV" } ]""", "950.00")]
    [InlineData("""[ { "balance_amount": { "amount": "987.76", "currency": "EUR" }, "balance_type": "CLBD" } ]""", "987.76")]
    [InlineData("""[ { "balance_amount": { "amount": "9407.15", "currency": "EUR" }, "balance_type": "OTHR" } ]""", "9407.15")]
    public async Task Prefers_the_available_balance_over_the_booked_one(string balances, string expected)
    {
        _handler.Respond($$"""{ "balances": {{balances}} }""");

        var balance = await CreateProvider().GetBalanceAsync("uid", CancellationToken.None);

        Assert.Equal(new Money(decimal.Parse(expected, System.Globalization.CultureInfo.InvariantCulture), "EUR"), balance);
    }

    [Fact]
    public async Task Starts_an_authorization_with_the_longest_consent_the_bank_allows()
    {
        _handler
            .Respond("""{ "aspsps": [ { "name": "Trade Republic", "country": "DE", "maximum_consent_validity": 7776000 } ] }""")
            .Respond("""{ "url": "https://tilisy.enablebanking.com/ais/start?sessionid=abc" }""");

        var authorization = await CreateProvider().StartAuthorizationAsync(
            Bank.TradeRepublic, new Uri("https://localhost:7017/callback"), "state-1", CancellationToken.None);

        Assert.Equal(new Uri("https://tilisy.enablebanking.com/ais/start?sessionid=abc"), authorization.Url);
        Assert.Equal(Now.AddDays(90).AddMinutes(-10), authorization.ConsentValidUntil);

        var (method, path, body) = _handler.Requests[1];
        Assert.Equal(HttpMethod.Post, method);
        Assert.Equal("/auth", path);
        var json = JsonDocument.Parse(body!).RootElement;
        Assert.Equal("Trade Republic", json.GetProperty("aspsp").GetProperty("name").GetString());
        Assert.Equal("DE", json.GetProperty("aspsp").GetProperty("country").GetString());
        Assert.Equal("state-1", json.GetProperty("state").GetString());
        Assert.Equal("https://localhost:7017/callback", json.GetProperty("redirect_url").GetString());
        Assert.Equal("personal", json.GetProperty("psu_type").GetString());
        Assert.Equal(Now.AddDays(90).AddMinutes(-10), json.GetProperty("access").GetProperty("valid_until").GetDateTimeOffset());
    }

    [Fact]
    public async Task Creates_a_session_with_the_shared_accounts()
    {
        _handler.Respond("""
            {
              "session_id": "session-1",
              "access": { "valid_until": "2027-05-01T11:09:03.153000Z" },
              "accounts": [
                { "uid": "uid-1", "account_id": { "iban": "ES9121000418450200051332" }, "name": "TITULAR INVENTADO", "currency": "EUR" },
                { "uid": "uid-2", "account_id": { "iban": null }, "name": null, "currency": "EUR" }
              ]
            }
            """);

        var session = await CreateProvider().CreateSessionAsync("code-1", CancellationToken.None);

        Assert.Equal("session-1", session.SessionId);
        Assert.Equal(new DateTimeOffset(2027, 5, 1, 11, 9, 3, 153, TimeSpan.Zero), session.ValidUntil);
        Assert.Equal("ES91 **** 1332", session.Accounts[0].Iban?.Masked);
        Assert.Null(session.Accounts[1].Iban);
        Assert.Equal("""{"code":"code-1"}""", _handler.Requests.Single().Body);
    }

    [Theory]
    [InlineData("AUTHORIZED", true)]
    [InlineData("EXPIRED", false)]
    [InlineData("REVOKED", false)]
    public async Task A_session_can_read_only_while_authorized(string status, bool expected)
    {
        _handler.Respond($$"""{ "status": "{{status}}" }""");

        Assert.Equal(expected, await CreateProvider().IsSessionAuthorizedAsync("session-1", CancellationToken.None));
    }

    [Fact]
    public async Task Errors_carry_the_status_and_Enable_Bankings_message()
    {
        _handler.Respond("""{ "code": 403, "message": "Application is not active" }""", HttpStatusCode.Forbidden);

        var error = await Assert.ThrowsAsync<BankingProviderException>(() =>
            CreateProvider().GetBalanceAsync("uid", CancellationToken.None));

        Assert.Equal(403, error.StatusCode);
        Assert.Contains("Application is not active", error.Message);
    }

    private EnableBankingProvider CreateProvider() =>
        new(new HttpClient(_handler) { BaseAddress = new Uri("https://api.enablebanking.com") }, new FixedTimeProvider(Now));

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }
}
