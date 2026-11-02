var builder = DistributedApplication.CreateBuilder(args);

var sql = builder.AddSqlServer("sql", port: 14331)
    .WithLifetime(ContainerLifetime.Persistent)
    .WithDataVolume();

var db = sql.AddDatabase("financesdb");

// Enable Banking, from the AppHost's user secrets (Parameters:enablebanking-*). The private key stays a file outside
// the repo; only its path is passed
var enableBankingAppId = builder.AddParameter("enablebanking-application-id");
var enableBankingKeyPath = builder.AddParameter("enablebanking-private-key-path");
var enableBankingRedirectUrl = builder.AddParameter("enablebanking-redirect-url");

var api = builder.AddProject<Projects.FinancesHub_Api>("api")
    .WithReference(db)
    .WaitFor(db)
    .WithEnvironment("EnableBanking__ApplicationId", enableBankingAppId)
    .WithEnvironment("EnableBanking__PrivateKeyPath", enableBankingKeyPath)
    .WithEnvironment("EnableBanking__RedirectUrl", enableBankingRedirectUrl);

// Pulls balances and transactions from the banks once and exits, like the Container Apps Job it becomes in Azure.
// It waits for the API because the API applies the migrations in development. To run it again, restart it from
// the dashboard
builder.AddProject<Projects.FinancesHub_Sync>("sync")
    .WithReference(db)
    .WaitFor(api)
    .WithEnvironment("EnableBanking__ApplicationId", enableBankingAppId)
    .WithEnvironment("EnableBanking__PrivateKeyPath", enableBankingKeyPath);

builder.Build().Run();
