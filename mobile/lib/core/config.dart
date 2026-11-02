import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Build-time configuration, from `--dart-define`. Nothing here is hard-coded per environment.
class AppConfig {
  const AppConfig({required this.apiBaseUrl, required this.demo});

  /// `--dart-define=API_BASE_URL=...`: from the Android emulator the local API is `http://10.0.2.2:5080`, from a
  /// phone over USB `http://localhost:5080` after `adb reverse tcp:5080 tcp:5080`.
  final String apiBaseUrl;

  /// `--dart-define=DEMO=true`: in-memory made-up data, no API needed.
  final bool demo;

  static const fromEnvironment = AppConfig(
    apiBaseUrl: String.fromEnvironment('API_BASE_URL'),
    demo: bool.fromEnvironment('DEMO'),
  );

  bool get isValid => demo || apiBaseUrl.isNotEmpty;
}

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.fromEnvironment);
