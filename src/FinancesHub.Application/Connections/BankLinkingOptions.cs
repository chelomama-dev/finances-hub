namespace FinancesHub.Application.Connections;

/// <summary>Bound from the "BankLinking" configuration section.</summary>
public sealed class BankLinkingOptions
{
    public const string SectionName = "BankLinking";

    /// <summary>
    /// IBANs that may be stored, separated by commas. Empty means every account the owner shares. A second line of
    /// defence after the bank's own consent screen: an account outside the list is never saved, even if it is
    /// shared again on a reconnection. It holds personal data, so it lives in user secrets, not in the repo.
    /// </summary>
    public string? AllowedIbans { get; set; }

    internal IReadOnlySet<string> AllowedIbanSet =>
        (AllowedIbans ?? "")
        .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
        .Select(i => string.Concat(i.Where(c => !char.IsWhiteSpace(c))).ToUpperInvariant())
        .ToHashSet();
}
