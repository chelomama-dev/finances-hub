import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/accounts/presentation/bank_screen.dart';
import '../features/connections/presentation/connections_screen.dart';
import '../features/summary/presentation/summary_screen.dart';
import '../features/transactions/presentation/transactions_screen.dart';

final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SummaryScreen()),
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
  ),
);
