import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_providers.dart';
import '../features/accounts/presentation/bank_screen.dart';
import '../features/connections/data/connections.dart';
import '../features/connections/presentation/connections_providers.dart';
import '../features/connections/presentation/connections_screen.dart';
import '../features/sign_in/presentation/sign_in_screen.dart';
import '../features/statistics/presentation/statistics_screen.dart';
import '../features/summary/presentation/summary_providers.dart';
import '../features/summary/presentation/summary_screen.dart';
import '../features/transactions/presentation/transactions_screen.dart';
import 'shell.dart';

const signInPath = '/sign-in';
const connectionResultPath = '/connections/result';

/// The scheme of the deep link the API sends the browser back to after a bank login (docs/api.md → "Link a bank").
const appScheme = 'financeshub';

final routerProvider = Provider<GoRouter>((ref) {
  // The router lives as long as the app; it re-checks its redirect whenever the auth status changes
  final status = ValueNotifier(ref.read(authProvider));
  ref.listen(authProvider, (_, next) => status.value = next);
  ref.onDispose(status.dispose);

  final router = GoRouter(
    refreshListenable: status,
    // The browser is back from a bank login. Only the deep link itself counts, not the app route it becomes, so a
    // router refresh on that route doesn't show the result again
    onEnter: (context, current, next, router) => isConnectionResult(next.uri)
        ? Allow(
            then: () {
              ref.read(linkOutcomeProvider.notifier).show(LinkOutcome.fromQuery(next.uri.queryParameters));
              ref.invalidate(connectionsProvider);
              ref.invalidate(summaryProvider);
            },
          )
        : const Allow(),
    redirect: (context, state) => redirectFor(status.value, state.uri),
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const SummaryScreen(),
                routes: [
                  GoRoute(path: 'connections', builder: (context, state) => const ConnectionsScreen()),
                  GoRoute(
                    path: 'connections/result',
                    builder: (context, state) => const ConnectionsScreen(showLinkOutcome: true),
                  ),
                  GoRoute(
                    path: 'banks/:bankId',
                    builder: (context, state) => BankScreen(bankId: state.pathParameters['bankId']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/transactions', builder: (context, state) => const TransactionsScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/statistics', builder: (context, state) => const StatisticsScreen())],
          ),
        ],
      ),
      GoRoute(path: signInPath, builder: (context, state) => const SignInScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// The deep link as Android hands it over: `financeshub://connections/result?…`.
@visibleForTesting
bool isConnectionResult(Uri uri) => uri.scheme == appScheme && uri.host == 'connections' && uri.path == '/result';

/// Turns the deep link into an app route, shows nothing but the sign-in screen until the owner is signed in, and
/// never the sign-in screen after that.
@visibleForTesting
String? redirectFor(AsyncValue<AuthStatus> status, Uri uri) {
  // Android passes the whole deep link, and go_router would only match its path (`/result`)
  if (uri.scheme == appScheme) {
    return isConnectionResult(uri) ? connectionResultPath : '/';
  }

  final signedIn = status.value == AuthStatus.signedIn;
  if (!signedIn) {
    if (uri.path == signInPath) return null;
    // Keep where it was going, so a deep link that cold-starts the app is still shown after the session check
    return uri.path == '/' ? signInPath : Uri(path: signInPath, queryParameters: {'from': uri.toString()}).toString();
  }
  if (uri.path == signInPath) {
    final from = uri.queryParameters['from'];
    // Only an app route, never somewhere else
    return from != null && from.startsWith('/') && !from.startsWith('//') ? from : '/';
  }
  return null;
}
