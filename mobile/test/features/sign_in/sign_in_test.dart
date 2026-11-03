import 'dart:async';

import 'package:finances_hub/core/auth/auth_providers.dart';
import 'package:finances_hub/core/auth/authenticator.dart';
import 'package:finances_hub/features/sign_in/presentation/sign_in_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/auth/fake_authenticator.dart';
import '../../helpers.dart';

void main() {
  Future<FakeAuthenticator> pump(WidgetTester tester, FakeAuthenticator authenticator) async {
    await pumpScreen(tester, const SignInScreen(), overrides: [authenticatorProvider.overrideWithValue(authenticator)]);
    await tester.pumpAndSettle();
    return authenticator;
  }

  testWidgets('signed out: the Microsoft sign-in button', (tester) async {
    final authenticator = await pump(tester, FakeAuthenticator());

    await tester.tap(find.text('Iniciar sesión con Microsoft'));
    await tester.pumpAndSettle();

    expect(authenticator.signInCalls, 1);
  });

  testWidgets('loading while the sign-in is open', (tester) async {
    final pending = Completer<bool>();
    await pump(tester, FakeAuthenticator()..onSignIn = () => pending.future);

    await tester.tap(find.text('Iniciar sesión con Microsoft'));
    await tester.pump();

    expect(find.text('Iniciar sesión con Microsoft'), findsNothing);
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Iniciar sesión con Microsoft'), findsOneWidget);
  });

  testWidgets('a failed sign-in shows why and lets you try again', (tester) async {
    await pump(tester, FakeAuthenticator()..onSignIn = () async => throw const SignInException('Ha fallado.'));

    await tester.tap(find.text('Iniciar sesión con Microsoft'));
    await tester.pumpAndSettle();

    expect(find.text('Ha fallado.'), findsOneWidget);
    expect(find.text('Iniciar sesión con Microsoft'), findsOneWidget);
  });

  testWidgets('if the session could not be checked, Reintentar checks it again', (tester) async {
    final authenticator = await pump(tester, FakeAuthenticator()..tokenError = Exception('no network'));

    expect(find.textContaining('Comprueba la conexión'), findsOneWidget);

    authenticator.tokenError = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Comprueba la conexión'), findsNothing);
  });
}
