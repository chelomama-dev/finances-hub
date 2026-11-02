using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace FinancesHub.Infrastructure.EnableBanking;

public static class EnableBankingServiceCollectionExtensions
{
    public const string HttpClientName = "EnableBanking";

    // Registers an HttpClient for the Enable Banking API that signs every request. The options are checked at
    // startup, so a missing application ID or key fails right away instead of on the first call
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

        services.AddSingleton(TimeProvider.System);
        services.AddSingleton<EnableBankingTokenProvider>();
        services.AddTransient<EnableBankingAuthHandler>();

        return services.AddHttpClient(HttpClientName, (sp, client) =>
                client.BaseAddress = sp.GetRequiredService<IOptions<EnableBankingOptions>>().Value.BaseUrl)
            .AddHttpMessageHandler<EnableBankingAuthHandler>();
    }
}
