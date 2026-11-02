using System.Buffers.Text;
using System.Globalization;
using System.Text;

namespace FinancesHub.Application.Queries;

/// <summary>
/// Where a page of transactions ended: the last transaction's booking date and ID. Pages are read by key
/// (newest date first, then by ID) instead of by offset, so new transactions arriving between two pages don't
/// shift the next one. Opaque to the app.
/// </summary>
public sealed record TransactionCursor(DateOnly BookingDate, Guid Id)
{
    public string Encode() =>
        Base64Url.EncodeToString(Encoding.UTF8.GetBytes($"{BookingDate:yyyy-MM-dd}|{Id:N}"));

    public static bool TryParse(string? value, out TransactionCursor? cursor)
    {
        cursor = null;
        if (string.IsNullOrEmpty(value))
            return false;

        try
        {
            var parts = Encoding.UTF8.GetString(Base64Url.DecodeFromChars(value)).Split('|');
            if (parts.Length == 2
                && DateOnly.TryParseExact(parts[0], "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var date)
                && Guid.TryParseExact(parts[1], "N", out var id))
            {
                cursor = new TransactionCursor(date, id);
                return true;
            }
        }
        catch (FormatException)
        {
        }

        return false;
    }
}
