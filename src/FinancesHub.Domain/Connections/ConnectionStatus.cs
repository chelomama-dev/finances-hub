namespace FinancesHub.Domain.Connections;

public enum ConnectionStatus
{
    /// <summary>The consent is valid for longer than <see cref="Connection.ExpiringWithin"/>.</summary>
    Active,

    /// <summary>The consent is still valid but expires soon: the owner should reconnect.</summary>
    Expiring,

    /// <summary>The consent expired or was revoked: no more data can be read until the owner reconnects.</summary>
    Expired
}
