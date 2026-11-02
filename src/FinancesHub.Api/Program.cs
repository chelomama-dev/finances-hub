using FinancesHub.Api.Connections;
using FinancesHub.Api.Finances;
using FinancesHub.Application;
using FinancesHub.Infrastructure;
using FinancesHub.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.HttpOverrides;

var builder = WebApplication.CreateBuilder(args);

builder.AddServiceDefaults();
builder.AddInfrastructure();
builder.Services.AddApplication(builder.Configuration);

builder.Services.AddProblemDetails();
// .NET 10: validates DataAnnotations on endpoint parameters and returns a 400 ValidationProblem
builder.Services.AddValidation();

// In Azure, TLS terminates at the Container Apps ingress, which forwards plain HTTP plus X-Forwarded-* headers.
// Without this the app would think every request is HTTP and log the ingress IP instead of the client's.
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    options.KnownIPNetworks.Clear();
    options.KnownProxies.Clear();
});

builder.Services.Configure<AppLinkOptions>(builder.Configuration.GetSection(AppLinkOptions.SectionName));

builder.Services.AddOpenApi();

var app = builder.Build();

// First, so everything after it sees the original scheme and client IP
app.UseForwardedHeaders();

app.UseExceptionHandler();

app.MapDefaultEndpoints();
app.MapConnections();
app.MapFinances();

if (app.Environment.IsDevelopment())
{
    // Locally the database is brought up to date on startup. In Azure, the pipeline applies the migrations
    await using (var scope = app.Services.CreateAsyncScope())
    {
        await scope.ServiceProvider.GetRequiredService<FinancesDbContext>().Database.MigrateAsync();
    }

    app.MapOpenApi();
}

// No HTTPS redirection: in Azure the ingress already redirects HTTP to HTTPS, and locally the Android app talks
// plain HTTP to port 5080 (the emulator or a phone don't trust the development certificate)

await app.RunAsync();

// For the API tests (WebApplicationFactory)
public partial class Program;
