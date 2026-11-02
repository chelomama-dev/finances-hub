using FinancesHub.Application.Sync;
using Microsoft.Extensions.DependencyInjection;

namespace FinancesHub.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        services.AddScoped<SyncBanks>();
        return services;
    }
}
