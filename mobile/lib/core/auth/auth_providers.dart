import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import 'authenticator.dart';

/// MSAL when the build has Entra ID config; `null` for the local API and demo mode, which have no auth.
final authenticatorProvider = Provider<Authenticator?>((ref) {
  final config = ref.watch(appConfigProvider);
  final auth = config.auth;
  return config.demo || auth == null ? null : MsalAuthenticator(auth);
});

enum AuthStatus { signedIn, signedOut }

/// Whether the owner is signed in. The router sends every screen to the sign-in screen until this is
/// [AuthStatus.signedIn].
final authProvider = AsyncNotifierProvider<AuthNotifier, AuthStatus>(AuthNotifier.new);

class AuthNotifier extends AsyncNotifier<AuthStatus> {
  Authenticator? get _authenticator => ref.read(authenticatorProvider);

  @override
  FutureOr<AuthStatus> build() {
    final authenticator = ref.watch(authenticatorProvider);
    // Synchronous without auth, so the app opens straight on its first screen
    if (authenticator == null) return AuthStatus.signedIn;
    return _statusFrom(authenticator.tokenSilently());
  }

  Future<void> signIn() async {
    final authenticator = _authenticator!;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () async => await authenticator.signIn() ? AuthStatus.signedIn : AuthStatus.signedOut,
    );
  }

  Future<void> signOut() async {
    await _authenticator!.signOut();
    state = const AsyncData(AuthStatus.signedOut);
  }

  /// A request found no token it could use without UI: the session is over.
  void sessionExpired() {
    if (state.value == AuthStatus.signedIn) state = const AsyncData(AuthStatus.signedOut);
  }

  static Future<AuthStatus> _statusFrom(Future<String?> token) async =>
      await token == null ? AuthStatus.signedOut : AuthStatus.signedIn;
}
