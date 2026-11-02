using FinancesHub.Application.Abstractions;
using FinancesHub.Application.Queries;
using FinancesHub.Infrastructure.EnableBanking;
using FinancesHub.Infrastructure.Persistence;
using FinancesHub.Infrastructure.Persistence.Repositories;
using Microsoft.Extensions.DependencyInjection;
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

        builder.Services.AddScoped<IUnitOfWork, UnitOfWork>();
        builder.Services.AddScoped<IConnectionRepository, ConnectionRepository>();
        builder.Services.AddScoped<ILinkRequestRepository, LinkRequestRepository>();
        builder.Services.AddScoped<IAccountRepository, AccountRepository>();
        builder.Services.AddScoped<ITransactionRepository, TransactionRepository>();
        builder.Services.AddScoped<IFinanceQueries, FinanceQueries>();

        builder.Services.AddEnableBanking(builder.Configuration);

        return builder;
    }
}
