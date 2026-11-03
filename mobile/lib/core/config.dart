import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Build-time configuration, from `--dart-define` (or `--dart-define-from-file=config/azure.json`). Nothing here is
/// hard-coded per environment.
class AppConfig {
  const AppConfig({required this.apiBaseUrl, required this.demo, this.auth});

  /// `--dart-define=API_BASE_URL=...`: from the Android emulator the local API is `http://10.0.2.2:5080`, from a
  /// phone over USB `http://localhost:5080` after `adb reverse tcp:5080 tcp:5080`.
  final String apiBaseUrl;

  /// `--dart-define=DEMO=true`: in-memory made-up data, no API needed.
  final bool demo;

  /// Sign in with Microsoft Entra ID; `null` for the local API, which has no auth. Ignored in demo mode.
  final AuthConfig? auth;

  static final fromEnvironment = AppConfig(
    apiBaseUrl: const String.fromEnvironment('API_BASE_URL'),
    demo: const bool.fromEnvironment('DEMO'),
    auth: AuthConfig.fromEnvironment(),
  );

  bool get isValid => demo || (apiBaseUrl.isNotEmpty && (auth?.isValid ?? true));
}

/// The Entra ID values `infra/scripts/bootstrap-entra-app.sh` writes to `config/azure.json`.
class AuthConfig {
  const AuthConfig({required this.tenantId, required this.clientId, required this.apiScope, required this.signatureHash});

  final String tenantId;

  /// The *Finances Hub Android* app registration.
  final String clientId;

  /// `api://<API client ID>/access_as_user`.
  final String apiScope;

  /// Base64 SHA-1 of the key that signs this build: Entra ID only sends the login back to a registered one.
  final String signatureHash;

  /// Signs in against the tenant itself, not `organizations`: the owner is a personal account invited to it.
  String get authority => 'https://login.microsoftonline.com/$tenantId';

  /// The hash goes URL-encoded here and as is in the manifest (android/app/build.gradle.kts).
  String get redirectUri => 'msauth://dev.chelomama.financeshub/${Uri.encodeComponent(signatureHash)}';

  /// `null` unless the client ID is set. Release builds take the release key's hash, debug and profile the debug
  /// key's, the same choice Gradle makes for the manifest.
  static AuthConfig? fromEnvironment() {
    const clientId = String.fromEnvironment('AUTH_CLIENT_ID');
    if (clientId.isEmpty) return null;
    return const AuthConfig(
      tenantId: String.fromEnvironment('AUTH_TENANT_ID'),
      clientId: clientId,
      apiScope: String.fromEnvironment('AUTH_API_SCOPE'),
      signatureHash: kReleaseMode
          ? String.fromEnvironment('AUTH_RELEASE_SIGNATURE_HASH')
          : String.fromEnvironment('AUTH_DEBUG_SIGNATURE_HASH'),
    );
  }

  bool get isValid => tenantId.isNotEmpty && apiScope.isNotEmpty && signatureHash.isNotEmpty;
}

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.fromEnvironment);
