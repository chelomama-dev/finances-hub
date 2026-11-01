var builder = DistributedApplication.CreateBuilder(args);

var sql = builder.AddSqlServer("sql", port: 14331)
    .WithLifetime(ContainerLifetime.Persistent)
    .WithDataVolume();

var db = sql.AddDatabase("financesdb");

builder.AddProject<Projects.FinancesHub_Api>("api")
    .WithReference(db)
    .WaitFor(db);

// Pulls balances and transactions from the banks once and exits, like the Container Apps Job it becomes in Azure.
// To run it again, restart it from the dashboard
builder.AddProject<Projects.FinancesHub_Sync>("sync")
    .WithReference(db)
    .WaitFor(db);

builder.Build().Run();
