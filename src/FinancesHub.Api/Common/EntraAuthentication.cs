using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;

namespace FinancesHub.Api.Common;

/// <summary>The "Authentication" configuration section: identifiers, not secrets.</summary>
internal sealed class EntraOptions
{
    public const string SectionName = "Authentication";

    public string Instance { get; init; } = "https://login.microsoftonline.com/";

    [Required]
    public string? TenantId { get; init; }

    /// <summary>The API's app registration (client) ID: the <c>aud</c> of v2 access tokens.</summary>
    [Required]
    public string? ClientId { get; init; }

    /// <summary>The owner's object ID in the tenant (<c>oid</c>): the only person whose tokens are accepted.</summary>
    [Required]
    public string? OwnerObjectId { get; init; }

    /// <summary>The delegated scope the app requests to call the API.</summary>
    public string Scope { get; init; } = "access_as_user";

    public string Authority => $"{Instance.TrimEnd('/')}/{TenantId}/v2.0";
}

internal static class EntraAuthentication
{
    /// <summary>
    /// Requires a Microsoft Entra ID access token for the API, with its scope and signed in as the owner, on every
    /// endpoint that doesn't opt out with <c>AllowAnonymous</c> (health checks, the bank's callback). Without the
    /// "Authentication" section the API stays open, but only in Development: anywhere else it refuses to start,
    /// so a missing setting can never publish the owner's bank data.
    /// </summary>
    public static WebApplicationBuilder AddEntraAuthentication(this WebApplicationBuilder builder)
    {
        var section = builder.Configuration.GetSection(EntraOptions.SectionName);
        if (!section.Exists())
        {
            if (!builder.Environment.IsDevelopment())
            {
                throw new InvalidOperationException(
                    $"The '{EntraOptions.SectionName}' configuration section is required outside Development.");
            }

            // No schemes and no fallback policy: every endpoint is open, as local development has always been
            builder.Services.AddAuthentication();
            builder.Services.AddAuthorization();
            return builder;
        }

        var entra = section.Get<EntraOptions>()!;
        Validator.ValidateObject(entra, new ValidationContext(entra), validateAllProperties: true);

        builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
            .AddJwtBearer(options =>
            {
                // Signing keys come from {Authority}/.well-known/openid-configuration and are cached and rotated
                options.Authority = entra.Authority;
                options.TokenValidationParameters.ValidIssuer = entra.Authority;
                options.TokenValidationParameters.ValidAudience = entra.ClientId;

                // Keep the token's claim names (oid, scp) instead of the long WS-Federation URIs
                options.MapInboundClaims = false;
                options.TokenValidationParameters.NameClaimType = "name";

                // Why a token was rejected goes in WWW-Authenticate only while developing: in production it would
                // help an attacker tune a forged token. The logs always have it
                options.IncludeErrorDetails = builder.Environment.IsDevelopment();
            });

        // A valid token isn't enough: it must carry the API's scope and belong to the owner. Anyone else signed in
        // to the tenant gets a 403
        var ownerWithScope = new AuthorizationPolicyBuilder(JwtBearerDefaults.AuthenticationScheme)
            .RequireAuthenticatedUser()
            .RequireAssertion(context => HasScope(context.User, entra.Scope))
            .RequireClaim("oid", entra.OwnerObjectId!)
            .Build();

        builder.Services.AddAuthorizationBuilder()
            .SetDefaultPolicy(ownerWithScope)
            // Endpoints with no authorization metadata at all: secure by default
            .SetFallbackPolicy(ownerWithScope);

        return builder;
    }

    // scp is a space-separated list, e.g. "openid access_as_user"
    private static bool HasScope(ClaimsPrincipal user, string scope) =>
        user.FindFirst("scp")?.Value.Split(' ', StringSplitOptions.RemoveEmptyEntries).Contains(scope) ?? false;
}
