using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FinancesHub.Infrastructure.EnableBanking;
using Microsoft.Extensions.Options;

namespace FinancesHub.Infrastructure.Tests.EnableBanking;

public sealed class EnableBankingTokenProviderTests : IDisposable
{
    private const string ApplicationId = "3b5e0c2a-app-id";

    private static readonly DateTimeOffset Now = new(2026, 11, 2, 10, 0, 0, TimeSpan.Zero);

    private readonly RSA _key = RSA.Create(2048);
    private readonly ManualTimeProvider _time = new(Now);

    [Fact]
    public void Token_has_the_header_and_claims_Enable_Banking_expects()
    {
        using var provider = CreateProvider(new EnableBankingOptions
        {
            ApplicationId = ApplicationId,
            PrivateKey = _key.ExportPkcs8PrivateKeyPem()
        });

        var (header, payload, _) = Decode(provider.GetToken());

        Assert.Equal("JWT", header.GetProperty("typ").GetString());
        Assert.Equal("RS256", header.GetProperty("alg").GetString());
        Assert.Equal(ApplicationId, header.GetProperty("kid").GetString());
        Assert.Equal("enablebanking.com", payload.GetProperty("iss").GetString());
        Assert.Equal("api.enablebanking.com", payload.GetProperty("aud").GetString());
        Assert.Equal(Now.ToUnixTimeSeconds(), payload.GetProperty("iat").GetInt64());
        Assert.Equal((Now + EnableBankingTokenProvider.Lifetime).ToUnixTimeSeconds(), payload.GetProperty("exp").GetInt64());
    }

    [Fact]
    public void Token_lifetime_is_within_the_24_hours_Enable_Banking_allows()
    {
        Assert.True(EnableBankingTokenProvider.Lifetime <= TimeSpan.FromHours(24));
    }

    [Fact]
    public void Token_is_signed_with_the_private_key()
    {
        using var provider = CreateProvider(new EnableBankingOptions
        {
            ApplicationId = ApplicationId,
            PrivateKey = _key.ExportPkcs8PrivateKeyPem()
        });

        var token = provider.GetToken();
        var signingInput = token[..token.LastIndexOf('.')];
        var (_, _, signature) = Decode(token);

        Assert.True(_key.VerifyData(Encoding.ASCII.GetBytes(signingInput), signature,
            HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1));
    }

    [Fact]
    public void Key_can_be_read_from_a_pem_file()
    {
        var path = Path.GetTempFileName();
        try
        {
            File.WriteAllText(path, _key.ExportRSAPrivateKeyPem());
            using var provider = CreateProvider(new EnableBankingOptions
            {
                ApplicationId = ApplicationId,
                PrivateKeyPath = path
            });

            Assert.NotEmpty(provider.GetToken());
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void Token_is_reused_until_it_is_about_to_expire()
    {
        using var provider = CreateProvider(new EnableBankingOptions
        {
            ApplicationId = ApplicationId,
            PrivateKey = _key.ExportPkcs8PrivateKeyPem()
        });

        var first = provider.GetToken();

        _time.UtcNow = Now + EnableBankingTokenProvider.Lifetime - EnableBankingTokenProvider.RenewBefore - TimeSpan.FromSeconds(1);
        Assert.Equal(first, provider.GetToken());

        _time.UtcNow = Now + EnableBankingTokenProvider.Lifetime - EnableBankingTokenProvider.RenewBefore;
        Assert.NotEqual(first, provider.GetToken());
    }

    private EnableBankingTokenProvider CreateProvider(EnableBankingOptions options) =>
        new(Options.Create(options), _time);

    private static (JsonElement Header, JsonElement Payload, byte[] Signature) Decode(string token)
    {
        var parts = token.Split('.');
        Assert.Equal(3, parts.Length);
        return (
            JsonDocument.Parse(Base64Url.DecodeFromChars(parts[0])).RootElement,
            JsonDocument.Parse(Base64Url.DecodeFromChars(parts[1])).RootElement,
            Base64Url.DecodeFromChars(parts[2]));
    }

    public void Dispose() => _key.Dispose();

    private sealed class ManualTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        public DateTimeOffset UtcNow { get; set; } = utcNow;

        public override DateTimeOffset GetUtcNow() => UtcNow;
    }
}
