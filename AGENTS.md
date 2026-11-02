# AGENTS.md

Instructions for the AI agents working on this repo. Read this whole file before making changes. What the project is
and why is in [README.md](README.md); the HTTP contract between backend and app is in [docs/api.md](docs/api.md).

## Who does what

Two agents work here, each in its own area. The human owner decides scope, reviews and merges.

| Agent | Owns | Must not touch |
|---|---|---|
| **Claude Code** (backend) | `src/`, `tests/`, `infra/`, `.github/`, `docs/api.md`, root build files (`*.slnx`, `Directory.Build.props`, `global.json`, `dotnet-tools.json`) | `mobile/` (except CI needs, agreed with the owner) |
| **Antigravity** (frontend) | `mobile/` (the Flutter app) | Everything outside `mobile/` |

Shared files (`AGENTS.md`, `README.md`, `.gitignore`): either agent may propose a change, and the owner approves it.

### Claude Code: backend, testing, CI/CD and Azure

- .NET 10 backend: domain, use cases, EF Core, the Enable Banking client, the API and the sync job.
- Backend tests (unit and integration).
- Keeps [docs/api.md](docs/api.md) in sync with the real API. **The contract changes there first, then the code.**
- GitHub Actions: backend build and tests, container images to GHCR, deployment to Azure, and the CI job that runs
  `flutter analyze`, `flutter test` and builds the APK as a GitHub release.
- Infrastructure as code (Bicep) and Azure: Container Apps, Azure SQL, Key Vault, Entra ID, Application Insights.

### Antigravity: the Flutter app

- Everything in `mobile/`: screens, navigation, state, the API client, theme, tests.
- Consumes the API exactly as [docs/api.md](docs/api.md) describes it. **Never invents endpoints or fields.** If the
  app needs something the contract doesn't have, stop and tell the owner what is missing and why; the backend
  agent adds it to the contract and the API.
- Keeps `flutter analyze` with no issues and `flutter test` green, because CI runs both.

## Rules for both agents

- Stay in your area. If a task needs a change on the other side, say so instead of doing it.
- Before you consider something done, it must build and its tests must pass.
- Never commit secrets: no keys, tokens, connection strings or real bank data. Fixtures and demo data are made up.
- The app is **read-only**: nothing in the backend or the app ever starts a payment or moves money.
- Don't add dependencies without a reason. Say which one you are adding and why.
- Code, comments, commits and docs are in **English**. The app's UI text is in **Spanish**.

### Git

- One branch per task, prefixed by area: `backend/...`, `mobile/...`, `ci/...`, `infra/...`, `docs/...`. Pull request to `main`.
- Commit messages: a short sentence in the imperative, no prefixes (`Add the transactions endpoint`, not
  `feat: added endpoint`). One logical change per commit.
- Never push, merge or force-push unless the owner asks.

## Repository layout

```
src/                           .NET backend (Claude Code)
  FinancesHub.Domain/          accounts, balances, transactions
  FinancesHub.Application/     use cases
  FinancesHub.Infrastructure/  EF Core, Enable Banking client
  FinancesHub.Api/             HTTP API for the app
  FinancesHub.Sync/            pulls balances and transactions from the banks, then exits
  FinancesHub.AppHost/         Aspire orchestration for local dev
  FinancesHub.ServiceDefaults/ OpenTelemetry, health checks, resilience
tests/                         backend tests (Claude Code)
infra/                         Bicep (Claude Code)
.github/workflows/             CI/CD (Claude Code)
docs/api.md                    HTTP contract between API and app (Claude Code writes it, Antigravity follows it)
mobile/                        Flutter app (Antigravity)
```

## Backend (Claude Code)

- Light Clean Architecture: `Domain` has no dependencies; `Application` depends on `Domain`; `Infrastructure`
  implements `Application`'s interfaces; `Api` and `Sync` are hosts and only wire things together.
- Minimal APIs grouped by feature, errors as ProblemDetails, OpenAPI document at `/openapi/v1.json` in Development.
- Package versions are locked (`packages.lock.json`): restore with `dotnet restore --locked-mode` in CI.
- Run everything locally with `aspire run` from the repo root (SQL Server in Docker, API and sync).
- Build and test: `dotnet build` and `dotnet test` from the repo root.

## Frontend (Antigravity)

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
  test/                        mirrors lib/
```

Each feature keeps the same two folders: `data/` (DTOs and the repository that talks to the API) and
`presentation/` (widgets and providers). Screens never call dio directly; they read providers, providers call
repositories.

### Screens

All texts in Spanish. Every screen has loading, empty and error (with "Reintentar") states, and pull to refresh.

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
- Auth: in local development the API has no auth. Later it will use Microsoft Entra ID; leave a single place in
  `api_client.dart` that adds `Authorization: Bearer <token>` from a `TokenProvider` that returns `null` for now.
  The MSAL integration is decided when we get there.
- Tests: unit tests for `money.dart`, the DTO parsing (with the JSON from docs/api.md) and the repositories; widget
  tests for the states (loading, empty, error, data) of each screen.
- Commands, from `mobile/`: `flutter pub get`, `dart run build_runner build --delete-conflicting-outputs`,
  `flutter analyze`, `flutter test`, `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5080`.
