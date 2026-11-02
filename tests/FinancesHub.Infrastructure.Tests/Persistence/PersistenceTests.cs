using FinancesHub.Domain.Accounts;
using FinancesHub.Domain.Banks;
using FinancesHub.Domain.Common;
using FinancesHub.Domain.Connections;
using FinancesHub.Domain.Transactions;
using FinancesHub.Infrastructure.Persistence;
using FinancesHub.Infrastructure.Persistence.Repositories;
using Microsoft.EntityFrameworkCore;

namespace FinancesHub.Infrastructure.Tests.Persistence;

[Collection(nameof(SqlServerCollection))]
public sealed class PersistenceTests(SqlServerFixture fixture)
{
    private static readonly DateTimeOffset Now = new(2026, 11, 2, 7, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task Stores_and_reads_back_money_ibans_and_statuses()
    {
        var (_, account) = await SeedAsync();
        await using (var db = fixture.CreateContext())
        {
            db.Attach(account);
            account.RecordSync(new Money(987.7612m, "EUR"), Now);
            db.Transactions.Add(Tx(account.Id, 2026, 11, 1, -23.40m, TransactionStatus.Pending));
            await db.SaveChangesAsync(TestContext.Current.CancellationToken);
        }

        await using var read = fixture.CreateContext();
        var stored = await read.Accounts.SingleAsync(a => a.Id == account.Id, TestContext.Current.CancellationToken);
        Assert.Equal(new Money(987.7612m, "EUR"), stored.Balance);
        Assert.Equal("ES91 **** 1332", stored.Iban?.Masked);
        var transaction = await read.Transactions.SingleAsync(t => t.AccountId == account.Id, TestContext.Current.CancellationToken);
        Assert.Equal(new Money(-23.40m, "EUR"), transaction.Amount);
        Assert.Equal(TransactionStatus.Pending, transaction.Status);
    }

    [Fact]
    public async Task An_account_never_synced_has_no_balance()
    {
        var (_, account) = await SeedAsync();

        await using var db = fixture.CreateContext();
        var stored = await db.Accounts.SingleAsync(a => a.Id == account.Id, TestContext.Current.CancellationToken);
        Assert.Null(stored.Balance);
    }

    [Fact]
    public async Task Replacing_the_window_keeps_older_transactions_and_other_accounts()
    {
        var (_, account) = await SeedAsync();
        var (_, other) = await SeedAsync();
        await using (var db = fixture.CreateContext())
        {
            db.Transactions.AddRange(
                Tx(account.Id, 2026, 10, 1, -7m),
                Tx(account.Id, 2026, 10, 23, -5m),
                Tx(account.Id, 2026, 10, 30, -3m),
                Tx(other.Id, 2026, 10, 30, -9m));
            await db.SaveChangesAsync(TestContext.Current.CancellationToken);
        }

        await using (var db = fixture.CreateContext())
        {
            await new UnitOfWork(db).ExecuteInTransactionAsync(ct => new TransactionRepository(db).ReplaceAsync(
                account.Id, new DateOnly(2026, 10, 23), [Tx(account.Id, 2026, 11, 2, -1m)], ct), TestContext.Current.CancellationToken);
        }

        await using var read = fixture.CreateContext();
        Assert.Equal(
            [new DateOnly(2026, 10, 1), new DateOnly(2026, 11, 2)],
            await read.Transactions.Where(t => t.AccountId == account.Id).OrderBy(t => t.BookingDate).Select(t => t.BookingDate).ToListAsync(TestContext.Current.CancellationToken));
        Assert.Equal(1, await read.Transactions.CountAsync(t => t.AccountId == other.Id, TestContext.Current.CancellationToken));
    }

    [Fact]
    public async Task Nothing_is_deleted_if_the_work_fails_halfway()
    {
        var (_, account) = await SeedAsync();
        await using (var db = fixture.CreateContext())
        {
            db.Transactions.Add(Tx(account.Id, 2026, 10, 30, -3m));
            await db.SaveChangesAsync(TestContext.Current.CancellationToken);
        }

        await using (var db = fixture.CreateContext())
        {
            await Assert.ThrowsAsync<InvalidOperationException>(() => new UnitOfWork(db).ExecuteInTransactionAsync(async ct =>
            {
                await new TransactionRepository(db).ReplaceAsync(account.Id, null, [], ct);
                throw new InvalidOperationException("The sync failed after deleting.");
            }, TestContext.Current.CancellationToken));
        }

        await using var read = fixture.CreateContext();
        Assert.Equal(1, await read.Transactions.CountAsync(t => t.AccountId == account.Id, TestContext.Current.CancellationToken));
    }

    private async Task<(Connection, Account)> SeedAsync()
    {
        var connection = Connection.Create(Bank.CajaRuralDeNavarra, "session", Now.AddDays(180), Now);
        var account = Account.Create(connection.Id, "uid", new Iban("ES9121000418450200051332"), "TITULAR INVENTADO", "EUR");

        await using var db = fixture.CreateContext();
        db.Connections.Add(connection);
        db.Accounts.Add(account);
        await db.SaveChangesAsync(TestContext.Current.CancellationToken);
        return (connection, account);
    }

    private static Transaction Tx(Guid accountId, int year, int month, int day, decimal amount, TransactionStatus status = TransactionStatus.Booked) =>
        Transaction.Create(accountId, new DateOnly(year, month, day), null, new Money(amount, "EUR"), "TEXTO INVENTADO", null, status);
}
