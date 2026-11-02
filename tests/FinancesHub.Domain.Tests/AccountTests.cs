using FinancesHub.Domain.Accounts;
using FinancesHub.Domain.Common;

namespace FinancesHub.Domain.Tests;

public sealed class AccountTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 2, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Has_no_balance_and_no_sync_until_the_first_sync()
    {
        var account = CreateAccount();

        Assert.Null(account.Balance);
        Assert.Null(account.LastSyncedAt);
    }

    [Fact]
    public void A_sync_records_the_balance_and_its_time()
    {
        var account = CreateAccount();

        account.RecordSync(new Money(987.76m, "EUR"), Now);

        Assert.Equal(new Money(987.76m, "EUR"), account.Balance);
        Assert.Equal(Now, account.LastSyncedAt);
    }

    [Fact]
    public void Rejects_a_balance_in_another_currency()
    {
        Assert.Throws<DomainException>(() => CreateAccount().RecordSync(new Money(1m, "USD"), Now));
    }

    [Fact]
    public void A_missing_name_is_null_rather_than_blank()
    {
        Assert.Null(Account.Create(Guid.NewGuid(), "uid", null, "  ", "EUR").Name);
    }

    [Fact]
    public void Relinking_keeps_the_account_with_a_new_uid()
    {
        var account = CreateAccount();
        var id = account.Id;

        account.Relink("new-uid", "Cuenta Corriente");

        Assert.Equal(id, account.Id);
        Assert.Equal("new-uid", account.ProviderAccountId);
        Assert.Equal("Cuenta Corriente", account.Name);
    }

    private static Account CreateAccount() =>
        Account.Create(Guid.NewGuid(), "uid", new Iban("ES9121000418450200051332"), "MI CUENTA", "EUR");
}
