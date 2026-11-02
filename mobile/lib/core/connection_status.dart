import 'package:json_annotation/json_annotation.dart';

/// A bank's consent, as `GET /api/summary` and `GET /api/connections` report it.
enum ConnectionStatus {
  active,
  expiring,
  expired;

  /// The owner should reconnect the bank.
  bool get needsAttention => this != active;

  String get label => switch (this) {
    active => 'Activa',
    expiring => 'Caduca pronto',
    expired => 'Caducada',
  };
}

/// A status the app doesn't know yet is shown as expired, so it asks for attention rather than hiding a problem.
const connectionStatusUnknown = JsonKey(unknownEnumValue: ConnectionStatus.expired);
