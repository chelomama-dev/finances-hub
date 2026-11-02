namespace FinancesHub.Infrastructure.EnableBanking;

// Bound from the "EnableBanking" configuration section. Locally the values come from user secrets; in Azure the
// private key comes from Key Vault
public sealed class EnableBankingOptions
{
    public const string SectionName = "EnableBanking";

    public Uri BaseUrl { get; set; } = new("https://api.enablebanking.com");

    // The application ID from the Enable Banking control panel. It goes in the JWT's "kid" header
    public string ApplicationId { get; set; } = "";

    // The application's RSA private key in PEM format, either inline (Key Vault) or as a path to a .pem file (local)
    public string? PrivateKey { get; set; }

    public string? PrivateKeyPath { get; set; }

    // Where the bank sends the browser back after the login, with "code" and "state" in the query string.
    // Must be one of the redirect URLs registered for the application
    public Uri? RedirectUrl { get; set; }
}
