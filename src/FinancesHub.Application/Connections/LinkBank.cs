using FinancesHub.Application.Abstractions;
using FinancesHub.Application.Banking;
using FinancesHub.Application.Sync;
using FinancesHub.Domain.Accounts;
using FinancesHub.Domain.Banks;
using FinancesHub.Domain.Connections;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FinancesHub.Application.Connections;

/// <summary>
/// Links a bank or renews its consent: start returns the bank's login URL, complete handles the bank's callback.
/// </summary>
public sealed partial class LinkBank(
    ILinkRequestRepository linkRequests,
    IConnectionRepository connections,
    IAccountRepository accounts,
    IUnitOfWork unitOfWork,
    IBankingProvider banking,
    SyncBanks sync,
    IOptions<BankLinkingOptions> options,
    TimeProvider timeProvider,
    ILogger<LinkBank> logger)
{
    public async Task<Uri> StartAsync(Bank bank, CancellationToken cancellationToken) =>
        await StartAsync(LinkRequest.ToLink(bank, timeProvider.GetUtcNow()), cancellationToken);

    /// <returns><c>null</c> if the connection doesn't exist.</returns>
    public async Task<Uri?> StartRenewalAsync(Guid connectionId, CancellationToken cancellationToken)
    {
        var connection = await connections.GetAsync(connectionId, cancellationToken);
        return connection is null
            ? null
            : await StartAsync(LinkRequest.ToRenew(connection, timeProvider.GetUtcNow()), cancellationToken);
    }

    private async Task<Uri> StartAsync(LinkRequest request, CancellationToken cancellationToken)
    {
        // Links the owner started and abandoned would otherwise pile up
        await linkRequests.RemoveCreatedBeforeAsync(request.CreatedAt - LinkRequest.ValidFor, cancellationToken);

        var authorization = await banking.StartAuthorizationAsync(request.Bank, request.Id.ToString(), cancellationToken);

        linkRequests.Add(request);
        await unitOfWork.SaveChangesAsync(cancellationToken);

        return authorization.Url;
    }

    /// <summary>
    /// The bank sent the browser back with <paramref name="code"/>. Saves the connection and the allowed accounts,
    /// then syncs them right away: banks give the full history only just after linking.
    /// </summary>
    public async Task<LinkResult> CompleteAsync(string? state, string? code, CancellationToken cancellationToken)
    {
        var now = timeProvider.GetUtcNow();
        if (await TakeRequestAsync(state, cancellationToken) is not { } request)
        {
            LogUnknownState();
            return LinkResult.Failed;
        }

        if (request.IsExpiredAt(now) || string.IsNullOrWhiteSpace(code))
        {
            LogExpiredOrEmpty(request.Bank.Name);
            return LinkResult.Failed;
        }

        var session = await banking.CreateSessionAsync(code, cancellationToken);

        var connection = request.ConnectionId is { } id ? await connections.GetAsync(id, cancellationToken) : null;
        if (connection is null)
        {
            connection = Connection.Create(request.Bank, session.SessionId, session.ValidUntil, now);
            connections.Add(connection);
        }
        else
        {
            connection.Renew(session.SessionId, session.ValidUntil, now);
        }

        await SaveAccountsAsync(connection, session.Accounts, cancellationToken);
        await unitOfWork.SaveChangesAsync(cancellationToken);
        LogLinked(request.Bank.Name, session.ValidUntil);

        // A failed first sync doesn't undo the link: the scheduled sync tries again
        var result = await sync.RunAsync(connection, cancellationToken);
        return result.FailedAccounts == 0 ? LinkResult.Success : LinkResult.LinkedButNotSynced;
    }

    /// <summary>The bank sent the browser back with an error instead of a code.</summary>
    public async Task FailAsync(string? state, string error, string? description, CancellationToken cancellationToken)
    {
        var request = await TakeRequestAsync(state, cancellationToken);
        LogBankError(request?.Bank.Name ?? "an unknown bank", error, description);
    }

    // A request is used once, whatever happens next
    private async Task<LinkRequest?> TakeRequestAsync(string? state, CancellationToken cancellationToken)
    {
        if (!Guid.TryParse(state, out var requestId)
            || await linkRequests.GetAsync(requestId, cancellationToken) is not { } request)
            return null;

        linkRequests.Remove(request);
        await unitOfWork.SaveChangesAsync(cancellationToken);
        return request;
    }

    private async Task SaveAccountsAsync(Connection connection, IReadOnlyList<BankAccount> shared, CancellationToken cancellationToken)
    {
        var allowed = options.Value.AllowedIbanSet;
        var existing = await accounts.ListByConnectionAsync(connection.Id, cancellationToken);

        foreach (var account in shared)
        {
            if (allowed.Count > 0 && (account.Iban is not { } iban || !allowed.Contains(iban.Value)))
            {
                LogNotAllowed(connection.Bank.Name, account.Iban?.Masked);
                continue;
            }

            // On a renewal the same account comes back with a new uid; the IBAN tells it is the same one
            var match = existing.FirstOrDefault(a => account.Iban is not null && a.Iban == account.Iban);
            if (match is not null)
                match.Relink(account.ProviderAccountId, account.Name);
            else
                accounts.Add(Account.Create(connection.Id, account.ProviderAccountId, account.Iban, account.Name, account.Currency));
        }
    }

    [LoggerMessage(Level = LogLevel.Warning, Message = "Linking {Bank} failed at the bank: {Error} ({Description})")]
    private partial void LogBankError(string bank, string error, string? description);

    [LoggerMessage(Level = LogLevel.Warning, Message = "Bank callback with an unknown state: ignored")]
    private partial void LogUnknownState();

    [LoggerMessage(Level = LogLevel.Warning, Message = "Bank callback for {Bank} expired or without a code")]
    private partial void LogExpiredOrEmpty(string bank);

    [LoggerMessage(Level = LogLevel.Information, Message = "{Bank} linked, consent valid until {ValidUntil}")]
    private partial void LogLinked(string bank, DateTimeOffset validUntil);

    [LoggerMessage(Level = LogLevel.Information, Message = "Account {MaskedIban} of {Bank} is not in the allowed list: not saved")]
    private partial void LogNotAllowed(string bank, string? maskedIban);
}

public enum LinkResult
{
    Success,

    /// <summary>The bank is linked, but the first sync failed; the scheduled one will try again.</summary>
    LinkedButNotSynced,

    Failed
}
