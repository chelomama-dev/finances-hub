# Finances Hub, Android app

The Flutter app of [Finances Hub](../README.md). It reads the API described in [docs/api.md](../docs/api.md);
the conventions it follows are in [CLAUDE.md](../CLAUDE.md#flutter-app).

## Run it

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # JSON code (*.g.dart, not committed)

# Made-up data, no API needed
flutter run --dart-define=DEMO=true

# The local API (`aspire run` from the repo root), from the emulator
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5080

# The local API, from a phone over USB
adb reverse tcp:5080 tcp:5080
flutter run --dart-define=API_BASE_URL=http://localhost:5080
```

Plain HTTP is allowed only in debug builds, and only to `10.0.2.2` and `localhost`.

### Against the API in Azure

The API in Azure needs a Microsoft sign-in. Once, from the repo root, with `az` logged in as a tenant admin:

```bash
infra/scripts/bootstrap-entra-app.sh   # the app's registration in Entra ID, and config/azure.json
```

Then, from `mobile/`:

```bash
flutter run --dart-define-from-file=config/azure.json
```

`config/azure.json` has the tenant, the client IDs and the signature hashes of the keys that sign the app
([config/azure.example.json](config/azure.example.json) shows its shape). Git ignores it. If the signing key changes
(a new machine, the release key), run the script again: Entra ID only sends the login back to a registered key.

## Check it

```bash
flutter analyze
flutter test
```
