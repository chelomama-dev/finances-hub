import 'package:json_annotation/json_annotation.dart';

import '../../../core/connection_status.dart';
import '../../../core/money.dart';

part 'summary.g.dart';

/// `GET /api/summary` (docs/api.md → "Get the summary").
@JsonSerializable(createToJson: false)
@MoneyConverter()
class Summary {
  const Summary({required this.totalBalance, required this.lastSyncedAt, required this.banks});

  factory Summary.fromJson(Map<String, dynamic> json) => _$SummaryFromJson(json);

  final Money totalBalance;

  /// `null` if no sync has run yet.
  final DateTime? lastSyncedAt;

  final List<BankSummary> banks;

  bool get needsAttention => banks.any((b) => b.connectionStatus.needsAttention);
}

@JsonSerializable(createToJson: false)
@MoneyConverter()
class BankSummary {
  const BankSummary({required this.id, required this.name, required this.balance, required this.connectionStatus});

  factory BankSummary.fromJson(Map<String, dynamic> json) => _$BankSummaryFromJson(json);

  /// The bank's code (`caja-rural-navarra`).
  final String id;
  final String name;
  final Money balance;

  @connectionStatusUnknown
  final ConnectionStatus connectionStatus;
}
