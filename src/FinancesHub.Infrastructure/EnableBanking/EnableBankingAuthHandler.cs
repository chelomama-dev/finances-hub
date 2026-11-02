using System.Net.Http.Headers;

namespace FinancesHub.Infrastructure.EnableBanking;

// Adds the signed JWT to every request sent to Enable Banking
internal sealed class EnableBankingAuthHandler(EnableBankingTokenProvider tokenProvider) : DelegatingHandler
{
    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokenProvider.GetToken());
        return base.SendAsync(request, cancellationToken);
    }
}
