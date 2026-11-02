using FinancesHub.Domain.Banks;
using FinancesHub.Domain.Common;

namespace FinancesHub.Domain.Connections;

/// <summary>
/// A bank linked through Enable Banking: a session with a consent that expires. Reconnecting renews the same
/// connection with a new session, so the accounts and their history stay.
/// </summary>
public sealed class Connection
{
    /// <summary>From this long before the consent expires, the connection shows as expiring.</summary>
    public static readonly TimeSpan ExpiringWithin = TimeSpan.FromDays(14);

    public Guid Id { get; private set; }

    /// <summary><see cref="Bank.Code"/> of the linked bank.</summary>
    public string BankCode { get; private set; }

    /// <summary>The Enable Banking session ID.</summary>
    public string SessionId { get; private set; }

    public DateTimeOffset ValidUntil { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset? RevokedAt { get; private set; }

    public Bank Bank => Bank.FromCode(BankCode)!;

    private Connection(Guid id, string bankCode, string sessionId, DateTimeOffset validUntil, DateTimeOffset createdAt)
    {
        Id = id;
        BankCode = bankCode;
        SessionId = sessionId;
        ValidUntil = validUntil;
        CreatedAt = createdAt;
    }

    public static Connection Create(Bank bank, string? sessionId, DateTimeOffset validUntil, DateTimeOffset now)
    {
        ArgumentNullException.ThrowIfNull(bank);

        return new Connection(Guid.CreateVersion7(), bank.Code, ValidateSession(sessionId, validUntil, now), validUntil, now);
    }

    /// <summary>The owner went through the bank's consent again: a new session replaces the old one.</summary>
    public void Renew(string? sessionId, DateTimeOffset validUntil, DateTimeOffset now)
    {
        SessionId = ValidateSession(sessionId, validUntil, now);
        ValidUntil = validUntil;
        RevokedAt = null;
    }

    /// <summary>The bank or Enable Banking reported that the session is no longer authorised.</summary>
    public void Revoke(DateTimeOffset now) => RevokedAt ??= now;

    public ConnectionStatus StatusAt(DateTimeOffset now)
    {
        if (RevokedAt is not null || now >= ValidUntil)
            return ConnectionStatus.Expired;

        return ValidUntil - now <= ExpiringWithin ? ConnectionStatus.Expiring : ConnectionStatus.Active;
    }

    private static string ValidateSession(string? sessionId, DateTimeOffset validUntil, DateTimeOffset now)
    {
        if (string.IsNullOrWhiteSpace(sessionId))
            throw new DomainException("The connection needs an Enable Banking session.");

        if (validUntil <= now)
            throw new DomainException("The consent of a new session must be valid in the future.");

        return sessionId.Trim();
    }
}
