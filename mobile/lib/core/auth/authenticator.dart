import 'package:msal_auth/msal_auth.dart';

import '../config.dart';

/// Signs the owner in with Microsoft Entra ID and gives access tokens for the API. Behind an interface so tests use
/// a fake instead of the platform plugin.
abstract interface class Authenticator {
  /// A valid access token, from the cache or refreshed without any UI; `null` when the user has to sign in.
  /// Other failures (no network, for example) throw.
  Future<String?> tokenSilently();

  /// Opens the Microsoft login in the browser. Returns `false` if the user closed it; throws [SignInException].
  Future<bool> signIn();

  Future<void> signOut();
}

class SignInException implements Exception {
  const SignInException(this.message);

  /// Already in Spanish, for the screen.
  final String message;

  @override
  String toString() => 'SignInException: $message';
}

/// [Authenticator] on MSAL for Android (`msal_auth`), in single account mode: there is only the owner.
class MsalAuthenticator implements Authenticator {
  MsalAuthenticator(this._config);

  final AuthConfig _config;
  Future<SingleAccountPca>? _pca;

  List<String> get _scopes => [_config.apiScope];

  // Created once, on first use: MSAL loads its config and cache from the platform
  Future<SingleAccountPca> get _app => _pca ??= SingleAccountPca.create(
    clientId: _config.clientId,
    androidConfig: AndroidConfig(configFilePath: 'assets/msal_config.json', redirectUri: _config.redirectUri),
  );

  @override
  Future<String?> tokenSilently() async {
    final app = await _app;
    try {
      // MSAL answers from its cache while the token is valid, and refreshes it a few minutes before it expires
      final result = await app.acquireTokenSilent(scopes: _scopes, authority: _config.authority);
      return result.accessToken;
    } on MsalNoCurrentAccountException {
      return null;
    } on MsalUiRequiredException {
      // The refresh token expired or was revoked
      return null;
    }
  }

  @override
  Future<bool> signIn() async {
    final app = await _app;
    try {
      await app.acquireToken(scopes: _scopes, authority: _config.authority, prompt: Prompt.selectAccount);
      return true;
    } on MsalUserCancelException {
      return false;
    } on MsalException catch (e) {
      throw SignInException('No se ha podido iniciar sesión (${e.message}).');
    }
  }

  @override
  Future<void> signOut() async {
    final app = await _app;
    try {
      await app.signOut();
    } on MsalNoCurrentAccountException {
      // Already signed out
    }
  }
}
