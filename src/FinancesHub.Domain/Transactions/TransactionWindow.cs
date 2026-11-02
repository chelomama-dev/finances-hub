namespace FinancesHub.Domain.Transactions;

/// <summary>
/// Which transactions a sync re-reads and replaces (ADR 0001).
/// </summary>
public static class TransactionWindow
{
    /// <summary>How far before the last successful sync the window starts.</summary>
    public static readonly TimeSpan Overlap = TimeSpan.FromDays(10);

    /// <summary>
    /// First booking date of the window, or <c>null</c> for an account that was never synced: then the whole
    /// history the bank gives is loaded.
    /// </summary>
    public static DateOnly? StartFor(DateTimeOffset? lastSyncedAt) =>
        lastSyncedAt is { } last ? DateOnly.FromDateTime((last - Overlap).UtcDateTime) : null;
}
