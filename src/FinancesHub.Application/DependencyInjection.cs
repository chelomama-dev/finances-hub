using FinancesHub.Application.Connections;
using FinancesHub.Application.Queries;
using FinancesHub.Application.Sync;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace FinancesHub.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services, IConfiguration configuration)
    {
        services.AddOptions<BankLinkingOptions>().Bind(configuration.GetSection(BankLinkingOptions.SectionName));
        services.TryAddSingleton(TimeProvider.System);
        services.AddScoped<SyncBanks>();
        services.AddScoped<LinkBank>();
        services.AddScoped<GetSummary>();
        services.AddScoped<GetStatistics>();
        return services;
    }
}
