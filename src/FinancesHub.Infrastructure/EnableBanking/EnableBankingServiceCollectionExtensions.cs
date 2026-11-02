using FinancesHub.Application.Banking;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Options;

namespace FinancesHub.Infrastructure.EnableBanking;

public static class EnableBankingServiceCollectionExtensions
{
    public const string HttpClientName = "EnableBanking";

    // Banks can be slow to answer through Enable Banking; still bounded, so a stuck call can't hang a sync run
    internal static readonly TimeSpan RequestTimeout = TimeSpan.FromSeconds(60);

    // Registers an HttpClient for the Enable Banking API that signs every request. The options are checked at
    // startup, so a missing application ID or key fails right away instead of on the first call
    /// <summary>Registers <see cref="IBankingProvider"/> over Enable Banking.</summary>
    public static IServiceCollection AddEnableBanking(this IServiceCollection services, IConfiguration configuration)
    {
        services.AddEnableBankingHttpClient(configuration).AddTypedClient<IBankingProvider, EnableBankingProvider>();
        return services;
    }

    public static IHttpClientBuilder AddEnableBankingHttpClient(
        this IServiceCollection services, IConfiguration configuration)
    {
        services.AddOptions<EnableBankingOptions>()
            .Bind(configuration.GetSection(EnableBankingOptions.SectionName))
            .Validate(o => !string.IsNullOrWhiteSpace(o.ApplicationId),
                $"{EnableBankingOptions.SectionName}:ApplicationId is required")
            .Validate(o => !string.IsNullOrWhiteSpace(o.PrivateKey) || File.Exists(o.PrivateKeyPath),
                $"{EnableBankingOptions.SectionName}:PrivateKey or an existing PrivateKeyPath is required")
            .ValidateOnStart();

        services.TryAddSingleton(TimeProvider.System);
        services.AddSingleton<EnableBankingTokenProvider>();
        services.AddTransient<EnableBankingAuthHandler>();

        // RemoveAllResilienceHandlers is marked experimental, but it is the supported way to undo
        // ConfigureHttpClientDefaults for one client; configuring the default pipeline by its internal name instead
        // would be more fragile
#pragma warning disable EXTEXP0001
        return services.AddHttpClient(HttpClientName, (sp, client) =>
            {
                client.BaseAddress = sp.GetRequiredService<IOptions<EnableBankingOptions>>().Value.BaseUrl;
                client.Timeout = RequestTimeout;
            })
            // No retries, unlike every other HttpClient (ServiceDefaults): each retry of a bank read uses up one of
            // the few background requests a bank allows a day, and an authorization code can be exchanged only
            // once. A failed sync is caught up by the next scheduled run (ADR 0001)
            .RemoveAllResilienceHandlers()
            .AddHttpMessageHandler<EnableBankingAuthHandler>();
#pragma warning restore EXTEXP0001
    }
}
