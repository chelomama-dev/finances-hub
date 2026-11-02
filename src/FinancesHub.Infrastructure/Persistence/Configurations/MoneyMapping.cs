using FinancesHub.Domain.Common;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FinancesHub.Infrastructure.Persistence.Configurations;

internal static class MoneyMapping
{
    // 4 decimals: amounts in euros have 2, but a bank sending more must not be rounded silently
    public static void Map(ComplexPropertyBuilder<Money> money, string prefix)
    {
        money.Property(m => m.Amount).HasColumnName($"{prefix}Amount").HasPrecision(19, 4);
        money.Property(m => m.Currency).HasColumnName($"{prefix}Currency").HasMaxLength(3).IsUnicode(false).IsFixedLength();
    }
}
