using FinancesHub.Domain.Accounts;
using FinancesHub.Domain.Common;
using FinancesHub.Domain.Connections;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FinancesHub.Infrastructure.Persistence.Configurations;

internal sealed class AccountConfiguration : IEntityTypeConfiguration<Account>
{
    public void Configure(EntityTypeBuilder<Account> builder)
    {
        builder.ToTable("Accounts");

        builder.HasKey(a => a.Id);
        builder.Property(a => a.Id).ValueGeneratedNever();

        builder.Property(a => a.ProviderAccountId).HasMaxLength(100).IsUnicode(false).IsRequired();
        builder.Property(a => a.Iban)
            .HasConversion(iban => iban!.Value.Value, value => new Iban(value))
            .HasMaxLength(34)
            .IsUnicode(false);
        builder.Property(a => a.Name).HasMaxLength(Account.MaxNameLength);
        builder.Property(a => a.Currency).HasMaxLength(3).IsUnicode(false).IsFixedLength().IsRequired();

        // Null until the first sync
        builder.ComplexProperty<Money>(a => a.Balance, money => MoneyMapping.Map(money, "Balance"));

        // Restrict: removing a connection must not silently take its accounts and their history with it
        builder.HasOne<Connection>()
            .WithMany()
            .HasForeignKey(a => a.ConnectionId)
            .OnDelete(DeleteBehavior.Restrict);
    }
}
