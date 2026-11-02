using FinancesHub.Domain.Accounts;
using FinancesHub.Domain.Transactions;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FinancesHub.Infrastructure.Persistence.Configurations;

internal sealed class TransactionConfiguration : IEntityTypeConfiguration<Transaction>
{
    public void Configure(EntityTypeBuilder<Transaction> builder)
    {
        builder.ToTable("Transactions");

        builder.HasKey(t => t.Id);
        builder.Property(t => t.Id).ValueGeneratedNever();

        builder.ComplexProperty(t => t.Amount, money => MoneyMapping.Map(money, ""));
        builder.Property(t => t.Description).HasMaxLength(Transaction.MaxDescriptionLength);
        builder.Property(t => t.Counterparty).HasMaxLength(Transaction.MaxCounterpartyLength);
        builder.Property(t => t.Status).HasConversion<string>().HasMaxLength(20).IsUnicode(false);

        // Derived from the sign of the amount
        builder.Ignore(t => t.Direction);

        // Each sync deletes an account's transactions from a date (ADR 0001), and the app lists them newest first
        builder.HasIndex(t => new { t.AccountId, t.BookingDate });

        // The transactions are the account's history: they go with it
        builder.HasOne<Account>()
            .WithMany()
            .HasForeignKey(t => t.AccountId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
