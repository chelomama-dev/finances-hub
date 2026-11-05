import 'package:finances_hub/app/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('the bottom bar switches between the sections', (tester) async {
    final router = GoRouter(
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [GoRoute(path: '/', builder: (_, _) => const Text('home'))],
            ),
            StatefulShellBranch(
              routes: [GoRoute(path: '/transactions', builder: (_, _) => const Text('transactions'))],
            ),
            StatefulShellBranch(
              routes: [GoRoute(path: '/statistics', builder: (_, _) => const Text('statistics'))],
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(find.text('home'), findsOneWidget);

    await tester.tap(find.text('Movimientos'));
    await tester.pumpAndSettle();

    expect(find.text('transactions'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/transactions');

    await tester.tap(find.text('Estadísticas'));
    await tester.pumpAndSettle();

    expect(find.text('statistics'), findsOneWidget);
  });
}
