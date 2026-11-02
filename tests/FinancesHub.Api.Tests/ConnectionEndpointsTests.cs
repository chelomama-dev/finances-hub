using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Web;
using FinancesHub.Application.Banking;
using FinancesHub.Domain.Accounts;
using Microsoft.AspNetCore.Mvc.Testing;

namespace FinancesHub.Api.Tests;

[Collection(nameof(ApiCollection))]
public sealed class ConnectionEndpointsTests(ApiFactory factory)
{
    private readonly HttpClient _client = factory.CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });

    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Linking_an_unknown_bank_is_a_validation_error()
    {
        var response = await _client.PostAsJsonAsync("/api/connections", new { bank = "unknown" }, Ct);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var problem = await response.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.True(problem.GetProperty("errors").TryGetProperty("bank", out _));
    }

    [Fact]
    public async Task A_full_link_redirects_to_the_app_and_lists_the_connection()
    {
        var start = await _client.PostAsJsonAsync("/api/connections", new { bank = "trade-republic" }, Ct);
        start.EnsureSuccessStatusCode();
        var authorizationUrl = (await start.Content.ReadFromJsonAsync<JsonElement>(Ct)).GetProperty("authorizationUrl").GetString()!;
        var state = HttpUtility.ParseQueryString(new Uri(authorizationUrl).Query)["state"];

        factory.Banking.NextSession = new BankSession($"session-{state}", DateTimeOffset.UtcNow.AddDays(90),
            [new BankAccount($"uid-{state}", new Iban("ES9121000418450200051332"), null, "EUR")]);
        var callback = await _client.GetAsync($"/api/connections/callback?state={state}&code=code-1", Ct);

        Assert.Equal(HttpStatusCode.Redirect, callback.StatusCode);
        Assert.Equal("financeshub://connections/result?status=success&synced=true", callback.Headers.Location?.ToString());

        var list = await _client.GetFromJsonAsync<JsonElement>("/api/connections", Ct);
        Assert.Contains(list.GetProperty("items").EnumerateArray(), c =>
            c.GetProperty("bankId").GetString() == "trade-republic"
            && c.GetProperty("bankName").GetString() == "Trade Republic"
            && c.GetProperty("status").GetString() == "active");
    }

    [Fact]
    public async Task A_callback_with_an_unknown_state_fails()
    {
        var callback = await _client.GetAsync($"/api/connections/callback?state={Guid.NewGuid()}&code=code-1", Ct);

        Assert.Equal("financeshub://connections/result?status=error&reason=failed", callback.Headers.Location?.ToString());
    }

    [Theory]
    [InlineData("user_cancelled", "cancelled")]
    [InlineData("access_denied", "denied")]
    [InlineData("server_error", "failed")]
    public async Task A_bank_error_tells_the_app_why(string error, string reason)
    {
        var callback = await _client.GetAsync($"/api/connections/callback?error={error}&error_description=x", Ct);

        Assert.Equal($"financeshub://connections/result?status=error&reason={reason}", callback.Headers.Location?.ToString());
    }

    [Fact]
    public async Task Renewing_a_connection_that_does_not_exist_is_not_found()
    {
        var response = await _client.PostAsync($"/api/connections/{Guid.NewGuid()}/renew", null, Ct);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }
}
