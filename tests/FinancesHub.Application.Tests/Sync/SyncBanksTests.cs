using FinancesHub.Application.Banking;
using FinancesHub.Application.Sync;
using FinancesHub.Domain.Accounts;
using FinancesHub.Domain.Banks;
using FinancesHub.Domain.Common;
using FinancesHub.Domain.Connections;
using FinancesHub.Domain.Transactions;
using Microsoft.Extensions.Logging.Abstractions;

namespace FinancesHub.Application.Tests.Sync;

public sealed class SyncBanksTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 2, 7, 0, 0, TimeSpan.Zero);

    private readonly FakeStore _store = new();
    private readonly FakeBanking _banking = new();
    private readonly ManualTimeProvider _time = new(Now);

    [Fact]
    public async Task First_sync_loads_the_whole_history_and_the_balance()
    {
        var account = AddAccount(Bank.CajaRuralDeNavarra, "uid-cr");
        _banking.Balances["uid-cr"] = Eur(987.76m);
        _banking.TransactionsByAccount["uid-cr"] = [Tx(2026, 11, 1, -23.40m), Tx(2025, 10, 9, 1000m)];

        var result = await CreateSync().RunAsync(CancellationToken.None);

        Assert.Equal(1, result.SyncedAccounts);
        Assert.Equal(("uid-cr", (DateOnly?)null), _banking.TransactionRequests.Single());
        Assert.Equal(2, _store.Transactions.Count);
        Assert.Equal(Eur(987.76m), account.Balance);
        Assert.Equal(Now, account.LastSyncedAt);
    }

    [Fact]
    public async Task Later_syncs_replace_only_the_window()
    {
        var account = AddAccount(Bank.TradeRepublic, "uid-tr");
        _banking.Balances["uid-tr"] = Eur(100m);
        _banking.TransactionsByAccount["uid-tr"] = [Tx(2026, 10, 30, -5m), Tx(2026, 10, 1, -7m)];
        await CreateSync().RunAsync(CancellationToken.None);
        var old = _store.Transactions.Single(t => t.BookingDate == new DateOnly(2026, 10, 1));

        // A day later the bank returns the window again, with one more transaction and one from before the
        // window that it shouldn't have sent
        _time.Now = Now.AddDays(1);
        _banking.TransactionsByAccount["uid-tr"] = [Tx(2026, 11, 2, -1m), Tx(2026, 10, 30, -5m), Tx(2026, 10, 1, -7m)];
        await CreateSync().RunAsync(CancellationToken.None);

        Assert.Equal(new DateOnly(2026, 10, 23), _banking.TransactionRequests[^1].From);
        Assert.Equal(3, _store.Transactions.Count);
        Assert.Contains(old, _store.Transactions);
        Assert.Equal(Now.AddDays(1), account.LastSyncedAt);
    }

    [Fact]
    public async Task An_expired_consent_is_skipped_without_calling_the_bank()
    {
        var connection = Connection.Create(Bank.TradeRepublic, "session", Now.AddDays(1), Now.AddDays(-89));
        _store.Add(connection);
        _store.Add(Account.Create(connection.Id, "uid", null, null, "EUR"));
        _time.Now = Now.AddDays(2);

        var result = await CreateSync().RunAsync(CancellationToken.None);

        Assert.Equal(1, result.SkippedConnections);
        Assert.Equal(0, _banking.Calls);
    }

    [Fact]
    public async Task A_revoked_session_is_recorded_and_its_accounts_are_not_read()
    {
        var account = AddAccount(Bank.CajaRuralDeNavarra, "uid-cr");
        var connection = _store.Connections.Single();
        _banking.AuthorizedSessions[connection.SessionId] = false;

        var result = await CreateSync().RunAsync(CancellationToken.None);

        Assert.Equal(1, result.SkippedConnections);
        Assert.Equal(ConnectionStatus.Expired, connection.StatusAt(Now));
        Assert.Equal(1, _store.Saves);
        Assert.Empty(_banking.TransactionRequests);
        Assert.Null(account.LastSyncedAt);
    }

    [Fact]
    public async Task A_failing_account_keeps_its_data_and_does_not_stop_the_others()
    {
        var failing = AddAccount(Bank.CajaRuralDeNavarra, "uid-cr");
        var healthy = AddAccount(Bank.TradeRepublic, "uid-tr");
        _banking.FailingAccounts.Add("uid-cr");
        _banking.Balances["uid-tr"] = Eur(100m);

        var result = await CreateSync().RunAsync(CancellationToken.None);

        Assert.Equal(1, result.FailedAccounts);
        Assert.Equal(1, result.SyncedAccounts);
        Assert.Null(failing.LastSyncedAt);
        Assert.Equal(Now, healthy.LastSyncedAt);
    }

    private Account AddAccount(Bank bank, string uid)
    {
        var connection = Connection.Create(bank, $"session-{uid}", Now.AddDays(90), Now.AddDays(-1));
        var account = Account.Create(connection.Id, uid, null, null, "EUR");
        _store.Add(connection);
        _store.Add(account);
        return account;
    }

    private SyncBanks CreateSync() =>
        new(_store, _store, _store, _store, _banking, _time, NullLogger<SyncBanks>.Instance);

    private static Money Eur(decimal amount) => new(amount, "EUR");

    private static BankTransaction Tx(int year, int month, int day, decimal amount) =>
        new(new DateOnly(year, month, day), null, Eur(amount), null, null, TransactionStatus.Booked);
}
