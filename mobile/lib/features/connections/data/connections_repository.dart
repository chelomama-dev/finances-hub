import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config.dart';
import '../../../core/connection_status.dart';
import 'connections.dart';

abstract interface class ConnectionsRepository {
  Future<ConnectionList> getConnections();
}

final connectionsRepositoryProvider = Provider<ConnectionsRepository>(
  (ref) => ref.watch(appConfigProvider).demo
      ? const DemoConnectionsRepository()
      : ApiConnectionsRepository(ref.watch(apiClientProvider)),
);

class ApiConnectionsRepository implements ConnectionsRepository {
  const ApiConnectionsRepository(this._api);

  final ApiClient _api;

  @override
  Future<ConnectionList> getConnections() async => ConnectionList.fromJson(await _api.get('/api/connections'));
}

/// Made-up data, shaped like the example in docs/api.md.
class DemoConnectionsRepository implements ConnectionsRepository {
  const DemoConnectionsRepository();

  @override
  Future<ConnectionList> getConnections() async {
    final now = DateTime.now().toUtc();
    return ConnectionList(
      items: [
        Connection(
          id: 'demo-connection-caja-rural',
          bankId: 'caja-rural-navarra',
          bankName: 'Caja Rural de Navarra',
          status: ConnectionStatus.active,
          expiresAt: now.add(const Duration(days: 170)),
        ),
        Connection(
          id: 'demo-connection-trade-republic',
          bankId: 'trade-republic',
          bankName: 'Trade Republic',
          status: ConnectionStatus.expiring,
          expiresAt: now.add(const Duration(days: 9)),
        ),
      ],
    );
  }
}
