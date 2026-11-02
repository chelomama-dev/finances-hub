using FinancesHub.Domain.Banks;

namespace FinancesHub.Domain.Connections;

/// <summary>
/// A bank link started by the owner and waiting for the bank to send the browser back. Its ID is the OAuth
/// <c>state</c>: random, used once, and only valid for <see cref="ValidFor"/>, so a callback that the app didn't
/// start is rejected.
/// </summary>
public sealed class LinkRequest
{
    public static readonly TimeSpan ValidFor = TimeSpan.FromMinutes(30);

    public Guid Id { get; private set; }
    public string BankCode { get; private set; }

    /// <summary>The connection being renewed, or <c>null</c> when linking a bank for the first time.</summary>
    public Guid? ConnectionId { get; private set; }

    public DateTimeOffset CreatedAt { get; private set; }

    public Bank Bank => Bank.FromCode(BankCode)!;

    private LinkRequest(Guid id, string bankCode, Guid? connectionId, DateTimeOffset createdAt)
    {
        Id = id;
        BankCode = bankCode;
        ConnectionId = connectionId;
        CreatedAt = createdAt;
    }

    // Version 4, not 7: the state must be unguessable, and a v7 GUID starts with the time it was made
    public static LinkRequest ToLink(Bank bank, DateTimeOffset now) => new(Guid.NewGuid(), bank.Code, null, now);

    public static LinkRequest ToRenew(Connection connection, DateTimeOffset now) =>
        new(Guid.NewGuid(), connection.BankCode, connection.Id, now);

    public bool IsExpiredAt(DateTimeOffset now) => now - CreatedAt > ValidFor;
}
