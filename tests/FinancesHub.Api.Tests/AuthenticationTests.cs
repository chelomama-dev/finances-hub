using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;

namespace FinancesHub.Api.Tests;

// The API configured as in Azure, trusting a key only the tests know instead of the tenant's public keys. Issuer,
// audience, lifetime, scope and owner are validated with the real configuration
public sealed class AuthenticatedApiFactory : ApiFactory
{
    public const string TenantId = "11111111-1111-1111-1111-111111111111";
    public const string ClientId = "22222222-2222-2222-2222-222222222222";
    public const string OwnerObjectId = "33333333-3333-3333-3333-333333333333";
    public const string Issuer = $"https://login.microsoftonline.com/{TenantId}/v2.0";

    public static readonly SecurityKey SigningKey = new RsaSecurityKey(RSA.Create(2048)) { KeyId = "financeshub-tests" };

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        base.ConfigureWebHost(builder);
        builder.UseSetting("Authentication:TenantId", TenantId);
        builder.UseSetting("Authentication:ClientId", ClientId);
        builder.UseSetting("Authentication:OwnerObjectId", OwnerObjectId);
        // Only the keys change: no network call to the tenant's metadata
        builder.ConfigureTestServices(services =>
            services.PostConfigure<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme, options =>
            {
                var configuration = new OpenIdConnectConfiguration { Issuer = Issuer };
                configuration.SigningKeys.Add(SigningKey);
                options.ConfigurationManager = new StaticConfigurationManager<OpenIdConnectConfiguration>(configuration);
            }));
    }
}

public sealed class AuthenticationTests(AuthenticatedApiFactory factory) : IClassFixture<AuthenticatedApiFactory>
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task The_owner_with_the_scope_gets_in()
    {
        Assert.Equal(HttpStatusCode.OK, (await GetSummaryAsync(Token())).StatusCode);
    }

    [Fact]
    public async Task No_token_is_401()
    {
        Assert.Equal(HttpStatusCode.Unauthorized, (await GetSummaryAsync(null)).StatusCode);
    }

    [Fact]
    public async Task Someone_else_in_the_tenant_is_403()
    {
        Assert.Equal(HttpStatusCode.Forbidden, (await GetSummaryAsync(Token(objectId: Guid.NewGuid().ToString()))).StatusCode);
    }

    [Fact]
    public async Task A_token_without_the_scope_is_403()
    {
        Assert.Equal(HttpStatusCode.Forbidden, (await GetSummaryAsync(Token(scope: "openid profile"))).StatusCode);
    }

    [Theory]
    [InlineData("issuer")]
    [InlineData("audience")]
    [InlineData("expired")]
    [InlineData("key")]
    public async Task A_token_that_is_not_valid_is_401(string broken)
    {
        var token = broken switch
        {
            "issuer" => Token(issuer: "https://login.microsoftonline.com/another-tenant/v2.0"),
            "audience" => Token(audience: "another-api"),
            "expired" => Token(expires: DateTime.UtcNow.AddMinutes(-10)),
            _ => Token(key: new RsaSecurityKey(RSA.Create(2048)) { KeyId = "untrusted" })
        };

        Assert.Equal(HttpStatusCode.Unauthorized, (await GetSummaryAsync(token)).StatusCode);
    }

    [Theory]
    [InlineData("/alive")]
    [InlineData("/api/connections/callback?error=access_denied")]
    public async Task The_health_check_and_the_banks_callback_need_no_token(string path)
    {
        var client = factory.CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });

        var response = await client.GetAsync(path, Ct);

        Assert.NotEqual(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.NotEqual(HttpStatusCode.Forbidden, response.StatusCode);
    }

    private async Task<HttpResponseMessage> GetSummaryAsync(string? token)
    {
        var client = factory.CreateClient();
        if (token is not null)
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return await client.GetAsync("/api/summary", Ct);
    }

    private static string Token(
        string? objectId = null, string scope = "access_as_user", string issuer = AuthenticatedApiFactory.Issuer,
        string audience = AuthenticatedApiFactory.ClientId, DateTime? expires = null, SecurityKey? key = null)
    {
        var expiry = expires ?? DateTime.UtcNow.AddHours(1);
        return new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
        {
            Issuer = issuer,
            Audience = audience,
            Claims = new Dictionary<string, object>
            {
                ["oid"] = objectId ?? AuthenticatedApiFactory.OwnerObjectId,
                ["scp"] = scope,
                ["name"] = "Test Owner"
            },
            IssuedAt = expiry.AddHours(-1),
            NotBefore = expiry.AddHours(-1),
            Expires = expiry,
            SigningCredentials = new SigningCredentials(key ?? AuthenticatedApiFactory.SigningKey, SecurityAlgorithms.RsaSha256)
        });
    }
}

public sealed class StartupWithoutAuthenticationTests
{
    [Fact]
    public void Outside_development_the_API_refuses_to_start_without_authentication()
    {
        using var factory = new WebApplicationFactory<Program>().WithWebHostBuilder(b => b.UseEnvironment("Production"));

        var error = Assert.ThrowsAny<Exception>(() => factory.CreateClient());

        Assert.Contains("'Authentication' configuration section is required", error.ToString());
    }
}
