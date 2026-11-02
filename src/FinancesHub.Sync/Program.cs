using FinancesHub.Application;
using FinancesHub.Application.Sync;
using FinancesHub.Infrastructure;

// Pulls balances and transactions from the banks through Enable Banking, saves them and exits.
// In Azure it runs as a Container Apps Job on a schedule: banks allow only a few background requests a day
var builder = Host.CreateApplicationBuilder(args);

builder.AddServiceDefaults();
builder.AddInfrastructure();
builder.Services.AddApplication();

// Checked at startup: a missing registration fails the run right away instead of halfway through a sync
builder.ConfigureContainer(new DefaultServiceProviderFactory(new ServiceProviderOptions
{
    ValidateOnBuild = true,
    ValidateScopes = true
}));

using var host = builder.Build();

// Started so the OpenTelemetry exporters run, and stopped at the end so they flush before the process exits
await host.StartAsync();

SyncResult result;
await using (var scope = host.Services.CreateAsyncScope())
{
    result = await scope.ServiceProvider.GetRequiredService<SyncBanks>().RunAsync(CancellationToken.None);
}

host.Services.GetRequiredService<ILogger<Program>>().LogInformation(
    "Sync finished: {Synced} accounts synced, {Failed} failed, {Skipped} connections skipped",
    result.SyncedAccounts, result.FailedAccounts, result.SkippedConnections);

await host.StopAsync();

// A failed account makes the job run fail, so it shows up in Azure instead of looking fine
return result.FailedAccounts > 0 ? 1 : 0;
