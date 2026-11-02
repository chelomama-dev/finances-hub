using System.Net;
using System.Security.Cryptography;
using FinancesHub.Application.Banking;
using FinancesHub.Infrastructure.EnableBanking;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace FinancesHub.Infrastructure.Tests.EnableBanking;

public sealed class EnableBankingHttpClientTests
{
    [Fact]
    public async Task A_failed_request_is_not_retried_even_with_the_apps_default_resilience()
    {
        using var key = RSA.Create(2048);
        var handler = new CountingHandler();
        var services = new ServiceCollection();

        // What ServiceDefaults does for every HttpClient in the API and the sync
        services.ConfigureHttpClientDefaults(http => http.AddStandardResilienceHandler());
        services.AddEnableBanking(new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["EnableBanking:ApplicationId"] = "test",
            ["EnableBanking:PrivateKey"] = key.ExportPkcs8PrivateKeyPem()
        }).Build());
        services.AddHttpClient(EnableBankingServiceCollectionExtensions.HttpClientName).ConfigurePrimaryHttpMessageHandler(() => handler);

        await using var provider = services.BuildServiceProvider();
        var banking = provider.GetRequiredService<IBankingProvider>();

        await Assert.ThrowsAsync<BankingProviderException>(() => banking.GetBalanceAsync("uid", TestContext.Current.CancellationToken));
        Assert.Equal(1, handler.Calls);
    }

    private sealed class CountingHandler : HttpMessageHandler
    {
        public int Calls { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable)
            {
                RequestMessage = request,
                Content = new StringContent("""{ "code": 503, "message": "Bank unavailable" }""")
            });
        }
    }
}
