using FinancesHub.Domain.Connections;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FinancesHub.Infrastructure.Persistence.Configurations;

internal sealed class ConnectionConfiguration : IEntityTypeConfiguration<Connection>
{
    public void Configure(EntityTypeBuilder<Connection> builder)
    {
        builder.ToTable("Connections");

        // The domain generates the Id (GUID v7), never the database
        builder.HasKey(c => c.Id);
        builder.Property(c => c.Id).ValueGeneratedNever();

        builder.Property(c => c.BankCode).HasMaxLength(50).IsUnicode(false).IsRequired();
        builder.Property(c => c.SessionId).HasMaxLength(100).IsUnicode(false).IsRequired();

        // Derived from BankCode
        builder.Ignore(c => c.Bank);
    }
}
