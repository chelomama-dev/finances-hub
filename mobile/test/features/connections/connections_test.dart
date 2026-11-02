import 'dart:async';

import 'package:finances_hub/core/api/api_exception.dart';
import 'package:finances_hub/core/connection_status.dart';
import 'package:finances_hub/features/connections/data/connections.dart';
import 'package:finances_hub/features/connections/data/connections_repository.dart';
import 'package:finances_hub/features/connections/presentation/connections_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

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

class FakeConnectionsRepository implements ConnectionsRepository {
  FakeConnectionsRepository(this.result);

  final Future<ConnectionList> Function() result;

  @override
  Future<ConnectionList> getConnections() => result();
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

  testWidgets('shows each bank with its status and expiry', (tester) async {
    await pumpScreen(tester, const ConnectionsScreen(),
        overrides: [connectionsRepositoryProvider.overrideWithValue(FakeConnectionsRepository(() async => ConnectionList.fromJson(example)))]);
    await tester.pumpAndSettle();

    expect(find.text('Caja Rural de Navarra'), findsOneWidget);
    expect(find.textContaining('Activa · hasta el'), findsOneWidget);
    expect(find.textContaining('Caducada'), findsOneWidget);
  });

  testWidgets('empty', (tester) async {
    await pumpScreen(tester, const ConnectionsScreen(),
        overrides: [connectionsRepositoryProvider.overrideWithValue(FakeConnectionsRepository(() async => const ConnectionList(items: [])))]);
    await tester.pumpAndSettle();

    expect(find.text('Aún no hay ningún banco vinculado.'), findsOneWidget);
  });

  testWidgets('loading', (tester) async {
    await pumpScreen(tester, const ConnectionsScreen(),
        overrides: [connectionsRepositoryProvider.overrideWithValue(FakeConnectionsRepository(() => Completer<Never>().future))]);
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('error', (tester) async {
    await pumpScreen(tester, const ConnectionsScreen(),
        overrides: [connectionsRepositoryProvider.overrideWithValue(FakeConnectionsRepository(() async => throw const ApiException('Sin conexión.')))]);
    await tester.pumpAndSettle();

    expect(find.text('Sin conexión.'), findsOneWidget);
  });
}
