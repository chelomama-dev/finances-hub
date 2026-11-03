import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_providers.dart';
import '../features/accounts/presentation/bank_screen.dart';
import '../features/connections/presentation/connections_screen.dart';
import '../features/sign_in/presentation/sign_in_screen.dart';
import '../features/summary/presentation/summary_screen.dart';
import '../features/transactions/presentation/transactions_screen.dart';

const signInPath = '/sign-in';

final routerProvider = Provider<GoRouter>((ref) {
  // The router lives as long as the app; it re-checks its redirect whenever the auth status changes
  final status = ValueNotifier(ref.read(authProvider));
  ref.listen(authProvider, (_, next) => status.value = next);
  ref.onDispose(status.dispose);

  final router = GoRouter(
    refreshListenable: status,
    redirect: (context, state) => redirectFor(status.value, state.matchedLocation),
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SummaryScreen()),
      GoRoute(path: signInPath, builder: (context, state) => const SignInScreen()),
      GoRoute(
        path: '/banks/:bankId',
        builder: (context, state) => BankScreen(bankId: state.pathParameters['bankId']!),
      ),
      GoRoute(
        path: '/accounts/:accountId/transactions',
        builder: (context, state) => TransactionsScreen(
          accountId: state.pathParameters['accountId']!,
          accountName: state.uri.queryParameters['name'],
        ),
      ),
      GoRoute(path: '/connections', builder: (context, state) => const ConnectionsScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Nothing but the sign-in screen until the owner is signed in, and never the sign-in screen after that.
@visibleForTesting
String? redirectFor(AsyncValue<AuthStatus> status, String location) {
  final signedIn = status.value == AuthStatus.signedIn;
  if (!signedIn && location != signInPath) return signInPath;
  if (signedIn && location == signInPath) return '/';
  return null;
}
