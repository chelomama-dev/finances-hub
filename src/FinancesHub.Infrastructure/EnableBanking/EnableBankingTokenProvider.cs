using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;

namespace FinancesHub.Infrastructure.EnableBanking;

// Signs the JWT that authenticates every call to Enable Banking: RS256, the application ID as "kid", and a lifetime
// of at most 24 hours (longer tokens are rejected). One token is reused until it is close to expiring
public sealed class EnableBankingTokenProvider : IDisposable
{
    internal static readonly TimeSpan Lifetime = TimeSpan.FromHours(1);

    // Renewed this long before it expires, so a token never runs out in the middle of a request
    internal static readonly TimeSpan RenewBefore = TimeSpan.FromMinutes(5);

    private readonly EnableBankingOptions _options;
    private readonly TimeProvider _timeProvider;
    private readonly Lazy<RSA> _key;
    private readonly Lock _lock = new();

    private string? _token;
    private DateTimeOffset _expiresAt;

    public EnableBankingTokenProvider(IOptions<EnableBankingOptions> options, TimeProvider timeProvider)
    {
        _options = options.Value;
        _timeProvider = timeProvider;
        _key = new Lazy<RSA>(LoadKey);
    }

    public string GetToken()
    {
        lock (_lock)
        {
            var now = _timeProvider.GetUtcNow();
            if (_token is null || now >= _expiresAt - RenewBefore)
            {
                _expiresAt = now + Lifetime;
                _token = CreateToken(now, _expiresAt);
            }

            return _token;
        }
    }

    private string CreateToken(DateTimeOffset issuedAt, DateTimeOffset expiresAt)
    {
        var header = JsonSerializer.SerializeToUtf8Bytes(new Dictionary<string, string>
        {
            ["typ"] = "JWT",
            ["alg"] = "RS256",
            ["kid"] = _options.ApplicationId
        });
        var payload = JsonSerializer.SerializeToUtf8Bytes(new Dictionary<string, object>
        {
            ["iss"] = "enablebanking.com",
            ["aud"] = "api.enablebanking.com",
            ["iat"] = issuedAt.ToUnixTimeSeconds(),
            ["exp"] = expiresAt.ToUnixTimeSeconds()
        });

        var signingInput = $"{Base64Url.EncodeToString(header)}.{Base64Url.EncodeToString(payload)}";
        var signature = _key.Value.SignData(
            Encoding.ASCII.GetBytes(signingInput), HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);

        return $"{signingInput}.{Base64Url.EncodeToString(signature)}";
    }

    private RSA LoadKey()
    {
        var pem = !string.IsNullOrWhiteSpace(_options.PrivateKey)
            ? _options.PrivateKey
            : File.ReadAllText(_options.PrivateKeyPath!);

        var rsa = RSA.Create();
        rsa.ImportFromPem(pem);
        return rsa;
    }

    public void Dispose()
    {
        if (_key.IsValueCreated)
        {
            _key.Value.Dispose();
        }
    }
}
