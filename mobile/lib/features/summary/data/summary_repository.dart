import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config.dart';
import '../../../core/connection_status.dart';
import '../../../core/money.dart';
import 'summary.dart';

abstract interface class SummaryRepository {
  Future<Summary> getSummary();
}

final summaryRepositoryProvider = Provider<SummaryRepository>(
  (ref) => ref.watch(appConfigProvider).demo
      ? const DemoSummaryRepository()
      : ApiSummaryRepository(ref.watch(apiClientProvider)),
);

class ApiSummaryRepository implements SummaryRepository {
  const ApiSummaryRepository(this._api);

  final ApiClient _api;

  @override
  Future<Summary> getSummary() async => Summary.fromJson(await _api.get('/api/summary'));
}

/// Made-up data, shaped like the example in docs/api.md.
class DemoSummaryRepository implements SummaryRepository {
  const DemoSummaryRepository();

  @override
  Future<Summary> getSummary() async => Summary(
    totalBalance: Money(Decimal.parse('12873.45'), 'EUR'),
    lastSyncedAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
    banks: [
      BankSummary(
        id: 'caja-rural-navarra',
        name: 'Caja Rural de Navarra',
        balance: Money(Decimal.parse('3120.80'), 'EUR'),
        connectionStatus: ConnectionStatus.active,
      ),
      BankSummary(
        id: 'trade-republic',
        name: 'Trade Republic',
        balance: Money(Decimal.parse('9752.65'), 'EUR'),
        connectionStatus: ConnectionStatus.expiring,
      ),
    ],
  );
}
