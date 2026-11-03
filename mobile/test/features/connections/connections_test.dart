import 'dart:async';

import 'package:finances_hub/app/app.dart';
import 'package:finances_hub/core/api/api_exception.dart';
import 'package:finances_hub/core/config.dart';
import 'package:finances_hub/core/connection_status.dart';
import 'package:finances_hub/features/connections/data/connections.dart';
import 'package:finances_hub/features/connections/data/connections_repository.dart';
import 'package:finances_hub/features/connections/presentation/connections_providers.dart';
import 'package:finances_hub/features/connections/presentation/connections_screen.dart';
import 'package:finances_hub/features/summary/data/summary.dart';
import 'package:finances_hub/features/summary/data/summary_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../helpers.dart';
import '../summary/summary_test.dart' as summary_test;

// The example of docs/api.md → "List connections", plus an expired one
const example = {
  'items': [
    {
      'id': 'a5d3f8e1-9b2c-4e7a-8f60-4c1b7d9e2a58',
      'bankId': 'caja-rural-navarra',
      'bankName': 'Caja Rural de Navarra',
      'status': 'active',
      'expiresAt': '2027-04-28T21:58:00Z',
    },
    {
      'id': 'b1',
      'bankId': 'trade-republic',
      'bankName': 'Trade Republic',
      'status': 'expired',
      'expiresAt': '2026-10-01T10:00:00Z',
    },
  ],
};

// Only Caja Rural is linked, so Trade Republic can be
const onlyCajaRural = {
  'items': [
    {
      'id': 'a5d3f8e1-9b2c-4e7a-8f60-4c1b7d9e2a58',
      'bankId': 'caja-rural-navarra',
      'bankName': 'Caja Rural de Navarra',
      'status': 'active',
      'expiresAt': '2027-04-28T21:58:00Z',
    },
  ],
};

final bankLogin = Uri.parse('https://tilisy.enablebanking.com/welcome?sessionid=abc');

class FakeConnectionsRepository implements ConnectionsRepository {
  FakeConnectionsRepository(this.result, {Future<Uri> Function()? login}) : login = login ?? (() async => bankLogin);

  final Future<ConnectionList> Function() result;
  final Future<Uri> Function() login;
  final calls = <String>[];

  @override
  Future<ConnectionList> getConnections() {
    calls.add('list');
    return result();
  }

  @override
  Future<Uri> startLink(String bankId) {
    calls.add('link $bankId');
    return login();
  }

  @override
  Future<Uri> startRenewal(String connectionId) {
    calls.add('renew $connectionId');
    return login();
  }
}

/// Records the URLs the app opens instead of opening a browser.
class FakeBrowser {
  FakeBrowser({this.opens = true});

  final bool opens;
  final opened = <Uri>[];

  Future<bool> call(Uri url) async {
    opened.add(url);
    return opens;
  }
}

Future<void> pumpConnections(
  WidgetTester tester,
  FakeConnectionsRepository repository, {
  FakeBrowser? browser,
  ConnectionsScreen screen = const ConnectionsScreen(),
  List<dynamic> overrides = const [],
}) async {
  await pumpScreen(
    tester,
    screen,
    overrides: [
      connectionsRepositoryProvider.overrideWithValue(repository),
      browserLauncherProvider.overrideWithValue((browser ?? FakeBrowser()).call),
      ...overrides,
    ],
  );
  await tester.pumpAndSettle();
}

void main() {
  test('reads the contract example', () {
    final list = ConnectionList.fromJson(example);

    expect(list.items.first.status, ConnectionStatus.active);
    expect(list.items.first.expiresAt, DateTime.utc(2027, 4, 28, 21, 58));
    expect(list.items.last.status.needsAttention, isTrue);
  });

  test('the repository calls GET /api/connections', () async {
    final adapter = FakeAdapter((_) => (200, example));

    await ApiConnectionsRepository(fakeApi(adapter)).getConnections();

    expect(adapter.requests.single.path, '/api/connections');
  });

  group('link a bank', () {
    // The example of docs/api.md → "Link a bank"
    const authorization = {'authorizationUrl': 'https://tilisy.enablebanking.com/welcome?sessionid=abc'};

    test('the repository posts the bank code and returns the login URL', () async {
      final adapter = FakeAdapter((_) => (200, authorization));

      final url = await ApiConnectionsRepository(fakeApi(adapter)).startLink('trade-republic');

      expect(url, bankLogin);
      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.path, '/api/connections');
      expect(adapter.requests.single.data, {'bank': 'trade-republic'});
    });

    test('the repository renews a connection with no body', () async {
      final adapter = FakeAdapter((_) => (200, authorization));

      final url = await ApiConnectionsRepository(fakeApi(adapter)).startRenewal('b1');

      expect(url, bankLogin);
      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.path, '/api/connections/b1/renew');
      expect(adapter.requests.single.data, isNull);
    });

    test('only the banks that are not linked yet can be linked', () {
      expect(ConnectionList.fromJson(onlyCajaRural).unlinkedBanks.map((b) => b.id), ['trade-republic']);
      expect(ConnectionList.fromJson(example).unlinkedBanks, isEmpty);
    });

    test('reads the result deep link', () {
      LinkOutcome outcome(String query) =>
          LinkOutcome.fromQuery(Uri.parse('financeshub://connections/result?$query').queryParameters);

      expect(outcome('status=success&synced=true'), LinkOutcome.synced);
      expect(outcome('status=success&synced=false'), LinkOutcome.linkedNotSynced);
      expect(outcome('status=error&reason=cancelled'), LinkOutcome.cancelled);
      expect(outcome('status=error&reason=denied'), LinkOutcome.denied);
      expect(outcome('status=error&reason=failed'), LinkOutcome.failed);
      expect(outcome('status=error&reason=something-new'), LinkOutcome.failed);
    });

    testWidgets('"Vincular banco" opens the login of the chosen bank in the browser', (tester) async {
      final repository = FakeConnectionsRepository(() async => ConnectionList.fromJson(onlyCajaRural));
      final browser = FakeBrowser();
      await pumpConnections(tester, repository, browser: browser);

      await tester.tap(find.text('Vincular banco'));
      await tester.pumpAndSettle();
      // Caja Rural is already linked: only Trade Republic is offered
      expect(find.text('Caja Rural de Navarra'), findsOneWidget);
      await tester.tap(find.text('Trade Republic'));
      await tester.pumpAndSettle();

      expect(repository.calls, contains('link trade-republic'));
      expect(browser.opened, [bankLogin]);
    });

    testWidgets('no "Vincular banco" when every bank is linked', (tester) async {
      await pumpConnections(tester, FakeConnectionsRepository(() async => ConnectionList.fromJson(example)));

      expect(find.text('Vincular banco'), findsNothing);
    });

    testWidgets('"Reconectar" only on the connections that need it, and it renews that one', (tester) async {
      final repository = FakeConnectionsRepository(() async => ConnectionList.fromJson(example));
      final browser = FakeBrowser();
      await pumpConnections(tester, repository, browser: browser);

      expect(find.text('Reconectar'), findsOneWidget);
      await tester.tap(find.text('Reconectar'));
      await tester.pumpAndSettle();

      expect(repository.calls, contains('renew b1'));
      expect(browser.opened, [bankLogin]);
    });

    testWidgets('an API error is shown', (tester) async {
      final repository = FakeConnectionsRepository(
        () async => ConnectionList.fromJson(example),
        login: () async => throw const ApiException('Algo ha fallado en el servidor. Inténtalo de nuevo.'),
      );
      final browser = FakeBrowser();
      await pumpConnections(tester, repository, browser: browser);

      await tester.tap(find.text('Reconectar'));
      await tester.pumpAndSettle();

      expect(find.text('Algo ha fallado en el servidor. Inténtalo de nuevo.'), findsOneWidget);
      expect(browser.opened, isEmpty);
    });

    testWidgets('says so when the browser does not open', (tester) async {
      final repository = FakeConnectionsRepository(() async => ConnectionList.fromJson(example));
      await pumpConnections(tester, repository, browser: FakeBrowser(opens: false));

      await tester.tap(find.text('Reconectar'));
      await tester.pumpAndSettle();

      expect(find.text('No se ha podido abrir el navegador.'), findsOneWidget);
    });

    testWidgets('the result shows until it is closed', (tester) async {
      final repository = FakeConnectionsRepository(() async => ConnectionList.fromJson(example));
      await pumpConnections(
        tester,
        repository,
        screen: const ConnectionsScreen(showLinkOutcome: true),
        overrides: [linkOutcomeProvider.overrideWith(_LinkedNotSynced.new)],
      );

      expect(find.textContaining('Se reintentará en la próxima sincronización'), findsOneWidget);
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Se reintentará'), findsNothing);
    });

    testWidgets("the bank's deep link opens Conexiones with the result and refreshes the data", (tester) async {
      await initializeDateFormatting('es_ES');
      final connections = FakeConnectionsRepository(() async => ConnectionList.fromJson(example));
      var summaryLoads = 0;
      final summary = summary_test.FakeSummaryRepository(() async {
        summaryLoads++;
        return Summary.fromJson(summary_test.example);
      });
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            // Local API: no sign-in
            appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test', demo: false)),
            connectionsRepositoryProvider.overrideWithValue(connections),
            summaryRepositoryProvider.overrideWithValue(summary),
          ],
          child: const FinancesHubApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(summaryLoads, 1);

      // What Android sends when the browser opens financeshub://… (FlutterActivity → pushRouteInformation)
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/navigation',
        const JSONMethodCodec().encodeMethodCall(
          const MethodCall('pushRouteInformation', {
            'location': 'financeshub://connections/result?status=error&reason=cancelled',
            'state': null,
          }),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();

      expect(find.text('Conexiones'), findsOneWidget);
      expect(find.text('Has cancelado la vinculación.'), findsOneWidget);
      expect(summaryLoads, 2);
      // Back goes to Inicio
      expect(find.byType(BackButton), findsOneWidget);
    });
  });

  testWidgets('shows each bank with its status and expiry', (tester) async {
    await pumpScreen(
      tester,
      const ConnectionsScreen(),
      overrides: [
        connectionsRepositoryProvider.overrideWithValue(
          FakeConnectionsRepository(() async => ConnectionList.fromJson(example)),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Caja Rural de Navarra'), findsOneWidget);
    expect(find.textContaining('Activa · hasta el'), findsOneWidget);
    expect(find.textContaining('Caducada'), findsOneWidget);
  });

  testWidgets('empty', (tester) async {
    await pumpScreen(
      tester,
      const ConnectionsScreen(),
      overrides: [
        connectionsRepositoryProvider.overrideWithValue(
          FakeConnectionsRepository(() async => const ConnectionList(items: [])),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Aún no hay ningún banco vinculado.'), findsOneWidget);
  });

  testWidgets('loading', (tester) async {
    await pumpScreen(
      tester,
      const ConnectionsScreen(),
      overrides: [
        connectionsRepositoryProvider.overrideWithValue(FakeConnectionsRepository(() => Completer<Never>().future)),
      ],
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('error', (tester) async {
    await pumpScreen(
      tester,
      const ConnectionsScreen(),
      overrides: [
        connectionsRepositoryProvider.overrideWithValue(
          FakeConnectionsRepository(() async => throw const ApiException('Sin conexión.')),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Sin conexión.'), findsOneWidget);
  });
}

class _LinkedNotSynced extends LinkOutcomeNotifier {
  @override
  LinkOutcome? build() => LinkOutcome.linkedNotSynced;
}
