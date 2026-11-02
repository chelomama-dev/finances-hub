namespace FinancesHub.Application.Abstractions;

/// <summary>
/// Commits the changes tracked by the repositories.
/// </summary>
public interface IUnitOfWork
{
    Task SaveChangesAsync(CancellationToken cancellationToken);

    /// <summary>
    /// Runs <paramref name="work"/> and saves its changes in one database transaction: either everything is
    /// committed or nothing is. It may run more than once if the database connection fails transiently, so the
    /// work must be safe to repeat.
    /// </summary>
    Task ExecuteInTransactionAsync(Func<CancellationToken, Task> work, CancellationToken cancellationToken);
}
