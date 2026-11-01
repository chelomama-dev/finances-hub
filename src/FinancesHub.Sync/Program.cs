using FinancesHub.Infrastructure;
using FinancesHub.Sync;

// Pulls balances and transactions from the banks through Enable Banking, saves them and exits.
// In Azure it runs as a Container Apps Job on a schedule: banks allow only a few background requests a day
var builder = Host.CreateApplicationBuilder(args);

builder.AddServiceDefaults();
builder.AddInfrastructure();

builder.Services.AddScoped<BankSync>();

// Checked at startup: a missing registration fails the run right away instead of halfway through a sync
builder.ConfigureContainer(new DefaultServiceProviderFactory(new ServiceProviderOptions
{
    ValidateOnBuild = true,
    ValidateScopes = true
}));

using var host = builder.Build();

// Started so the OpenTelemetry exporters run, and stopped at the end so they flush before the process exits
await host.StartAsync();

await using (var scope = host.Services.CreateAsyncScope())
{
    await scope.ServiceProvider.GetRequiredService<BankSync>().RunAsync(CancellationToken.None);
}

await host.StopAsync();
