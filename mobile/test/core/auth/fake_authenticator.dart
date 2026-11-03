import 'package:finances_hub/core/auth/authenticator.dart';

/// An [Authenticator] that answers with whatever the test sets, and counts the calls.
class FakeAuthenticator implements Authenticator {
  FakeAuthenticator({this.token});

  String? token;
  Object? tokenError;
  Future<bool> Function()? onSignIn;
  var signInCalls = 0;
  var signOutCalls = 0;

  @override
  Future<String?> tokenSilently() async {
    if (tokenError != null) throw tokenError!;
    return token;
  }

  @override
  Future<bool> signIn() async {
    signInCalls++;
    final result = await (onSignIn ?? () async => true)();
    if (result) token = 'signed-in-token';
    return result;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    token = null;
  }
}
