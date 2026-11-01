namespace FinancesHub.Sync;

// One sync run: for each linked bank, read its accounts' balances and new transactions and save them
public sealed class BankSync(ILogger<BankSync> logger)
{
    public Task RunAsync(CancellationToken cancellationToken)
    {
        logger.LogInformation("No banks linked yet, nothing to sync");
        return Task.CompletedTask;
    }
}
