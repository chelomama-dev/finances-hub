import 'package:json_annotation/json_annotation.dart';

import '../../../core/connection_status.dart';

part 'connections.g.dart';

/// `GET /api/connections` (docs/api.md → "List connections").
@JsonSerializable(createToJson: false)
class ConnectionList {
  const ConnectionList({required this.items});

  factory ConnectionList.fromJson(Map<String, dynamic> json) => _$ConnectionListFromJson(json);

  final List<Connection> items;
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
