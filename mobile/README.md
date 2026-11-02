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

## Check it

```bash
flutter analyze
flutter test
```
