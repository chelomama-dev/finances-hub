# CLAUDE.md

Instructions for working on this repo. What the project is and why is in [README.md](README.md); the HTTP contract
between the backend and the app is in [docs/api.md](docs/api.md), and the decisions behind the design are in
[docs/adr/](docs/adr/).

Claude Code works on the whole project: the .NET backend, the Flutter app, tests, CI/CD and Azure. The owner decides
the scope and reviews.

## Rules

- **The contract comes first.** An endpoint or field changes in `docs/api.md` before it changes in the API or the
  app, and the app never uses anything the contract doesn't describe.
- Before something is done, it must build and its tests must pass, in both the backend and the app.
- Never commit secrets: no keys, tokens, connection strings or real bank data. Fixtures and demo data are made up.
  The spike's raw responses stay in `.spike/`, ignored by git.
- The app is **read-only**: nothing in the backend or the app ever starts a payment or moves money.
- Don't add dependencies without a reason. Say which one you are adding and why.
- Code, comments, commits and docs are in **English**. The app's UI text is in **Spanish**.

### Git

Nothing is committed straight to `main`: every change goes in a branch and reaches `main` through a pull request,
squash merged.

- Branch prefixes: `feat/`, `fix/`, `chore/`, `docs/`, `refactor/`. Lowercase, hyphens, short
  (`feat/transactions-endpoint`, `feat/mobile-summary-screen`).
- Commit messages in English, in the imperative, starting with a capital letter and no prefixes
  (`Add the transactions endpoint`, not `feat: added endpoint`). If the why isn't obvious, explain it in the body.
  One logical change per commit.
- **Claude Code runs the whole git flow**: push, pull request, squash merge once the build, the tests and the CI
  checks are green, and then a clean local copy (`main` up to date, merged branches deleted, `git fetch --prune`).
  If something fails or is unclear, it stops and tells the owner before merging.
- Never force-push to `main` or rewrite its history.

## Repository layout

```
src/                           .NET backend
  FinancesHub.Domain/          accounts, balances, transactions
  FinancesHub.Application/     use cases
  FinancesHub.Infrastructure/  EF Core, Enable Banking client
  FinancesHub.Api/             HTTP API for the app
  FinancesHub.Sync/            pulls balances and transactions from the banks, then exits
  FinancesHub.AppHost/         Aspire orchestration for local dev
  FinancesHub.ServiceDefaults/ OpenTelemetry, health checks, resilience
tests/                         backend tests
infra/                         Bicep
.github/workflows/             CI/CD
docs/api.md                    HTTP contract between the API and the app
docs/adr/                      architecture decision records
mobile/                        Flutter app
```

## Backend

- Light Clean Architecture: `Domain` has no dependencies; `Application` depends on `Domain`; `Infrastructure`
  implements `Application`'s interfaces; `Api` and `Sync` are hosts and only wire things together.
- Minimal APIs grouped by feature, errors as ProblemDetails, OpenAPI document at `/openapi/v1.json` in Development.
- Package versions are locked (`packages.lock.json`): restore with `dotnet restore --locked-mode` in CI.
- Run everything locally with `aspire run` from the repo root (SQL Server in Docker, API and sync).
- Build and test: `dotnet build` and `dotnet test` from the repo root.

## Flutter app

### Stack

- Flutter, latest stable, Android only. Package name `dev.chelomama.financeshub`, app name "Finances Hub".
- State: **Riverpod** (`flutter_riverpod`). Navigation: **go_router**. HTTP: **dio**. JSON:
  **json_serializable** + `build_runner`. Number and date formatting: **intl** with the `es_ES` locale.
- Material 3, light and dark theme that follow the system.

### Folder structure (feature first)

```
mobile/
  lib/
    main.dart                  reads the config, starts ProviderScope and the app
    app/
      app.dart                 MaterialApp.router, theme, locale
      router.dart              go_router routes
      theme.dart
    core/
      config.dart              API base URL and demo flag (from --dart-define)
      auth/                    MSAL behind an Authenticator interface, and the signed in / out status
      api/
        api_client.dart        dio instance: base URL, timeouts, auth header, ProblemDetails -> ApiException
        api_exception.dart
      money.dart               parse decimal strings, format as "1.234,56 €"
      widgets/                 shared widgets (empty state, error with retry, loading)
    features/
      summary/                 home: total balance and one card per bank
        data/                  DTOs (json_serializable) and repository calling the API
        presentation/          screens, widgets and Riverpod providers
      accounts/                a bank's accounts with their balances
      transactions/            an account's transactions, filters, infinite scroll
      connections/             linked banks, consent status, link and reconnect
      sign_in/                 the Microsoft sign-in screen
  test/                        mirrors lib/
```

Each feature keeps the same two folders: `data/` (DTOs and the repository that talks to the API) and
`presentation/` (widgets and providers). Screens never call dio directly; they read providers, providers call
repositories.

### Screens

All texts in Spanish. Every screen has loading, empty and error (with "Reintentar") states, and pull to refresh.

0. **Iniciar sesión** (`/sign-in`): only when the build has Entra ID config. Every route goes here until the owner
   is signed in; "Cerrar sesión" is in Inicio's app bar.

1. **Inicio** (`/`): `GET /api/summary`. Total balance large at the top, a card per bank with its balance, and
   "Actualizado hace X" from `lastSyncedAt`. If a connection is `expiring` or `expired`, a banner that goes to
   Conexiones.
2. **Banco** (`/banks/:bankId`): `GET /api/banks/{bankId}/accounts`. The bank's accounts with name, masked IBAN and
   balance.
3. **Movimientos** (`/accounts/:accountId/transactions`): `GET /api/accounts/{accountId}/transactions`. Newest
   first, grouped by day, income in green and expenses in the normal text colour. Filters: date range and
   Todos / Ingresos / Gastos. Loads the next page with `cursor` when scrolling to the end. A transaction with no
   description shows "Sin descripción" (Trade Republic sends only amount, currency and date).
4. **Conexiones** (`/connections`): `GET /api/connections`. Each bank with its status and expiry date, a
   "Reconectar" button when `expiring` or `expired`, and "Vincular banco". The linking flow is in
   [docs/api.md](docs/api.md#link-a-bank).

### Rules for the app

- **Money is never a `double`.** Amounts come as decimal strings (`"-23.40"`); parse them with the `decimal`
  package and format them with `intl`. Show the currency the API sends.
- Dates: `bookingDate` is a date with no time (`2026-11-01`); timestamps are UTC ISO 8601, show them in local time.
- Configuration comes from `--dart-define`, never hard-coded:
  - `API_BASE_URL`: from the Android emulator, the local API is `http://10.0.2.2:5080`.
  - `DEMO=true`: the app uses in-memory fake repositories with made-up data shaped exactly like the examples in
    [docs/api.md](docs/api.md). This lets the app run before the backend has each endpoint, and in demos.
- Android blocks plain HTTP by default: allow it **only in debug** (a debug-only network security config for
  `10.0.2.2` and `localhost`), never in release.
- Auth: the local API has no auth. Against Azure the app signs in with Microsoft Entra ID through **msal_auth**
  ([ADR 0002](docs/adr/0002-the-app-signs-in-with-msal-through-the-browser.md)): `core/auth/` has the
  `Authenticator` and the auth status, and `api_client.dart` is the single place that adds
  `Authorization: Bearer <token>`. The Entra ID values come from `--dart-define-from-file=config/azure.json`, which
  `infra/scripts/bootstrap-entra-app.sh` writes and git ignores; without them there is no login.
- Releases: a tag `vX.Y.Z` on `main` that matches `pubspec.yaml` publishes the **demo** APK, signed with the release
  key ([ADR 0003](docs/adr/0003-public-releases-are-demo-builds.md)). The build against Azure is never published.
- Tests: unit tests for `money.dart`, the DTO parsing (with the JSON from docs/api.md), the repositories and the
  auth status (with a fake `Authenticator`); widget tests for the states (loading, empty, error, data) of each
  screen.
- Commands, from `mobile/`: `flutter pub get`, `dart run build_runner build --delete-conflicting-outputs`,
  `flutter analyze`, `flutter test`, `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5080`, and against Azure
  `flutter run --dart-define-from-file=config/azure.json`.
