import 'dart:async';

import 'package:flutter/material.dart';
import 'package:decimal/decimal.dart';
import 'package:finances_hub/core/api/api_exception.dart';
import 'package:finances_hub/core/auth/auth_providers.dart';
import 'package:finances_hub/core/connection_status.dart';
import 'package:finances_hub/core/money.dart';
import 'package:finances_hub/features/summary/data/summary.dart';
import 'package:finances_hub/features/summary/data/summary_repository.dart';
import 'package:finances_hub/features/summary/presentation/summary_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/auth/fake_authenticator.dart';
import '../../helpers.dart';

// The example of docs/api.md → "Get the summary"
const example = {
  'totalBalance': {'amount': '12873.45', 'currency': 'EUR'},
  'lastSyncedAt': '2026-11-02T07:00:12Z',
  'banks': [
    {
      'id': 'caja-rural-navarra',
      'name': 'Caja Rural de Navarra',
      'balance': {'amount': '3120.80', 'currency': 'EUR'},
      'connectionStatus': 'active',
    },
    {
      'id': 'trade-republic',
      'name': 'Trade Republic',
      'balance': {'amount': '9752.65', 'currency': 'EUR'},
      'connectionStatus': 'expiring',
    },
  ],
};

class FakeSummaryRepository implements SummaryRepository {
  FakeSummaryRepository(this.result);

  Future<Summary> Function() result;

  @override
  Future<Summary> getSummary() => result();
}

void main() {
  group('data', () {
    test('reads the contract example', () {
      final summary = Summary.fromJson(example);

      expect(summary.totalBalance, Money(Decimal.parse('12873.45'), 'EUR'));
      expect(summary.lastSyncedAt, DateTime.utc(2026, 11, 2, 7, 0, 12));
      expect(summary.banks.map((b) => b.id), ['caja-rural-navarra', 'trade-republic']);
      expect(summary.banks[1].connectionStatus, ConnectionStatus.expiring);
      expect(summary.needsAttention, isTrue);
    });

    test('a status the app does not know asks for attention', () {
      final json = {...example, 'banks': [{...(example['banks'] as List).first as Map<String, dynamic>, 'connectionStatus': 'new-status'}]};

      expect(Summary.fromJson(json).banks.single.connectionStatus, ConnectionStatus.expired);
    });

    test('the repository calls GET /api/summary', () async {
      final adapter = FakeAdapter((_) => (200, example));

      await ApiSummaryRepository(fakeApi(adapter)).getSummary();

      expect(adapter.requests.single.path, '/api/summary');
    });
  });

  group('screen', () {
    testWidgets('shows the total, each bank and the reconnect banner', (tester) async {
      await pumpScreen(tester, const SummaryScreen(),
          overrides: [summaryRepositoryProvider.overrideWithValue(FakeSummaryRepository(() async => Summary.fromJson(example)))]);
      await tester.pumpAndSettle();

      expect(find.text('12.873,45 €'), findsOneWidget);
      expect(find.text('Caja Rural de Navarra'), findsOneWidget);
      expect(find.text('9.752,65 €'), findsOneWidget);
      expect(find.text('Hay un banco que necesita reconectarse'), findsOneWidget);
      expect(find.textContaining('Actualizado hace'), findsOneWidget);
    });

    testWidgets('opens a bank', (tester) async {
      await pumpScreen(tester, const SummaryScreen(),
          overrides: [summaryRepositoryProvider.overrideWithValue(FakeSummaryRepository(() async => Summary.fromJson(example)))]);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trade Republic'));
      await tester.pumpAndSettle();

      expect(find.text('route /banks/trade-republic'), findsOneWidget);
    });

    testWidgets('loading', (tester) async {
      await pumpScreen(tester, const SummaryScreen(),
          overrides: [summaryRepositoryProvider.overrideWithValue(FakeSummaryRepository(() => Completer<Never>().future))]);
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('empty: no bank linked yet', (tester) async {
      await pumpScreen(tester, const SummaryScreen(),
          overrides: [summaryRepositoryProvider.overrideWithValue(FakeSummaryRepository(() async => Summary.fromJson({...example, 'banks': [], 'lastSyncedAt': null})))]);
      await tester.pumpAndSettle();

      expect(find.text('Aún no hay ningún banco vinculado.'), findsOneWidget);
      expect(find.text('Vincular banco'), findsOneWidget);
    });

    testWidgets('error, and retry', (tester) async {
      var calls = 0;
      final repository = FakeSummaryRepository(() async {
        calls++;
        throw const ApiException('No se puede conectar con el servidor.');
      });
      await pumpScreen(tester, const SummaryScreen(), overrides: [summaryRepositoryProvider.overrideWithValue(repository)]);
      await tester.pumpAndSettle();

      expect(find.text('No se puede conectar con el servidor.'), findsOneWidget);

      repository.result = () async => Summary.fromJson(example);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(find.text('12.873,45 €'), findsOneWidget);
    });

    testWidgets('without auth there is no sign-out button', (tester) async {
      await pumpScreen(tester, const SummaryScreen(),
          overrides: [summaryRepositoryProvider.overrideWithValue(FakeSummaryRepository(() async => Summary.fromJson(example)))]);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Cerrar sesión'), findsNothing);
    });

    testWidgets('signs out after confirming', (tester) async {
      final authenticator = FakeAuthenticator(token: 'abc');
      await pumpScreen(tester, const SummaryScreen(), overrides: [
        summaryRepositoryProvider.overrideWithValue(FakeSummaryRepository(() async => Summary.fromJson(example))),
        authenticatorProvider.overrideWithValue(authenticator),
      ]);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Cerrar sesión'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar sesión'));
      await tester.pumpAndSettle();

      expect(authenticator.signOutCalls, 1);
    });
  });
}
