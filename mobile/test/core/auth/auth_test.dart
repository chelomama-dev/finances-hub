import 'package:finances_hub/app/router.dart';
import 'package:finances_hub/core/api/api_client.dart';
import 'package:finances_hub/core/api/api_exception.dart';
import 'package:finances_hub/core/auth/auth_providers.dart';
import 'package:finances_hub/core/auth/authenticator.dart';
import 'package:finances_hub/core/config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import 'fake_authenticator.dart';

ProviderContainer containerWith(FakeAuthenticator? authenticator) {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test', demo: false)),
      authenticatorProvider.overrideWithValue(authenticator),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('config', () {
    test('the redirect URI carries the signature hash URL-encoded', () {
      const auth = AuthConfig(tenantId: 't', clientId: 'c', apiScope: 's', signatureHash: 'ab+c/d=');

      expect(auth.redirectUri, 'msauth://dev.chelomama.financeshub/ab%2Bc%2Fd%3D');
      expect(auth.authority, 'https://login.microsoftonline.com/t');
    });

    test('auth needs every value, not only the client ID', () {
      const missingScope = AuthConfig(tenantId: 't', clientId: 'c', apiScope: '', signatureHash: 'h');

      expect(const AppConfig(apiBaseUrl: 'https://api', demo: false, auth: missingScope).isValid, isFalse);
      expect(const AppConfig(apiBaseUrl: 'https://api', demo: false).isValid, isTrue);
    });
  });

  group('status', () {
    test('without auth the app is always signed in', () {
      expect(containerWith(null).read(authProvider).value, AuthStatus.signedIn);
    });

    test('signed in when there is a token in the cache', () async {
      final container = containerWith(FakeAuthenticator(token: 'cached'));

      expect(await container.read(authProvider.future), AuthStatus.signedIn);
    });

    test('signed out when there is none', () async {
      final container = containerWith(FakeAuthenticator());

      expect(await container.read(authProvider.future), AuthStatus.signedOut);
    });

    test('signing in, cancelling it and signing out', () async {
      final authenticator = FakeAuthenticator()..onSignIn = () async => false;
      final container = containerWith(authenticator);
      await container.read(authProvider.future);

      await container.read(authProvider.notifier).signIn();
      expect(container.read(authProvider).value, AuthStatus.signedOut);

      authenticator.onSignIn = () async => true;
      await container.read(authProvider.notifier).signIn();
      expect(container.read(authProvider).value, AuthStatus.signedIn);

      await container.read(authProvider.notifier).signOut();
      expect(container.read(authProvider).value, AuthStatus.signedOut);
      expect(authenticator.signOutCalls, 1);
    });

    test('a failed sign-in keeps its message for the screen', () async {
      final authenticator = FakeAuthenticator()..onSignIn = () async => throw const SignInException('Ha fallado.');
      final container = containerWith(authenticator);
      await container.read(authProvider.future);

      await container.read(authProvider.notifier).signIn();

      expect(container.read(authProvider).error, isA<SignInException>());
    });
  });

  group('requests', () {
    Future<(FakeAdapter, ProviderContainer)> apiWith(FakeAuthenticator authenticator) async {
      final container = containerWith(authenticator);
      await container.read(authProvider.future);
      final adapter = FakeAdapter((_) => (200, {'ok': true}));
      container.read(dioProvider).httpClientAdapter = adapter;
      return (adapter, container);
    }

    test('carry the token as a bearer token', () async {
      final (adapter, container) = await apiWith(FakeAuthenticator(token: 'abc'));

      await container.read(apiClientProvider).get('/api/summary');

      expect(adapter.requests.single.headers['Authorization'], 'Bearer abc');
    });

    test('without a token, the session is over', () async {
      final authenticator = FakeAuthenticator(token: 'abc');
      final (_, container) = await apiWith(authenticator);

      authenticator.token = null;
      await container.read(apiClientProvider).get('/api/summary');

      expect(container.read(authProvider).value, AuthStatus.signedOut);
    });

    test('a failure to refresh the token fails like a request with no connection', () async {
      final authenticator = FakeAuthenticator(token: 'abc');
      final (adapter, container) = await apiWith(authenticator);

      authenticator.tokenError = Exception('no network');

      await expectLater(
        container.read(apiClientProvider).get('/api/summary'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('conectar'))),
      );
      expect(adapter.requests, isEmpty);
      expect(container.read(authProvider).value, AuthStatus.signedIn);
    });
  });

  group('router', () {
    const signedIn = AsyncData(AuthStatus.signedIn);
    const signedOut = AsyncData(AuthStatus.signedOut);

    test('everything goes to the sign-in screen until signed in', () {
      expect(redirectFor(const AsyncLoading(), Uri.parse('/')), signInPath);
      expect(redirectFor(signedOut, Uri.parse(signInPath)), isNull);
    });

    test('a screen opened before signing in is kept and shown after', () {
      final toSignIn = redirectFor(signedOut, Uri.parse('/connections/result'))!;

      expect(toSignIn, '$signInPath?from=%2Fconnections%2Fresult');
      expect(redirectFor(signedIn, Uri.parse(toSignIn)), '/connections/result');
    });

    test('once signed in, the sign-in screen goes home, and never outside the app', () {
      expect(redirectFor(signedIn, Uri.parse(signInPath)), '/');
      expect(redirectFor(signedIn, Uri.parse('$signInPath?from=//evil.test')), '/');
      expect(redirectFor(signedIn, Uri.parse('/connections')), isNull);
    });

    test("the bank's deep link becomes the result route, and any other app link goes home", () {
      final deepLink = Uri.parse('financeshub://connections/result?status=success&synced=true');

      expect(isConnectionResult(deepLink), isTrue);
      expect(redirectFor(signedIn, deepLink), connectionResultPath);
      expect(redirectFor(signedIn, Uri.parse('financeshub://somewhere')), '/');
    });
  });
}
