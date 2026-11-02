using FinancesHub.Application.Abstractions;
using FinancesHub.Application.Banking;
using FinancesHub.Domain.Accounts;
using FinancesHub.Domain.Common;
using FinancesHub.Domain.Connections;
using FinancesHub.Domain.Transactions;
using Microsoft.Extensions.Logging;

namespace FinancesHub.Application.Sync;

/// <summary>
/// One sync run: for every linked bank whose consent is still valid, reads each account's balance and the
/// transactions of its window, and replaces them in the database (ADR 0001). One account failing doesn't stop
/// the others.
/// </summary>
public sealed partial class SyncBanks(
    IConnectionRepository connections,
    IAccountRepository accounts,
    ITransactionRepository transactions,
    IUnitOfWork unitOfWork,
    IBankingProvider banking,
    TimeProvider timeProvider,
    ILogger<SyncBanks> logger)
{
    public async Task<SyncResult> RunAsync(CancellationToken cancellationToken)
    {
        var result = new SyncResult();

        foreach (var connection in await connections.ListAsync(cancellationToken))
        {
            if (!await CanReadAsync(connection, cancellationToken))
            {
                result.SkippedConnections++;
                continue;
            }

            foreach (var account in await accounts.ListByConnectionAsync(connection.Id, cancellationToken))
            {
                try
                {
                    await SyncAccountAsync(account, cancellationToken);
                    result.SyncedAccounts++;
                }
                catch (Exception e) when (e is BankingProviderException or DomainException or HttpRequestException or TaskCanceledException
                                          && !cancellationToken.IsCancellationRequested)
                {
                    LogAccountFailed(e, connection.Bank.Name, account.Id);
                    result.FailedAccounts++;
                }
            }
        }

        return result;
    }

    private async Task<bool> CanReadAsync(Connection connection, CancellationToken cancellationToken)
    {
        var now = timeProvider.GetUtcNow();
        if (connection.StatusAt(now) == ConnectionStatus.Expired)
        {
            LogConsentExpired(connection.Bank.Name);
            return false;
        }

        // Asked to Enable Banking, not to the bank: it doesn't use up the bank's few daily requests
        if (!await banking.IsSessionAuthorizedAsync(connection.SessionId, cancellationToken))
        {
            connection.Revoke(now);
            await unitOfWork.SaveChangesAsync(cancellationToken);
            LogConsentRevoked(connection.Bank.Name);
            return false;
        }

        return true;
    }

    private async Task SyncAccountAsync(Account account, CancellationToken cancellationToken)
    {
        var windowStart = TransactionWindow.StartFor(account.LastSyncedAt);

        // Everything is read before anything is written: if a call fails, the stored data stays as it was
        var balance = await banking.GetBalanceAsync(account.ProviderAccountId, cancellationToken);
        var read = await banking.GetTransactionsAsync(account.ProviderAccountId, windowStart, cancellationToken);

        // Banks may filter date_from by another date, so anything booked before the window is dropped: it is
        // outside what gets deleted and would be stored twice
        var replacement = read
            .Where(t => windowStart is null || t.BookingDate >= windowStart)
            .Select(t => Transaction.Create(account.Id, t.BookingDate, t.ValueDate, t.Amount, t.Description, t.Counterparty, t.Status))
            .ToList();

        var syncedAt = timeProvider.GetUtcNow();
        await unitOfWork.ExecuteInTransactionAsync(async ct =>
        {
            await transactions.ReplaceAsync(account.Id, windowStart, replacement, ct);
            account.RecordSync(balance, syncedAt);
        }, cancellationToken);

        LogAccountSynced(account.Id, replacement.Count, windowStart);
    }

    [LoggerMessage(Level = LogLevel.Information, Message = "Account {AccountId} synced: {Count} transactions from {WindowStart}")]
    private partial void LogAccountSynced(Guid accountId, int count, DateOnly? windowStart);

    [LoggerMessage(Level = LogLevel.Error, Message = "Account {AccountId} of {Bank} failed to sync; its stored data is unchanged")]
    private partial void LogAccountFailed(Exception exception, string bank, Guid accountId);

    [LoggerMessage(Level = LogLevel.Warning, Message = "The consent for {Bank} has expired: reconnect it to keep syncing")]
    private partial void LogConsentExpired(string bank);

    [LoggerMessage(Level = LogLevel.Warning, Message = "The consent for {Bank} is no longer authorised: reconnect it to keep syncing")]
    private partial void LogConsentRevoked(string bank);
}

public sealed class SyncResult
{
    public int SyncedAccounts { get; set; }
    public int FailedAccounts { get; set; }

    /// <summary>Connections not read because their consent expired or was revoked.</summary>
    public int SkippedConnections { get; set; }
}
