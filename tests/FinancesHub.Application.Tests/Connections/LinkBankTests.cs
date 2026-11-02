using FinancesHub.Application.Banking;
using FinancesHub.Application.Connections;
using FinancesHub.Application.Sync;
using FinancesHub.Application.Tests.Sync;
using FinancesHub.Domain.Accounts;
using FinancesHub.Domain.Banks;
using FinancesHub.Domain.Common;
using FinancesHub.Domain.Connections;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;

namespace FinancesHub.Application.Tests.Connections;

public sealed class LinkBankTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 2, 12, 0, 0, TimeSpan.Zero);
    private static readonly Iban Allowed = new("ES9121000418450200051332");
    private static readonly Iban Other = new("ES7921000813610123456789");

    private readonly FakeStore _store = new();
    private readonly FakeBanking _banking = new();
    private readonly ManualTimeProvider _time = new(Now);

    [Fact]
    public async Task Starting_a_link_remembers_its_state_and_returns_the_banks_login()
    {
        var url = await CreateLinkBank().StartAsync(Bank.TradeRepublic, CancellationToken.None);

        var request = Assert.Single(_store.LinkRequests);
        Assert.Equal((Bank.TradeRepublic, request.Id.ToString()), _banking.Authorizations.Single());
        Assert.Equal($"https://bank.example/login?state={request.Id}", url.ToString());
    }

    [Fact]
    public async Task Completing_a_link_saves_only_the_allowed_accounts_and_syncs_them()
    {
        var state = await StartAsync(Bank.CajaRuralDeNavarra);
        _banking.NextSession = Session(("uid-1", Allowed), ("uid-2", Other));
        _banking.Balances["uid-1"] = new Money(987.76m, "EUR");

        var result = await CreateLinkBank(allowedIbans: Allowed.Value).CompleteAsync(state, "code", CancellationToken.None);

        Assert.Equal(LinkResult.Success, result);
        var connection = Assert.Single(_store.Connections);
        Assert.Equal("session-1", connection.SessionId);
        var account = Assert.Single(_store.Accounts);
        Assert.Equal(Allowed, account.Iban);
        Assert.Equal(Now, account.LastSyncedAt);
        Assert.Equal(("uid-1", (DateOnly?)null), _banking.TransactionRequests.Single());
        Assert.Empty(_store.LinkRequests);
    }

    [Fact]
    public async Task Without_an_allowed_list_every_shared_account_is_saved()
    {
        var state = await StartAsync(Bank.CajaRuralDeNavarra);
        _banking.NextSession = Session(("uid-1", Allowed), ("uid-2", Other));
        _banking.Balances["uid-1"] = _banking.Balances["uid-2"] = new Money(1m, "EUR");

        await CreateLinkBank().CompleteAsync(state, "code", CancellationToken.None);

        Assert.Equal(2, _store.Accounts.Count);
    }

    [Fact]
    public async Task Renewing_keeps_the_connection_and_its_accounts()
    {
        var connection = Connection.Create(Bank.TradeRepublic, "old-session", Now.AddDays(5), Now.AddDays(-85));
        var account = Account.Create(connection.Id, "old-uid", Allowed, "Cuenta", "EUR");
        account.RecordSync(new Money(1m, "EUR"), Now.AddDays(-1));
        _store.Add(connection);
        _store.Add(account);

        await CreateLinkBank().StartRenewalAsync(connection.Id, CancellationToken.None);
        _banking.NextSession = Session(("new-uid", Allowed));
        _banking.Balances["new-uid"] = new Money(2m, "EUR");

        await CreateLinkBank().CompleteAsync(_store.LinkRequests.Single().Id.ToString(), "code", CancellationToken.None);

        Assert.Same(connection, Assert.Single(_store.Connections));
        Assert.Equal("session-1", connection.SessionId);
        Assert.Same(account, Assert.Single(_store.Accounts));
        Assert.Equal("new-uid", account.ProviderAccountId);
    }

    [Fact]
    public async Task Renewing_a_connection_that_does_not_exist_returns_nothing()
    {
        Assert.Null(await CreateLinkBank().StartRenewalAsync(Guid.NewGuid(), CancellationToken.None));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("not-a-guid")]
    [InlineData("6b1f4f0e-8d2c-4e5a-9f7b-3c2d1e0a9b8c")]
    public async Task A_callback_the_app_did_not_start_fails_without_calling_the_bank(string? state)
    {
        Assert.Equal(LinkResult.Failed, await CreateLinkBank().CompleteAsync(state, "code", CancellationToken.None));
        Assert.Empty(_store.Connections);
    }

    [Fact]
    public async Task A_state_is_used_only_once()
    {
        var state = await StartAsync(Bank.TradeRepublic);
        _banking.NextSession = Session();

        await CreateLinkBank().CompleteAsync(state, "code", CancellationToken.None);

        Assert.Equal(LinkResult.Failed, await CreateLinkBank().CompleteAsync(state, "code", CancellationToken.None));
    }

    [Fact]
    public async Task A_callback_after_30_minutes_fails()
    {
        var state = await StartAsync(Bank.TradeRepublic);
        _time.Now = Now.AddMinutes(31);

        Assert.Equal(LinkResult.Failed, await CreateLinkBank().CompleteAsync(state, "code", CancellationToken.None));
        Assert.Empty(_store.LinkRequests);
    }

    [Fact]
    public async Task A_failed_first_sync_keeps_the_link()
    {
        var state = await StartAsync(Bank.TradeRepublic);
        _banking.NextSession = Session(("uid-1", Allowed));
        _banking.FailingAccounts.Add("uid-1");

        Assert.Equal(LinkResult.LinkedButNotSynced, await CreateLinkBank().CompleteAsync(state, "code", CancellationToken.None));
        Assert.Single(_store.Accounts);
    }

    private async Task<string> StartAsync(Bank bank)
    {
        await CreateLinkBank().StartAsync(bank, CancellationToken.None);
        return _store.LinkRequests.Single().Id.ToString();
    }

    private static BankSession Session(params (string Uid, Iban Iban)[] accounts) =>
        new("session-1", Now.AddDays(90), accounts.Select(a => new BankAccount(a.Uid, a.Iban, null, "EUR")).ToList());

    private LinkBank CreateLinkBank(string? allowedIbans = null) =>
        new(_store, _store, _store, _store, _banking,
            new SyncBanks(_store, _store, _store, _store, _banking, _time, NullLogger<SyncBanks>.Instance),
            Options.Create(new BankLinkingOptions { AllowedIbans = allowedIbans }),
            _time, NullLogger<LinkBank>.Instance);
}
