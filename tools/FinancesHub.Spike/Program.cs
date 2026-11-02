using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using FinancesHub.Infrastructure.EnableBanking;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

// Spike: real calls to Enable Banking. Every response is saved as-is in .spike/ (ignored by git: it holds real bank
// data) so we can see what each bank sends before modelling the domain. Run from the repo root:
//
//   dotnet run --project tools/FinancesHub.Spike -- aspsps ES rural      banks in a country, filtered by name
//   dotnet run --project tools/FinancesHub.Spike -- auth ES "Bank name"  start linking: prints the bank's login URL
//   dotnet run --project tools/FinancesHub.Spike -- session <code>       the "code" from the redirect URL
//   dotnet run --project tools/FinancesHub.Spike -- account <uid>        details, balances and all transactions
//
// Banks allow few background requests a day, so don't run "account" in a loop.

var builder = Host.CreateApplicationBuilder();
builder.Configuration.AddUserSecrets<Program>();
builder.Services.AddEnableBankingHttpClient(builder.Configuration);
builder.Logging.SetMinimumLevel(LogLevel.Warning);

using var host = builder.Build();
await host.StartAsync();

var http = host.Services.GetRequiredService<IHttpClientFactory>().CreateClient(EnableBankingServiceCollectionExtensions.HttpClientName);
var options = host.Services.GetRequiredService<IOptions<EnableBankingOptions>>().Value;
var outputDir = Directory.CreateDirectory(".spike").FullName;

return args switch
{
    ["aspsps", var country, ..] => await ListAspsps(country, args.ElementAtOrDefault(2)),
    ["auth", var country, var name] => await StartAuth(country, name),
    ["session", var code] => await CreateSession(code),
    ["account", var uid] => await ReadAccount(uid),
    _ => Usage()
};

async Task<int> ListAspsps(string country, string? filter)
{
    var json = await Get($"/aspsps?country={country}&service=AIS", $"aspsps-{country}");
    foreach (var aspsp in json["aspsps"]!.AsArray())
    {
        var name = (string)aspsp!["name"]!;
        if (filter is null || name.Contains(filter, StringComparison.OrdinalIgnoreCase))
        {
            var days = (long?)aspsp["maximum_consent_validity"] / 86400;
            Console.WriteLine($"{name} ({aspsp["country"]}): consent up to {days} days, psu_types {aspsp["psu_types"]?.ToJsonString()}");
        }
    }
    return 0;
}

async Task<int> StartAuth(string country, string name)
{
    if (options.RedirectUrl is null)
    {
        Console.Error.WriteLine("Set EnableBanking:RedirectUrl in user secrets first.");
        return 1;
    }

    // The consent can last as long as the bank allows: ask for the maximum, minus a margin for clock skew
    var aspsps = await Get($"/aspsps?country={country}&service=AIS", $"aspsps-{country}");
    var aspsp = aspsps["aspsps"]!.AsArray().FirstOrDefault(a => (string)a!["name"]! == name);
    if (aspsp is null)
    {
        Console.Error.WriteLine($"No bank named \"{name}\" in {country}. Use the exact name from the aspsps command.");
        return 1;
    }
    var maxSeconds = (long?)aspsp["maximum_consent_validity"] ?? (long)TimeSpan.FromDays(90).TotalSeconds;
    var validUntil = DateTimeOffset.UtcNow.AddSeconds(maxSeconds).AddMinutes(-10);

    var json = await Post("/auth", new
    {
        access = new { valid_until = validUntil.ToString("yyyy-MM-ddTHH:mm:ss.fffzzz") },
        aspsp = new { name, country },
        state = Guid.NewGuid().ToString(),
        redirect_url = options.RedirectUrl,
        psu_type = "personal"
    }, $"auth-{Slug(name)}");

    Console.WriteLine($"Consent valid until {validUntil:yyyy-MM-dd}. Open this URL, log in to the bank, and copy");
    Console.WriteLine("the \"code\" query parameter from the address you land on (the page itself may not load):");
    Console.WriteLine();
    Console.WriteLine(json["url"]);
    return 0;
}

async Task<int> CreateSession(string code)
{
    var json = await Post("/sessions", new { code }, "session");
    var sessionId = (string)json["session_id"]!;
    File.Move(Path.Combine(outputDir, "session.json"), Path.Combine(outputDir, $"session-{sessionId}.json"), overwrite: true);

    Console.WriteLine($"Session {sessionId}, valid until {json["access"]?["valid_until"]}");
    foreach (var account in json["accounts"]!.AsArray())
    {
        Console.WriteLine($"  uid {account!["uid"]}: {account["name"]} {account["account_id"]?["iban"]} {account["currency"]} {account["cash_account_type"]}");
    }
    return 0;
}

async Task<int> ReadAccount(string uid)
{
    await Get($"/accounts/{uid}/details", $"account-{uid}-details");

    var balances = await Get($"/accounts/{uid}/balances", $"account-{uid}-balances");
    foreach (var balance in balances["balances"]!.AsArray())
    {
        Console.WriteLine($"Balance {balance!["balance_type"]}: {balance["balance_amount"]?["amount"]} {balance["balance_amount"]?["currency"]} ({balance["name"]})");
    }

    // "longest" asks the bank for as much history as it gives. Pages are followed with continuation_key, with a cap
    // so a bank that keeps returning keys can't burn the day's requests
    const int maxPages = 30;
    var total = 0;
    string? continuationKey = null;
    for (var page = 1; page <= maxPages; page++)
    {
        var url = $"/accounts/{uid}/transactions?strategy=longest"
            + (continuationKey is null ? "" : $"&continuation_key={Uri.EscapeDataString(continuationKey)}");
        var json = await Get(url, $"account-{uid}-transactions-{page:D2}");

        var count = json["transactions"]?.AsArray().Count ?? 0;
        total += count;
        Console.WriteLine($"Transactions page {page}: {count}");

        continuationKey = (string?)json["continuation_key"];
        if (continuationKey is null)
        {
            break;
        }
    }

    Console.WriteLine($"{total} transactions{(continuationKey is null ? "" : $" (stopped after {maxPages} pages, more available)")}. Raw JSON in {outputDir}");
    return 0;
}

async Task<JsonNode> Get(string path, string fileName) => await Save(await http.GetAsync(path), fileName);

async Task<JsonNode> Post(string path, object body, string fileName) => await Save(await http.PostAsJsonAsync(path, body), fileName);

async Task<JsonNode> Save(HttpResponseMessage response, string fileName)
{
    var body = await response.Content.ReadAsStringAsync();
    if (!response.IsSuccessStatusCode)
    {
        throw new HttpRequestException($"{(int)response.StatusCode} {response.RequestMessage?.RequestUri?.PathAndQuery}: {body}");
    }

    var json = JsonNode.Parse(body)!;
    await File.WriteAllTextAsync(Path.Combine(outputDir, $"{fileName}.json"),
        json.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
    return json;
}

static string Slug(string value) => string.Concat(value.Where(char.IsLetterOrDigit)).ToLowerInvariant();

static int Usage()
{
    Console.Error.WriteLine("Usage: aspsps <country> [filter] | auth <country> <bank name> | session <code> | account <uid>");
    return 1;
}
