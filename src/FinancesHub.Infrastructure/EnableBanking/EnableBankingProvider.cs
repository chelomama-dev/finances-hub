using System.Net.Http.Json;
using System.Text.Json;
using FinancesHub.Application.Banking;
using FinancesHub.Domain.Banks;
using FinancesHub.Domain.Common;
using FinancesHub.Infrastructure.EnableBanking.Api;

namespace FinancesHub.Infrastructure.EnableBanking;

// IBankingProvider over the Enable Banking API. The HttpClient comes from AddEnableBankingHttpClient, which signs
// every request
internal sealed class EnableBankingProvider(HttpClient http, TimeProvider timeProvider) : IBankingProvider
{
    // Far more than a personal account needs (the spike's 13 months were 2 pages). Hitting it means the bank keeps
    // returning continuation keys, and a partial list must never reach the sync
    internal const int MaxPages = 100;

    // Asked for a little less than the bank's maximum, so clock differences don't get the request rejected
    private static readonly TimeSpan ConsentMargin = TimeSpan.FromMinutes(10);

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
    };

    public async Task<BankAuthorization> StartAuthorizationAsync(Bank bank, Uri redirectUrl, string state, CancellationToken cancellationToken)
    {
        var aspsps = await GetAsync<AspspsResponse>($"/aspsps?country={bank.Country}&service=AIS", cancellationToken);
        var aspsp = aspsps.Aspsps?.FirstOrDefault(a => a.Name == bank.Name)
            ?? throw new BankingProviderException($"Enable Banking doesn't list {bank.Name} in {bank.Country}.");

        var maxValidity = TimeSpan.FromSeconds(aspsp.MaximumConsentValidity ?? (long)TimeSpan.FromDays(90).TotalSeconds);
        var validUntil = timeProvider.GetUtcNow() + maxValidity - ConsentMargin;

        var response = await PostAsync<AuthResponse>("/auth",
            new AuthRequest(new AuthAccess(validUntil), new AuthAspsp(bank.Name, bank.Country), state, redirectUrl, "personal"),
            cancellationToken);

        return new BankAuthorization(response.Url ?? throw new BankingProviderException("Enable Banking returned no authorization URL."), validUntil);
    }

    public async Task<BankSession> CreateSessionAsync(string code, CancellationToken cancellationToken)
    {
        var response = await PostAsync<SessionResponse>("/sessions", new SessionRequest(code), cancellationToken);

        return new BankSession(
            response.SessionId ?? throw new BankingProviderException("Enable Banking returned no session ID."),
            response.Access?.ValidUntil ?? throw new BankingProviderException("Enable Banking returned no consent expiry."),
            (response.Accounts ?? []).Select(EnableBankingMapper.ToAccount).ToList());
    }

    public async Task<bool> IsSessionAuthorizedAsync(string sessionId, CancellationToken cancellationToken)
    {
        var response = await GetAsync<SessionStatusResponse>($"/sessions/{Uri.EscapeDataString(sessionId)}", cancellationToken);
        return response.Status == "AUTHORIZED";
    }

    public async Task<Money> GetBalanceAsync(string providerAccountId, CancellationToken cancellationToken)
    {
        var response = await GetAsync<BalancesResponse>($"/accounts/{Uri.EscapeDataString(providerAccountId)}/balances", cancellationToken);
        return EnableBankingMapper.ToBalance(response.Balances ?? []);
    }

    public async Task<IReadOnlyList<BankTransaction>> GetTransactionsAsync(string providerAccountId, DateOnly? from, CancellationToken cancellationToken)
    {
        // Without a start date, "longest" asks for all the history the bank gives (only right after linking)
        var query = from is { } date ? $"date_from={date:yyyy-MM-dd}" : "strategy=longest";
        var path = $"/accounts/{Uri.EscapeDataString(providerAccountId)}/transactions?{query}";

        var transactions = new List<BankTransaction>();
        string? continuationKey = null;
        for (var page = 1; ; page++)
        {
            if (page > MaxPages)
                throw new BankingProviderException($"Stopped after {MaxPages} pages of transactions: the bank keeps returning more.");

            // Every page repeats the same filters, plus the key of the previous page
            var url = continuationKey is null ? path : $"{path}&continuation_key={Uri.EscapeDataString(continuationKey)}";
            var response = await GetAsync<TransactionsResponse>(url, cancellationToken);

            transactions.AddRange((response.Transactions ?? [])
                .Select(EnableBankingMapper.ToTransaction)
                .OfType<BankTransaction>());

            // An empty page can still carry a key, so only the key decides when to stop
            continuationKey = response.ContinuationKey;
            if (string.IsNullOrEmpty(continuationKey))
                return transactions;
        }
    }

    private async Task<T> GetAsync<T>(string path, CancellationToken cancellationToken) =>
        await ReadAsync<T>(await http.GetAsync(path, cancellationToken), cancellationToken);

    private async Task<T> PostAsync<T>(string path, object body, CancellationToken cancellationToken) =>
        await ReadAsync<T>(await http.PostAsJsonAsync(path, body, Json, cancellationToken), cancellationToken);

    private static async Task<T> ReadAsync<T>(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        using (response)
        {
            var path = response.RequestMessage?.RequestUri?.AbsolutePath;
            if (!response.IsSuccessStatusCode)
            {
                // The body says why (an inactive application, an expired session...); it never holds bank data
                var error = await TryReadAsync<ErrorResponse>(response, cancellationToken);
                throw new BankingProviderException(
                    $"Enable Banking answered {(int)response.StatusCode} to {path}: {error?.Message ?? response.ReasonPhrase}"
                    + (error?.Error is { } code ? $" ({code})" : ""),
                    (int)response.StatusCode);
            }

            return await TryReadAsync<T>(response, cancellationToken)
                ?? throw new BankingProviderException($"Enable Banking returned an empty response to {path}.");
        }
    }

    private static async Task<T?> TryReadAsync<T>(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        try
        {
            return await response.Content.ReadFromJsonAsync<T>(Json, cancellationToken);
        }
        catch (JsonException e) when (response.IsSuccessStatusCode)
        {
            throw new BankingProviderException($"Enable Banking returned JSON we can't read: {e.Message}", (int)response.StatusCode, e);
        }
        catch (JsonException)
        {
            return default;
        }
    }
}
