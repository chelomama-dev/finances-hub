using System.Net;
using System.Text;

namespace FinancesHub.Infrastructure.Tests.EnableBanking;

// Answers each request with the next queued response and records what was sent
internal sealed class FakeHttpHandler : HttpMessageHandler
{
    private readonly Queue<(HttpStatusCode Status, string Body)> _responses = new();

    public List<(HttpMethod Method, string PathAndQuery, string? Body)> Requests { get; } = [];

    public FakeHttpHandler Respond(string json, HttpStatusCode status = HttpStatusCode.OK)
    {
        _responses.Enqueue((status, json));
        return this;
    }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var body = request.Content is null ? null : await request.Content.ReadAsStringAsync(cancellationToken);
        Requests.Add((request.Method, request.RequestUri!.PathAndQuery, body));

        var (status, json) = _responses.Count > 0 ? _responses.Dequeue() : throw new InvalidOperationException($"No response queued for {request.RequestUri}");
        return new HttpResponseMessage(status)
        {
            RequestMessage = request,
            Content = new StringContent(json, Encoding.UTF8, "application/json")
        };
    }
}
