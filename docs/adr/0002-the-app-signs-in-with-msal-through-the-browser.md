# ADR 0002: The app signs in with MSAL, through the browser

- Status: accepted
- Date: 2026-11-03

## Context

Outside local development the API needs a Microsoft Entra ID access token for its `access_as_user` scope, issued to
the owner (#16). The Android app has to get that token, keep the owner signed in for weeks
without asking again, and refresh it on its own.

The owner is a personal Microsoft account invited to the tenant (`#EXT#`), and the API's registration is single
tenant. A login against `organizations` or `common` does not issue tokens for it; it has to be against the tenant.

## Decision

- **A public client registration of its own**, *Finances Hub Android*, single tenant, with no secret (a phone can't
  keep one). It has the API's delegated scope, consented once for the tenant, so the login never shows a consent
  screen. `infra/scripts/bootstrap-entra-app.sh` creates it.
- **MSAL for Android through `msal_auth`**, the maintained Flutter plugin over Microsoft's native library, in single
  account mode. MSAL keeps the tokens in its encrypted cache and refreshes them silently; the app never stores a
  token itself. Every request asks MSAL for one (`acquireTokenSilent`), which answers from the cache while it is
  valid.
- **The login opens in the browser** (a Custom Tab), not in a WebView and not through the Authenticator app: a
  WebView can't use the browser's Microsoft session or passkeys, and the broker adds an app to install and another
  redirect URI for little gain with a single user.
- **The authority is the tenant** (`login.microsoftonline.com/<tenant ID>`), passed on every call.
- **The IDs come from `--dart-define`**, written by the bootstrap script to `mobile/config/azure.json`, which git
  ignores, like the rest of the Azure IDs. Without them (local API, demo, CI) the app has no login at all.
- **The redirect URI depends on the signing key** (`msauth://<package>/<signature hash>`). Debug and release builds
  have different keys, so the config carries both hashes; the app picks one by build mode and Gradle puts the same
  one in the manifest, both from the same `--dart-define` values.

## Consequences

- A new signing key (the release keystore, or a new machine's debug key) means running the bootstrap script again;
  until then, Entra ID refuses to send the login back to the app.
- If the refresh token expires or is revoked, the next request finds no token and the app goes back to the sign-in
  screen. A failure to refresh for any other reason (no network) shows as a failed request with "Reintentar", not as
  a sign-out.
- Tests use a fake `Authenticator`; the MSAL path itself is only checked on a device.
