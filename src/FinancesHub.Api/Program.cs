using FinancesHub.Infrastructure;
using Microsoft.AspNetCore.HttpOverrides;

var builder = WebApplication.CreateBuilder(args);

builder.AddServiceDefaults();
builder.AddInfrastructure();

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

builder.Services.AddOpenApi();

var app = builder.Build();

// First, so everything after it sees the original scheme and client IP
app.UseForwardedHeaders();

app.UseExceptionHandler();

app.MapDefaultEndpoints();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();

    // In Azure the ingress already redirects HTTP to HTTPS, and the container has no HTTPS port to redirect to
    app.UseHttpsRedirection();
}

await app.RunAsync();
