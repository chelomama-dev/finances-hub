using System.Globalization;
using FinancesHub.Application.Banking;
using FinancesHub.Domain.Accounts;
using FinancesHub.Domain.Common;
using FinancesHub.Domain.Transactions;
using FinancesHub.Infrastructure.EnableBanking.Api;

namespace FinancesHub.Infrastructure.EnableBanking;

// Turns what each bank sends through Enable Banking into the same shapes for every bank
internal static class EnableBankingMapper
{
    // Most useful first: what can be spent now, then what is booked. Trade Republic sends its available balance
    // as OTHR, so OTHR comes before the rest
    private static readonly string[] BalancePreference = ["CLAV", "ITAV", "OTHR", "CLBD", "ITBD", "XPCD", "OPAV", "OPBD"];

    public static BankAccount ToAccount(AccountDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.Uid))
            throw new BankingProviderException("Enable Banking returned an account without uid.");

        return new BankAccount(dto.Uid, ToIban(dto.AccountId?.Iban), dto.Name,
            dto.Currency ?? throw new BankingProviderException($"Account {dto.Uid} has no currency."));
    }

    public static Money ToBalance(IReadOnlyList<BalanceDto> balances)
    {
        var best = balances
            .Where(b => b.BalanceAmount?.Amount is not null)
            .OrderBy(b => Array.IndexOf(BalancePreference, b.BalanceType) is var i and >= 0 ? i : int.MaxValue)
            .FirstOrDefault()
            ?? throw new BankingProviderException("The bank returned no balance.");

        return ToMoney(best.BalanceAmount!);
    }

    /// <summary><c>null</c> for statuses that are not money moving (cancelled, rejected, scheduled).</summary>
    public static BankTransaction? ToTransaction(TransactionDto dto)
    {
        TransactionStatus? status = dto.Status switch
        {
            "BOOK" or "OTHR" or null => TransactionStatus.Booked,
            "PDNG" or "HOLD" => TransactionStatus.Pending,
            _ => null // CNCL, RJCT, SCHD
        };
        if (status is null)
            return null;

        var bookingDate = dto.BookingDate ?? dto.ValueDate ?? dto.TransactionDate
            ?? throw new BankingProviderException("The bank returned a transaction without any date.");

        var amount = ToMoney(dto.TransactionAmount ?? throw new BankingProviderException("The bank returned a transaction without amount."));

        // The sign comes from the indicator: Caja Rural sends every amount positive, Trade Republic sends debits
        // negative. Only when there is no indicator is the bank's sign kept
        var signed = dto.CreditDebitIndicator switch
        {
            "DBIT" => new Money(-Math.Abs(amount.Amount), amount.Currency),
            "CRDT" => new Money(Math.Abs(amount.Amount), amount.Currency),
            _ => amount
        };

        var description = dto.RemittanceInformation is { Count: > 0 } lines ? string.Join(' ', lines) : null;

        // The other party: who was paid for a debit, who paid for a credit
        var counterparty = signed.Amount < 0 ? dto.Creditor?.Name : dto.Debtor?.Name;

        return new BankTransaction(bookingDate, dto.ValueDate, signed, description, counterparty, status.Value);
    }

    private static Money ToMoney(AmountDto dto)
    {
        if (!decimal.TryParse(dto.Amount, NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint,
                CultureInfo.InvariantCulture, out var amount))
            throw new BankingProviderException($"\"{dto.Amount}\" is not a valid amount.");

        try
        {
            return new Money(amount, dto.Currency!);
        }
        catch (DomainException e)
        {
            throw new BankingProviderException(e.Message, inner: e);
        }
    }

    // An IBAN that doesn't parse is dropped rather than failing the whole session: the uid is what we read with
    private static Iban? ToIban(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
            return null;

        try
        {
            return new Iban(value);
        }
        catch (DomainException)
        {
            return null;
        }
    }
}
