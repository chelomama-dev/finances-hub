import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config.dart';
import '../../../core/dates.dart';
import '../../../core/money.dart';
import 'transactions.dart';

abstract interface class TransactionsRepository {
  Future<TransactionPage> getTransactions({
    required TransactionFilter filter,
    String? cursor,
    int limit = TransactionsRepository.pageSize,
  });

  static const pageSize = 50;
}

final transactionsRepositoryProvider = Provider<TransactionsRepository>(
  (ref) => ref.watch(appConfigProvider).demo
      ? DemoTransactionsRepository()
      : ApiTransactionsRepository(ref.watch(apiClientProvider)),
);

class ApiTransactionsRepository implements TransactionsRepository {
  const ApiTransactionsRepository(this._api);

  final ApiClient _api;

  @override
  Future<TransactionPage> getTransactions({
    required TransactionFilter filter,
    String? cursor,
    int limit = TransactionsRepository.pageSize,
  }) async {
    final range = filter.range;
    return TransactionPage.fromJson(
      await _api.get(
        '/api/transactions',
        query: {
          'limit': limit,
          if (range != null) 'from': apiDate(range.start),
          if (range != null) 'to': apiDate(range.end),
          if (filter.direction != null) 'direction': filter.direction!.name,
          'cursor': ?cursor,
        },
      ),
    );
  }
}

/// Made-up transactions of both banks for the last months, filtered and paged like the API does.
class DemoTransactionsRepository implements TransactionsRepository {
  DemoTransactionsRepository({DateTime? today}) : _all = _generate(today ?? DateTime.now());

  final List<Transaction> _all;

  @override
  Future<TransactionPage> getTransactions({
    required TransactionFilter filter,
    String? cursor,
    int limit = TransactionsRepository.pageSize,
  }) async {
    final range = filter.range;
    final matching = _all.where((t) {
      if (range != null && (t.bookingDate.isBefore(range.start) || t.bookingDate.isAfter(range.end))) return false;
      return switch (filter.direction) {
        TransactionDirection.income => t.isIncome,
        TransactionDirection.expense => !t.isIncome,
        null => true,
      };
    }).toList();

    final start = cursor == null ? 0 : int.parse(cursor);
    final end = (start + limit).clamp(0, matching.length);
    return TransactionPage(items: matching.sublist(start, end), nextCursor: end < matching.length ? '$end' : null);
  }

  static List<Transaction> _generate(DateTime today) {
    const expenses = [
      ('COMPRA TARJ. SUPERMERCADO', 'Supermercado Ejemplo S.L.', '-23.40'),
      ('COMPRA TARJ. GASOLINERA', null, '-45.10'),
      ('RECIBO LUZ', 'Eléctrica Inventada S.A.', '-61.32'),
      ('BIZUM ENVIADO', 'Amigo Inventado', '-15.00'),
      (null, null, '-9.99'),
    ];
    final day = DateTime(today.year, today.month, today.day);
    final result = <Transaction>[];
    for (var i = 0; i < 90; i++) {
      // By calendar day, not by 24 hours, which would land at 01:00 or 23:00 across a daylight saving change
      final date = DateTime(day.year, day.month, day.day - i);
      if (date.day == 1) {
        result.add(_tx('${i}n', date, '1650.00', 'NOMINA', 'Empresa Ejemplo S.A.', _cajaRural));
      }
      final (description, counterparty, amount) = expenses[i % expenses.length];
      // Trade Republic sends no description, like the transactions the bank really sends
      result.add(
        _tx('${i}e', date, amount, description, counterparty, description == null ? _tradeRepublic : _cajaRural),
      );
    }
    return result;
  }

  static const _cajaRural = TransactionBank(id: 'caja-rural-navarra', name: 'Caja Rural de Navarra');
  static const _tradeRepublic = TransactionBank(id: 'trade-republic', name: 'Trade Republic');

  static Transaction _tx(
    String id,
    DateTime date,
    String amount,
    String? description,
    String? counterparty,
    TransactionBank bank,
  ) => Transaction(
    id: 'demo-$id',
    bookingDate: date,
    amount: Money(Decimal.parse(amount), 'EUR'),
    description: description,
    counterparty: counterparty,
    status: TransactionStatus.booked,
    bank: bank,
  );
}
