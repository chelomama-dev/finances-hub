using FinancesHub.Domain.Connections;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FinancesHub.Infrastructure.Persistence.Configurations;

internal sealed class LinkRequestConfiguration : IEntityTypeConfiguration<LinkRequest>
{
    public void Configure(EntityTypeBuilder<LinkRequest> builder)
    {
        builder.ToTable("LinkRequests");

        builder.HasKey(r => r.Id);
        builder.Property(r => r.Id).ValueGeneratedNever();

        builder.Property(r => r.BankCode).HasMaxLength(50).IsUnicode(false).IsRequired();
        builder.Ignore(r => r.Bank);

        // A renewal whose connection is removed has nothing left to renew
        builder.HasOne<Connection>()
            .WithMany()
            .HasForeignKey(r => r.ConnectionId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
