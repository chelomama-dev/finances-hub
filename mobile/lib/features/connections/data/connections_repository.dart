import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config.dart';
import '../../../core/connection_status.dart';
import 'connections.dart';

abstract interface class ConnectionsRepository {
  Future<ConnectionList> getConnections();

  /// The bank's login page to link [bankId] (`POST /api/connections`).
  Future<Uri> startLink(String bankId);

  /// The bank's login page to reconnect [connectionId] (`POST /api/connections/{connectionId}/renew`).
  Future<Uri> startRenewal(String connectionId);
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

  @override
  Future<Uri> startLink(String bankId) async =>
      AuthorizationLink.fromJson(await _api.post('/api/connections', body: {'bank': bankId})).authorizationUrl;

  @override
  Future<Uri> startRenewal(String connectionId) async =>
      AuthorizationLink.fromJson(await _api.post('/api/connections/$connectionId/renew')).authorizationUrl;
}

/// Made-up data, shaped like the example in docs/api.md.
class DemoConnectionsRepository implements ConnectionsRepository {
  const DemoConnectionsRepository();

  /// There is no bank to log in to in demo mode: the "login page" is the deep link the API sends back on success.
  static final demoResult = Uri.parse('financeshub://connections/result?status=success&synced=true');

  @override
  Future<Uri> startLink(String bankId) async => demoResult;

  @override
  Future<Uri> startRenewal(String connectionId) async => demoResult;

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
