using FinancesHub.Domain.Common;

namespace FinancesHub.Domain.Transactions;

/// <summary>
/// A movement of an account, as the bank reported it. Transactions inside the sync window are replaced on every
/// sync (ADR 0001), so their IDs are not stable.
/// </summary>
public sealed class Transaction
{
    public const int MaxDescriptionLength = 500;
    public const int MaxCounterpartyLength = 200;

    public Guid Id { get; private set; }
    public Guid AccountId { get; private set; }
    public DateOnly BookingDate { get; private set; }
    public DateOnly? ValueDate { get; private set; }

    /// <summary>Signed: negative is an expense, positive is income.</summary>
    public Money Amount { get; private set; }

    /// <summary><c>null</c> when the bank sends none (Trade Republic never does).</summary>
    public string? Description { get; private set; }

    /// <summary>Who paid or was paid, when the bank says.</summary>
    public string? Counterparty { get; private set; }

    public TransactionStatus Status { get; private set; }

    public TransactionDirection Direction => Amount.Amount < 0 ? TransactionDirection.Expense : TransactionDirection.Income;

    private Transaction(Guid id, Guid accountId, DateOnly bookingDate, DateOnly? valueDate, Money amount,
        string? description, string? counterparty, TransactionStatus status)
    {
        Id = id;
        AccountId = accountId;
        BookingDate = bookingDate;
        ValueDate = valueDate;
        Amount = amount;
        Description = description;
        Counterparty = counterparty;
        Status = status;
    }

    public static Transaction Create(Guid accountId, DateOnly bookingDate, DateOnly? valueDate, Money amount,
        string? description, string? counterparty, TransactionStatus status)
    {
        if (accountId == Guid.Empty)
            throw new DomainException("The transaction must belong to an account.");

        return new Transaction(Guid.CreateVersion7(), accountId, bookingDate, valueDate, amount,
            Clean(description, MaxDescriptionLength), Clean(counterparty, MaxCounterpartyLength), status);
    }

    // Bank texts come padded and sometimes over-long; a long description is cut rather than rejected,
    // because losing a whole transaction over its text would be worse
    private static string? Clean(string? text, int maxLength)
    {
        if (string.IsNullOrWhiteSpace(text))
            return null;

        var collapsed = string.Join(' ', text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        return collapsed.Length <= maxLength ? collapsed : collapsed[..maxLength];
    }
}
