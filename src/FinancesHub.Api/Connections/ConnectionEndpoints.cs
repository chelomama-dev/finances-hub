using System.ComponentModel.DataAnnotations;
using FinancesHub.Application.Abstractions;
using FinancesHub.Application.Banking;
using FinancesHub.Application.Connections;
using FinancesHub.Domain.Banks;
using FinancesHub.Domain.Connections;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;

namespace FinancesHub.Api.Connections;

// See docs/api.md → "List connections" and "Link a bank"
public static partial class ConnectionEndpoints
{
    public const string CallbackPath = "/api/connections/callback";

    public static IEndpointRouteBuilder MapConnections(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/connections").WithTags("Connections");

        group.MapGet("/", ListAsync);
        group.MapPost("/", StartAsync);
        group.MapPost("/{connectionId:guid}/renew", RenewAsync);

        // The bank's browser redirect: no app token can come with it; the one-use state is what protects it
        app.MapGet(CallbackPath, CallbackAsync).WithTags("Connections").ExcludeFromDescription();

        return app;
    }

    private static async Task<Ok<ConnectionListResponse>> ListAsync(
        IConnectionRepository connections, TimeProvider timeProvider, CancellationToken cancellationToken)
    {
        var now = timeProvider.GetUtcNow();
        var items = (await connections.ListAsync(cancellationToken))
            .Select(c => new ConnectionResponse(c.Id, c.Bank.Code, c.Bank.Name, ToContract(c.StatusAt(now)), c.ValidUntil))
            .ToList();

        return TypedResults.Ok(new ConnectionListResponse(items));
    }

    private static async Task<Results<Ok<AuthorizationResponse>, ValidationProblem>> StartAsync(
        StartLinkRequest request, LinkBank linkBank, CancellationToken cancellationToken)
    {
        if (Bank.FromCode(request.Bank) is not { } bank)
        {
            return TypedResults.ValidationProblem(new Dictionary<string, string[]>
            {
                ["bank"] = [$"Unknown bank. Use one of: {string.Join(", ", Bank.All.Select(b => b.Code))}."]
            });
        }

        return TypedResults.Ok(new AuthorizationResponse(await linkBank.StartAsync(bank, cancellationToken)));
    }

    private static async Task<Results<Ok<AuthorizationResponse>, NotFound>> RenewAsync(
        Guid connectionId, LinkBank linkBank, CancellationToken cancellationToken) =>
        await linkBank.StartRenewalAsync(connectionId, cancellationToken) is { } url
            ? TypedResults.Ok(new AuthorizationResponse(url))
            : TypedResults.NotFound();

    private static async Task<RedirectHttpResult> CallbackAsync(
        string? state, string? code, string? error,
        LinkBank linkBank, IOptions<AppLinkOptions> appLink, ILogger<LinkBank> logger, CancellationToken cancellationToken)
    {
        if (error is not null)
        {
            LogBankError(logger, error);
            return Result(appLink.Value, "error", ("reason", ToReason(error)));
        }

        try
        {
            return await linkBank.CompleteAsync(state, code, cancellationToken) switch
            {
                LinkResult.Success => Result(appLink.Value, "success", ("synced", "true")),
                LinkResult.LinkedButNotSynced => Result(appLink.Value, "success", ("synced", "false")),
                _ => Result(appLink.Value, "error", ("reason", "failed"))
            };
        }
        catch (BankingProviderException e)
        {
            LogLinkFailed(logger, e);
            return Result(appLink.Value, "error", ("reason", "failed"));
        }
    }

    // Enable Banking passes the bank's OAuth error through; these are the ones the app tells apart
    private static string ToReason(string error) => error.ToLowerInvariant() switch
    {
        var e when e.Contains("cancel") => "cancelled",
        var e when e.Contains("denied") || e.Contains("reject") => "denied",
        _ => "failed"
    };

    private static RedirectHttpResult Result(AppLinkOptions options, string status, (string Key, string Value) extra) =>
        TypedResults.Redirect(QueryHelpers.AddQueryString(options.ResultUrl, new Dictionary<string, string?>
        {
            ["status"] = status,
            [extra.Key] = extra.Value
        }));

    private static string ToContract(ConnectionStatus status) => status switch
    {
        ConnectionStatus.Active => "active",
        ConnectionStatus.Expiring => "expiring",
        _ => "expired"
    };

    [LoggerMessage(Level = LogLevel.Warning, Message = "The bank returned an error to the link callback: {Error}")]
    private static partial void LogBankError(ILogger logger, string error);

    [LoggerMessage(Level = LogLevel.Error, Message = "Completing a bank link failed")]
    private static partial void LogLinkFailed(ILogger logger, Exception exception);
}

public sealed record StartLinkRequest([property: Required] string? Bank);

public sealed record AuthorizationResponse(Uri AuthorizationUrl);

public sealed record ConnectionListResponse(IReadOnlyList<ConnectionResponse> Items);

public sealed record ConnectionResponse(Guid Id, string BankId, string BankName, string Status, DateTimeOffset ExpiresAt);

/// <summary>Bound from "AppLink": where the browser goes after a bank link, to get back into the app.</summary>
public sealed class AppLinkOptions
{
    public const string SectionName = "AppLink";

    public string ResultUrl { get; set; } = "financeshub://connections/result";
}
