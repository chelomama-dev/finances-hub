import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:finances_hub/core/api/api_exception.dart';
import 'package:finances_hub/core/money.dart';
import 'package:finances_hub/features/statistics/data/statistics.dart';
import 'package:finances_hub/features/statistics/data/statistics_repository.dart';
import 'package:finances_hub/features/statistics/presentation/statistics_screen.dart';
import 'package:finances_hub/features/transactions/data/transactions_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

// The example of docs/api.md → "Get statistics"
const example = {
  'from': '2026-10-07',
  'to': '2026-11-05',
  'income': {'amount': '1650.00', 'currency': 'EUR'},
  'expenses': {'amount': '-812.30', 'currency': 'EUR'},
  'topExpenses': [
    {
      'description': 'MERCADONA PAMPLONA',
      'amount': {'amount': '-212.75', 'currency': 'EUR'},
      'count': 6,
    },
    {
      'description': 'RECIBO LUZ',
      'amount': {'amount': '-61.32', 'currency': 'EUR'},
      'count': 1,
    },
    {
      'description': null,
      'amount': {'amount': '-49.95', 'currency': 'EUR'},
      'count': 5,
    },
  ],
  'otherExpenses': {'amount': '-488.28', 'currency': 'EUR'},
  'days': [
    {
      'date': '2026-10-31',
      'income': {'amount': '1650.00', 'currency': 'EUR'},
      'expenses': {'amount': '0.00', 'currency': 'EUR'},
    },
    {
      'date': '2026-11-01',
      'income': {'amount': '0.00', 'currency': 'EUR'},
      'expenses': {'amount': '-23.40', 'currency': 'EUR'},
    },
  ],
};

class FakeStatisticsRepository implements StatisticsRepository {
  FakeStatisticsRepository(this.respond);

  final Future<Statistics> Function() respond;
  final calls = <(DateTime, DateTime)>[];

  @override
  Future<Statistics> getStatistics({required DateTime from, required DateTime to}) {
    calls.add((from, to));
    return respond();
  }
}

Money eur(String amount) => Money(Decimal.parse(amount), 'EUR');

void main() {
  group('data', () {
    test('reads the contract example', () {
      final statistics = Statistics.fromJson(example);

      expect(statistics.from, DateTime(2026, 10, 7));
      expect(statistics.expenses, eur('-812.30'));
      expect(statistics.topExpenses.map((g) => g.description), ['MERCADONA PAMPLONA', 'RECIBO LUZ', null]);
      expect(statistics.topExpenses.first.count, 6);
      expect(statistics.otherExpenses, eur('-488.28'));
      expect(statistics.days.last.date, DateTime(2026, 11, 1));
    });

    test('the repository asks for the range as dates', () async {
      final adapter = FakeAdapter((_) => (200, example));

      await ApiStatisticsRepository(fakeApi(adapter))
          .getStatistics(from: DateTime(2026, 10, 7), to: DateTime(2026, 11, 5));

      expect(adapter.requests.single.path, '/api/statistics');
      expect(adapter.requests.single.queryParameters, {'from': '2026-10-07', 'to': '2026-11-05'});
    });

    test('periods count back from today, today included', () {
      final range = StatisticsPeriod.month.range(DateTime(2026, 11, 5, 18, 30));

      expect(range, (from: DateTime(2026, 10, 7), to: DateTime(2026, 11, 5)));
      expect(StatisticsPeriod.week.range(DateTime(2026, 11, 5)).from, DateTime(2026, 10, 30));
    });

    test('bars add up groups of days counted back from the last one', () {
      final statistics = Statistics.fromJson(example);

      final periods = totalsByPeriod(statistics, 7);

      expect(periods, hasLength(5));
      expect((periods.first.start, periods.first.end), (DateTime(2026, 10, 7), DateTime(2026, 10, 8)));
      expect((periods.last.start, periods.last.end), (DateTime(2026, 10, 30), DateTime(2026, 11, 5)));
      expect(periods.last.income, Decimal.parse('1650.00'));
      expect(periods.last.expenses, Decimal.parse('23.40'));
      expect(periods.first.income, Decimal.zero);
    });

    test('daily bars have one per day', () {
      final statistics = Statistics.fromJson({...example, 'from': '2026-10-30'});

      expect(totalsByPeriod(statistics, 1).map((p) => p.start), [for (var d = 30; d <= 36; d++) DateTime(2026, 10, d)]);
    });

    test('the demo repository adds up the demo transactions like the API', () async {
      final demo = DemoStatisticsRepository(DemoTransactionsRepository(today: DateTime(2026, 11, 5)));

      final statistics = await demo.getStatistics(from: DateTime(2026, 10, 7), to: DateTime(2026, 11, 5));

      expect(statistics.topExpenses.length, lessThanOrEqualTo(5));
      final top = statistics.topExpenses.fold(Decimal.zero, (total, g) => total + g.amount.amount);
      expect(top + statistics.otherExpenses.amount, statistics.expenses.amount);
      expect(statistics.income, eur('1650.00'));
      expect(statistics.days.first.date, DateTime(2026, 10, 7));
    });
  });

  group('screen', () {
    testWidgets('shows the donut with its legend and the bars, for 30 days by default', (tester) async {
      final repository = FakeStatisticsRepository(() async => Statistics.fromJson(example));
      await pumpScreen(
        tester,
        const StatisticsScreen(),
        overrides: [statisticsRepositoryProvider.overrideWithValue(repository)],
      );
      await tester.pumpAndSettle();

      expect(find.byType(PieChart), findsOneWidget);
      expect(find.byType(BarChart), findsOneWidget);
      expect(find.text('812,30 €'), findsNWidgets(2));
      expect(find.text('MERCADONA PAMPLONA'), findsOneWidget);
      expect(find.text('Sin descripción'), findsOneWidget);
      expect(find.text('Otros'), findsOneWidget);
      expect(find.text('26 %'), findsOneWidget);
      final (from, to) = repository.calls.single;
      expect(to.difference(from).inDays, 29);
    });

    testWidgets('another period reloads', (tester) async {
      final repository = FakeStatisticsRepository(() async => Statistics.fromJson(example));
      await pumpScreen(
        tester,
        const StatisticsScreen(),
        overrides: [statisticsRepositoryProvider.overrideWithValue(repository)],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('90 días'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('7 días'));
      await tester.pumpAndSettle();

      expect(repository.calls.map((c) => c.$2.difference(c.$1).inDays), [29, 89, 6]);
    });

    testWidgets('only income: no donut', (tester) async {
      final repository = FakeStatisticsRepository(
        () async => Statistics.fromJson({
          ...example,
          'expenses': {'amount': '0.00', 'currency': 'EUR'},
          'topExpenses': [],
          'otherExpenses': {'amount': '0.00', 'currency': 'EUR'},
        }),
      );
      await pumpScreen(
        tester,
        const StatisticsScreen(),
        overrides: [statisticsRepositoryProvider.overrideWithValue(repository)],
      );
      await tester.pumpAndSettle();

      expect(find.byType(PieChart), findsNothing);
      expect(find.text('No hay gastos en este periodo.'), findsOneWidget);
      expect(find.byType(BarChart), findsOneWidget);
    });

    testWidgets('empty', (tester) async {
      await pumpScreen(
        tester,
        const StatisticsScreen(),
        overrides: [
          statisticsRepositoryProvider.overrideWithValue(
            FakeStatisticsRepository(
              () async => Statistics.fromJson({
                ...example,
                'income': {'amount': '0.00', 'currency': 'EUR'},
                'expenses': {'amount': '0.00', 'currency': 'EUR'},
                'topExpenses': [],
                'otherExpenses': {'amount': '0.00', 'currency': 'EUR'},
                'days': [],
              }),
            ),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('No hay movimientos en este periodo.'), findsOneWidget);
    });

    testWidgets('loading', (tester) async {
      await pumpScreen(
        tester,
        const StatisticsScreen(),
        overrides: [
          statisticsRepositoryProvider.overrideWithValue(FakeStatisticsRepository(() => Completer<Never>().future)),
        ],
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('error', (tester) async {
      await pumpScreen(
        tester,
        const StatisticsScreen(),
        overrides: [
          statisticsRepositoryProvider.overrideWithValue(
            FakeStatisticsRepository(() async => throw const ApiException('Algo ha fallado.')),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('Algo ha fallado.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });
  });
}
