using FinancesHub.Domain.Common;

namespace FinancesHub.Domain.Accounts;

/// <summary>
/// A bank account read through a connection, with its latest balance.
/// </summary>
public sealed class Account
{
    public const int MaxNameLength = 200;

    public Guid Id { get; private set; }
    public Guid ConnectionId { get; private set; }

    /// <summary>
    /// The account's <c>uid</c> in Enable Banking. It belongs to a session, so it changes when the connection is
    /// renewed; the IBAN is what identifies the account across sessions.
    /// </summary>
    public string ProviderAccountId { get; private set; }

    public Iban? Iban { get; private set; }
    public string? Name { get; private set; }
    public string Currency { get; private set; }

    public Money? Balance { get; private set; }
    public DateTimeOffset? BalanceUpdatedAt { get; private set; }

    /// <summary>Last time balance and transactions were read successfully. <c>null</c> until the first sync.</summary>
    public DateTimeOffset? LastSyncedAt { get; private set; }

    private Account(Guid id, Guid connectionId, string providerAccountId, Iban? iban, string? name, string currency)
    {
        Id = id;
        ConnectionId = connectionId;
        ProviderAccountId = providerAccountId;
        Iban = iban;
        Name = name;
        Currency = currency;
    }

    public static Account Create(Guid connectionId, string? providerAccountId, Iban? iban, string? name, string currency)
    {
        if (connectionId == Guid.Empty)
            throw new DomainException("The account must belong to a connection.");

        return new Account(Guid.CreateVersion7(), connectionId, ValidateProviderId(providerAccountId), iban,
            ValidateName(name), Money.ValidateCurrency(currency));
    }

    /// <summary>After a reconnection the same account comes back with a new <c>uid</c> and possibly a new name.</summary>
    public void Relink(string? providerAccountId, string? name)
    {
        ProviderAccountId = ValidateProviderId(providerAccountId);
        Name = ValidateName(name);
    }

    /// <summary>Records a successful sync: the balance read and the time it was read.</summary>
    public void RecordSync(Money balance, DateTimeOffset syncedAt)
    {
        if (balance.Currency != Currency)
            throw new DomainException($"The balance is in {balance.Currency}, but the account is in {Currency}.");

        Balance = balance;
        BalanceUpdatedAt = syncedAt;
        LastSyncedAt = syncedAt;
    }

    private static string ValidateProviderId(string? providerAccountId)
    {
        if (string.IsNullOrWhiteSpace(providerAccountId))
            throw new DomainException("The account needs its Enable Banking uid.");

        return providerAccountId.Trim();
    }

    // The bank may send no name; then the app shows the masked IBAN
    private static string? ValidateName(string? name)
    {
        if (string.IsNullOrWhiteSpace(name))
            return null;

        var trimmed = name.Trim();
        return trimmed.Length <= MaxNameLength ? trimmed : trimmed[..MaxNameLength];
    }
}
