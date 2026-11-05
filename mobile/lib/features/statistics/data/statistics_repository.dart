import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config.dart';
import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../transactions/data/transactions.dart';
import '../../transactions/data/transactions_repository.dart';
import 'statistics.dart';

abstract interface class StatisticsRepository {
  /// [from] and [to] are dates, both included.
  Future<Statistics> getStatistics({required DateTime from, required DateTime to});
}

final statisticsRepositoryProvider = Provider<StatisticsRepository>(
  (ref) => ref.watch(appConfigProvider).demo
      ? DemoStatisticsRepository(DemoTransactionsRepository())
      : ApiStatisticsRepository(ref.watch(apiClientProvider)),
);

class ApiStatisticsRepository implements StatisticsRepository {
  const ApiStatisticsRepository(this._api);

  final ApiClient _api;

  @override
  Future<Statistics> getStatistics({required DateTime from, required DateTime to}) async =>
      Statistics.fromJson(await _api.get('/api/statistics', query: {'from': apiDate(from), 'to': apiDate(to)}));
}

/// Adds up the demo transactions the way the API does, so the charts match the Movimientos tab.
class DemoStatisticsRepository implements StatisticsRepository {
  DemoStatisticsRepository(this._transactions);

  static const _currency = 'EUR';
  static const _topCount = 5;

  final TransactionsRepository _transactions;

  @override
  Future<Statistics> getStatistics({required DateTime from, required DateTime to}) async {
    final items = <Transaction>[];
    String? cursor;
    do {
      final page = await _transactions.getTransactions(
        filter: TransactionFilter(
          range: DateTimeRange(start: from, end: to),
        ),
        cursor: cursor,
        limit: 100,
      );
      items.addAll(page.items.where((t) => t.amount.currency == _currency));
      cursor = page.nextCursor;
    } while (cursor != null);

    Money sum(Iterable<Transaction> transactions) =>
        Money(transactions.fold(Decimal.zero, (total, t) => total + t.amount.amount), _currency);

    final expenses = items.where((t) => !t.isIncome).toList();
    final byDescription = <String?, List<Transaction>>{};
    for (final t in expenses) {
      byDescription.putIfAbsent(t.description, () => []).add(t);
    }
    final groups =
        byDescription.entries
            .map((e) => ExpenseGroup(description: e.key, amount: sum(e.value), count: e.value.length))
            .toList()
          ..sort((a, b) {
            final byAmount = a.amount.amount.compareTo(b.amount.amount);
            return byAmount != 0 ? byAmount : (a.description ?? '').compareTo(b.description ?? '');
          });

    final byDay = <DateTime, List<Transaction>>{};
    for (final t in items) {
      byDay.putIfAbsent(t.bookingDate, () => []).add(t);
    }
    final days = byDay.keys.toList()..sort();

    return Statistics(
      from: from,
      to: to,
      income: sum(items.where((t) => t.isIncome)),
      expenses: sum(expenses),
      topExpenses: groups.take(_topCount).toList(),
      otherExpenses: sum(groups.skip(_topCount).expand((g) => byDescription[g.description]!)),
      days: [
        for (final day in days)
          DayTotals(
            date: day,
            income: sum(byDay[day]!.where((t) => t.isIncome)),
            expenses: sum(byDay[day]!.where((t) => !t.isIncome)),
          ),
      ],
    );
  }
}
