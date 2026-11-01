using FinancesHub.Infrastructure.Persistence;
using Microsoft.Extensions.Hosting;

namespace FinancesHub.Infrastructure;

public static class DependencyInjection
{
    // Name of the database resource in the AppHost; Aspire passes its connection string as ConnectionStrings__financesdb
    public const string DatabaseName = "financesdb";

    public static IHostApplicationBuilder AddInfrastructure(this IHostApplicationBuilder builder)
    {
        // Registers the DbContext with retries, health check and OpenTelemetry
        builder.AddSqlServerDbContext<FinancesDbContext>(DatabaseName);

        return builder;
    }
}
