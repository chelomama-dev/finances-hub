import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:finances_hub/core/api/api_exception.dart';
import 'package:finances_hub/core/dates.dart';
import 'package:finances_hub/core/money.dart';
import 'package:finances_hub/features/transactions/data/transactions.dart';
import 'package:finances_hub/features/transactions/data/transactions_repository.dart';
import 'package:finances_hub/features/transactions/presentation/transactions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

// The example of docs/api.md → "List transactions"
const example = {
  'items': [
    {
      'id': 'c81e5a0f-2d3b-4f6a-9e47-1a8b5c0d9e21',
      'bookingDate': '2026-11-01',
      'amount': {'amount': '-23.40', 'currency': 'EUR'},
      'description': 'MERCADONA PAMPLONA',
      'counterparty': 'Mercadona S.A.',
      'status': 'booked',
      'bank': {'id': 'caja-rural-navarra', 'name': 'Caja Rural de Navarra'},
    },
    {
      'id': 'e4a7b2c9-6f1d-4a83-b5e0-3c9d8f2a1b76',
      'bookingDate': '2026-10-31',
      'amount': {'amount': '1650.00', 'currency': 'EUR'},
      'description': null,
      'counterparty': null,
      'status': 'booked',
      'bank': {'id': 'trade-republic', 'name': 'Trade Republic'},
    },
  ],
  'nextCursor': 'eyJkIjoiMjAyNi0xMC0zMSIsImkiOjQyfQ',
};

class FakeTransactionsRepository implements TransactionsRepository {
  FakeTransactionsRepository(this.pages);

  /// By cursor: `null` is the first page
  final Map<String?, Future<TransactionPage> Function()> pages;
  final calls = <(TransactionFilter, String?)>[];

  @override
  Future<TransactionPage> getTransactions({required TransactionFilter filter, String? cursor, int limit = 50}) {
    calls.add((filter, cursor));
    return pages[cursor]!();
  }
}

Transaction tx(String id, DateTime date, String amount, {String? description = 'COMPRA'}) => Transaction(
  id: id,
  bookingDate: date,
  amount: Money(Decimal.parse(amount), 'EUR'),
  description: description,
  counterparty: null,
  status: TransactionStatus.booked,
  bank: const TransactionBank(id: 'trade-republic', name: 'Trade Republic'),
);

void main() {
  group('data', () {
    test('reads the contract example', () {
      final page = TransactionPage.fromJson(example);

      expect(page.items.first.bookingDate, DateTime(2026, 11, 1));
      expect(page.items.first.amount, Money(Decimal.parse('-23.40'), 'EUR'));
      expect(page.items.first.isIncome, isFalse);
      expect(page.items.last.isIncome, isTrue);
      expect(page.items.last.description, isNull);
      expect(page.items.last.bank.name, 'Trade Republic');
      expect(page.nextCursor, isNotNull);
    });

    test('the repository sends the filters and the cursor as the API expects', () async {
      final adapter = FakeAdapter((_) => (200, {'items': [], 'nextCursor': null}));

      await ApiTransactionsRepository(fakeApi(adapter)).getTransactions(
        filter: TransactionFilter(
          range: DateTimeRange(start: DateTime(2026, 10, 1), end: DateTime(2026, 11, 2)),
          direction: TransactionDirection.expense,
        ),
        cursor: 'abc',
      );

      final request = adapter.requests.single;
      expect(request.path, '/api/transactions');
      expect(request.queryParameters, {
        'limit': 50,
        'from': '2026-10-01',
        'to': '2026-11-02',
        'direction': 'expense',
        'cursor': 'abc',
      });
    });

    test('without filters only the page size is sent', () async {
      final adapter = FakeAdapter((_) => (200, {'items': [], 'nextCursor': null}));

      await ApiTransactionsRepository(fakeApi(adapter)).getTransactions(filter: const TransactionFilter());

      expect(adapter.requests.single.queryParameters, {'limit': 50});
    });

    test('the demo repository pages and filters like the API', () async {
      final demo = DemoTransactionsRepository(today: DateTime(2026, 11, 2));

      final first = await demo.getTransactions(filter: const TransactionFilter(), limit: 10);
      final second = await demo.getTransactions(filter: const TransactionFilter(), limit: 10, cursor: first.nextCursor);
      final income = await demo.getTransactions(
        filter: const TransactionFilter(direction: TransactionDirection.income),
      );

      expect(first.items, hasLength(10));
      expect(second.items.first.id, isNot(first.items.last.id));
      expect(income.items, everyElement(predicate<Transaction>((t) => t.isIncome)));
      expect(first.items.map((t) => t.bank.id).toSet(), {'caja-rural-navarra', 'trade-republic'});
    });
  });

  group('screen', () {
    testWidgets('shows every bank together, marks a missing description, and loads the next page at the end', (
      tester,
    ) async {
      final days = List.generate(30, (i) => DateTime(2026, 10, 30).subtract(Duration(days: i)));
      final repository = FakeTransactionsRepository({
        null: () async => TransactionPage(
          items: [
            tx('a', DateTime(2026, 10, 31), '-23.40', description: null),
            for (final d in days) tx('$d', d, '-1.00'),
          ],
          nextCursor: 'next',
        ),
        'next': () async => TransactionPage(
          items: [tx('last', DateTime(2026, 9, 1), '1650.00', description: 'NOMINA')],
          nextCursor: null,
        ),
      });
      await pumpScreen(
        tester,
        const TransactionsScreen(),
        overrides: [transactionsRepositoryProvider.overrideWithValue(repository)],
      );
      await tester.pumpAndSettle();

      expect(find.text('Movimientos'), findsOneWidget);
      expect(find.text('Sin descripción'), findsOneWidget);
      expect(find.text('-23,40 €'), findsOneWidget);
      expect(find.text(rowDate(DateTime(2026, 10, 31))), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pumpAndSettle();

      expect(repository.calls.map((c) => c.$2), [null, 'next']);
      await tester.scrollUntilVisible(find.text('NOMINA'), 300);
      expect(find.text('1.650,00 €'), findsOneWidget);
    });

    testWidgets('a direction filter reloads from the first page', (tester) async {
      final repository = FakeTransactionsRepository({
        null: () async => TransactionPage(items: [tx('a', DateTime(2026, 10, 31), '-1.00')], nextCursor: null),
      });
      await pumpScreen(
        tester,
        const TransactionsScreen(),
        overrides: [transactionsRepositoryProvider.overrideWithValue(repository)],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gastos'));
      await tester.pumpAndSettle();

      expect(repository.calls.map((c) => c.$1.direction), [null, TransactionDirection.expense]);
    });

    testWidgets('a row has a green dot for income, a red one for an expense, and cuts a long description', (
      tester,
    ) async {
      final long = 'COMPRA TARJ. ${'MUY LARGA ' * 20}';
      await pumpScreen(
        tester,
        Scaffold(
          body: Column(
            children: [
              TransactionRow(transaction: tx('in', DateTime(2026, 10, 31), '1650.00', description: 'NOMINA')),
              TransactionRow(transaction: tx('out', DateTime(2026, 10, 30), '-9.99', description: long)),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      Color dotOf(String id) {
        final row = find.byType(TransactionRow).at(id == 'in' ? 0 : 1);
        final box = tester.widget<DecoratedBox>(find.descendant(of: row, matching: find.byType(DecoratedBox)).first);
        return (box.decoration as BoxDecoration).color!;
      }

      expect(dotOf('in'), Colors.green.shade700);
      expect(dotOf('out'), Colors.red.shade700);
      final text = tester.widget<Text>(find.text(long));
      expect((text.maxLines, text.overflow), (1, TextOverflow.ellipsis));
      expect(find.text('TR'), findsNWidgets(2));
    });

    testWidgets('a narrow row leaves the bank out', (tester) async {
      await pumpScreen(
        tester,
        Scaffold(
          body: Center(
            child: SizedBox(
              width: TransactionRow.minWidthForBank - 1,
              child: TransactionRow(transaction: tx('a', DateTime(2026, 10, 31), '-1.00')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BankBadge), findsNothing);
      expect(find.text('-1,00 €'), findsOneWidget);
    });

    test('bank initials skip the short words', () {
      expect(bankInitials('Caja Rural de Navarra'), 'CR');
      expect(bankInitials('Trade Republic'), 'TR');
      expect(bankInitials('ING'), 'I');
    });

    testWidgets('empty', (tester) async {
      await pumpScreen(
        tester,
        const TransactionsScreen(),
        overrides: [
          transactionsRepositoryProvider.overrideWithValue(
            FakeTransactionsRepository({null: () async => const TransactionPage(items: [], nextCursor: null)}),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('No hay movimientos con estos filtros.'), findsOneWidget);
    });

    testWidgets('loading', (tester) async {
      await pumpScreen(
        tester,
        const TransactionsScreen(),
        overrides: [
          transactionsRepositoryProvider.overrideWithValue(
            FakeTransactionsRepository({null: () => Completer<Never>().future}),
          ),
        ],
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('error', (tester) async {
      await pumpScreen(
        tester,
        const TransactionsScreen(),
        overrides: [
          transactionsRepositoryProvider.overrideWithValue(
            FakeTransactionsRepository({null: () async => throw const ApiException('Algo ha fallado.')}),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('Algo ha fallado.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });
  });
}
