import 'package:json_annotation/json_annotation.dart';

import '../../../core/connection_status.dart';

part 'connections.g.dart';

/// `GET /api/connections` (docs/api.md → "List connections").
@JsonSerializable(createToJson: false)
class ConnectionList {
  const ConnectionList({required this.items});

  factory ConnectionList.fromJson(Map<String, dynamic> json) => _$ConnectionListFromJson(json);

  final List<Connection> items;

  /// Known banks that do not have a connection yet.
  List<LinkableBank> get unlinkedBanks {
    final linked = items.map((c) => c.bankId).toSet();
    return [
      for (final bank in LinkableBank.all)
        if (!linked.contains(bank.id)) bank,
    ];
  }
}

@JsonSerializable(createToJson: false)
class Connection {
  const Connection({
    required this.id,
    required this.bankId,
    required this.bankName,
    required this.status,
    required this.expiresAt,
  });

  factory Connection.fromJson(Map<String, dynamic> json) => _$ConnectionFromJson(json);

  final String id;
  final String bankId;
  final String bankName;

  @connectionStatusUnknown
  final ConnectionStatus status;

  final DateTime expiresAt;
}

/// `POST /api/connections` and `POST /api/connections/{connectionId}/renew` (docs/api.md → "Link a bank").
@JsonSerializable(createToJson: false)
class AuthorizationLink {
  const AuthorizationLink({required this.authorizationUrl});

  factory AuthorizationLink.fromJson(Map<String, dynamic> json) => _$AuthorizationLinkFromJson(json);

  final Uri authorizationUrl;
}

/// Banks the API accepts in `POST /api/connections` (docs/api.md → "Link a bank").
class LinkableBank {
  const LinkableBank({required this.id, required this.name});

  final String id;
  final String name;

  static const all = [
    LinkableBank(id: 'caja-rural-navarra', name: 'Caja Rural de Navarra'),
    LinkableBank(id: 'trade-republic', name: 'Trade Republic'),
  ];
}

/// What `financeshub://connections/result` says about a link (docs/api.md → "Link a bank").
enum LinkOutcome {
  synced,
  linkedNotSynced,
  cancelled,
  denied,
  failed;

  static LinkOutcome fromQuery(Map<String, String> query) {
    if (query['status'] == 'success') return query['synced'] == 'true' ? synced : linkedNotSynced;
    return switch (query['reason']) {
      'cancelled' => cancelled,
      'denied' => denied,
      _ => failed,
    };
  }

  bool get linked => this == synced || this == linkedNotSynced;
}
