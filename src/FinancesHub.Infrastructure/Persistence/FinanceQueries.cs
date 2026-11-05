using FinancesHub.Application.Queries;
using FinancesHub.Domain.Transactions;
using Microsoft.EntityFrameworkCore;

namespace FinancesHub.Infrastructure.Persistence;

internal sealed class FinanceQueries(FinancesDbContext db) : IFinanceQueries
{
    public async Task<IReadOnlyList<AccountView>> ListAccountsAsync(string? bankCode, CancellationToken cancellationToken)
    {
        var query =
            from account in db.Accounts.AsNoTracking()
            join connection in db.Connections.AsNoTracking() on account.ConnectionId equals connection.Id
            where bankCode == null || connection.BankCode == bankCode
            orderby connection.CreatedAt, account.Name
            select new AccountView(account.Id, connection.BankCode, account.Name, account.Iban, account.Currency, account.Balance, account.LastSyncedAt);

        return await query.ToListAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<TransactionView>> ListTransactionsAsync(
        TransactionFilter filter, TransactionCursor? after, int limit, CancellationToken cancellationToken)
    {
        var query = db.Transactions.AsNoTracking();

        if (filter.From is { } from)
            query = query.Where(t => t.BookingDate >= from);
        if (filter.To is { } to)
            query = query.Where(t => t.BookingDate <= to);
        query = filter.Direction switch
        {
            TransactionDirection.Income => query.Where(t => t.Amount.Amount >= 0),
            TransactionDirection.Expense => query.Where(t => t.Amount.Amount < 0),
            _ => query
        };

        // Keyset: everything strictly after the last row of the previous page, in the same order as below
        if (after is not null)
            query = query.Where(t => t.BookingDate < after.BookingDate
                                     || (t.BookingDate == after.BookingDate && t.Id.CompareTo(after.Id) > 0));

        var page =
            from transaction in query
            join account in db.Accounts on transaction.AccountId equals account.Id
            join connection in db.Connections on account.ConnectionId equals connection.Id
            orderby transaction.BookingDate descending, transaction.Id
            select new TransactionView(transaction.Id, connection.BankCode, transaction.BookingDate, transaction.Amount,
                transaction.Description, transaction.Counterparty, transaction.Status);

        return await page.Take(limit + 1).ToListAsync(cancellationToken);
    }
}
