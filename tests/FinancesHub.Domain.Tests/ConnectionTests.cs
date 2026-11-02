using FinancesHub.Domain.Banks;
using FinancesHub.Domain.Common;
using FinancesHub.Domain.Connections;

namespace FinancesHub.Domain.Tests;

public sealed class ConnectionTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 2, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Is_active_while_the_consent_has_more_than_14_days_left()
    {
        var connection = Connection.Create(Bank.TradeRepublic, "session", Now.AddDays(90), Now);

        Assert.Equal(ConnectionStatus.Active, connection.StatusAt(Now));
        Assert.Equal(ConnectionStatus.Active, connection.StatusAt(Now.AddDays(76).AddSeconds(-1)));
    }

    [Fact]
    public void Is_expiring_in_the_last_14_days()
    {
        var connection = Connection.Create(Bank.TradeRepublic, "session", Now.AddDays(90), Now);

        Assert.Equal(ConnectionStatus.Expiring, connection.StatusAt(Now.AddDays(76)));
        Assert.Equal(ConnectionStatus.Expiring, connection.StatusAt(Now.AddDays(90).AddSeconds(-1)));
    }

    [Fact]
    public void Is_expired_once_the_consent_ends_or_is_revoked()
    {
        var connection = Connection.Create(Bank.TradeRepublic, "session", Now.AddDays(90), Now);
        Assert.Equal(ConnectionStatus.Expired, connection.StatusAt(Now.AddDays(90)));

        connection.Revoke(Now.AddDays(1));
        Assert.Equal(ConnectionStatus.Expired, connection.StatusAt(Now.AddDays(2)));
    }

    [Fact]
    public void Renewing_replaces_the_session_and_clears_a_revocation()
    {
        var connection = Connection.Create(Bank.CajaRuralDeNavarra, "old", Now.AddDays(180), Now);
        connection.Revoke(Now.AddDays(10));

        connection.Renew("new", Now.AddDays(200), Now.AddDays(20));

        Assert.Equal("new", connection.SessionId);
        Assert.Null(connection.RevokedAt);
        Assert.Equal(ConnectionStatus.Active, connection.StatusAt(Now.AddDays(20)));
    }

    [Fact]
    public void Needs_a_session_with_a_consent_in_the_future()
    {
        Assert.Throws<DomainException>(() => Connection.Create(Bank.TradeRepublic, " ", Now.AddDays(90), Now));
        Assert.Throws<DomainException>(() => Connection.Create(Bank.TradeRepublic, "session", Now, Now));
    }
}

public sealed class LinkRequestTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 2, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Is_valid_for_30_minutes()
    {
        var request = LinkRequest.ToLink(Bank.TradeRepublic, Now);

        Assert.False(request.IsExpiredAt(Now.AddMinutes(30)));
        Assert.True(request.IsExpiredAt(Now.AddMinutes(30).AddSeconds(1)));
    }

    [Fact]
    public void Its_state_is_random_not_time_based()
    {
        Assert.Equal(4, LinkRequest.ToLink(Bank.TradeRepublic, Now).Id.Version);
    }

    [Fact]
    public void A_renewal_points_to_its_connection()
    {
        var connection = Connection.Create(Bank.CajaRuralDeNavarra, "session", Now.AddDays(180), Now);

        var request = LinkRequest.ToRenew(connection, Now);

        Assert.Equal(connection.Id, request.ConnectionId);
        Assert.Equal(Bank.CajaRuralDeNavarra.Code, request.BankCode);
    }
}
