# ADR 0003: Public releases are demo builds, signed with a release key

- Status: accepted
- Date: 2026-11-03

## Context

Release builds were signed with the debug key, which is different on every machine and lives in `~/.android`. The
app needs a key of its own: Android only installs an update signed with the same key as the installed app, and
Entra ID only sends the login back to a signature hash it knows (ADR 0002).

The repository is public, so a GitHub release is too. An APK that talks to the API in Azure carries the tenant ID,
both client IDs and the API's URL, the values the repo keeps out of git. And it is useless to anyone else: only the
owner can sign in.

## Decision

- **One release key**, an RSA 4096 PKCS12 keystore outside the repo (`~/.android/financeshub-release.jks`), created by
  `infra/scripts/bootstrap-release-key.sh`. Gradle reads it through `mobile/android/key.properties`, which git
  ignores; without that file, release builds fall back to the debug key so `flutter run --release` keeps working.
- **The GitHub release carries the demo build** (`DEMO=true`): made-up data, no login, no API. Anyone can install it
  and try the app.
- **The owner's build is made locally**, with the same release key and `--dart-define-from-file=config/azure.json`.
  Same package and same key, so it installs over the demo build and updates in place.
- **A tag `vX.Y.Z` on `main` releases**, through `.github/workflows/release.yml`. The tag must match the version in
  `pubspec.yaml`, so the version code always grows. The workflow checks the APK's certificate before publishing it.
- **The key is in a `release` environment** whose secrets only tags `v*` can read, the same way the Azure identity
  only trusts the `production` environment.

## Consequences

- Losing the keystore means the app can't be updated: it has to be uninstalled (losing its sign-in) and installed
  again with a new key, and the Entra ID registration needs the new hash. The keystore and `key.properties` are
  backed up outside the machine.
- A release is a pull request that bumps `version` in `pubspec.yaml`, then a tag on the merge commit.
- The demo build and the owner's build can't be installed side by side; one replaces the other.
