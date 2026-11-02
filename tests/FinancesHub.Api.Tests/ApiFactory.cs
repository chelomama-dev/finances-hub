using System.Security.Cryptography;
using FinancesHub.Application.Banking;
using FinancesHub.Domain.Banks;
using FinancesHub.Domain.Common;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Testcontainers.MsSql;

namespace FinancesHub.Api.Tests;

// The real API (Development, so it applies the migrations) against SQL Server in a container, with the banks faked
public sealed class ApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly MsSqlContainer _sql = new MsSqlBuilder("mcr.microsoft.com/mssql/server:2022-latest").Build();
    private readonly RSA _key = RSA.Create(2048);

    public FakeBanking Banking { get; } = new();

    public async ValueTask InitializeAsync() => await _sql.StartAsync();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
        builder.UseSetting("ConnectionStrings:financesdb", _sql.GetConnectionString());
        builder.UseSetting("EnableBanking:ApplicationId", "test");
        builder.UseSetting("EnableBanking:PrivateKey", _key.ExportPkcs8PrivateKeyPem());
        builder.ConfigureServices(services =>
        {
            services.RemoveAll<IBankingProvider>();
            services.AddSingleton<IBankingProvider>(Banking);
        });
    }

    public override async ValueTask DisposeAsync()
    {
        await base.DisposeAsync();
        await _sql.DisposeAsync();
        _key.Dispose();
    }
}

public sealed class FakeBanking : IBankingProvider
{
    public BankSession? NextSession { get; set; }

    public Task<BankAuthorization> StartAuthorizationAsync(Bank bank, string state, CancellationToken cancellationToken) =>
        Task.FromResult(new BankAuthorization(new Uri($"https://bank.example/login?state={state}"), DateTimeOffset.MaxValue));

    public Task<BankSession> CreateSessionAsync(string code, CancellationToken cancellationToken) =>
        Task.FromResult(NextSession ?? throw new BankingProviderException("Invalid code.", 422));

    public Task<bool> IsSessionAuthorizedAsync(string sessionId, CancellationToken cancellationToken) => Task.FromResult(true);

    public Task<Money> GetBalanceAsync(string providerAccountId, CancellationToken cancellationToken) =>
        Task.FromResult(new Money(100m, "EUR"));

    public Task<IReadOnlyList<BankTransaction>> GetTransactionsAsync(string providerAccountId, DateOnly? from, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<BankTransaction>>([]);
}

[CollectionDefinition(nameof(ApiCollection))]
public sealed class ApiCollection : ICollectionFixture<ApiFactory>;
