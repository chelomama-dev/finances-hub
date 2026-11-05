import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../../core/money.dart';

part 'transactions.g.dart';

/// A page of `GET /api/transactions` (docs/api.md → "List transactions"): every bank's transactions together.
@JsonSerializable(createToJson: false)
class TransactionPage {
  const TransactionPage({required this.items, required this.nextCursor});

  factory TransactionPage.fromJson(Map<String, dynamic> json) => _$TransactionPageFromJson(json);

  final List<Transaction> items;

  /// `null` on the last page.
  final String? nextCursor;
}

/// The IDs of recent transactions change on every sync: use them as list keys within a response, never store them.
@JsonSerializable(createToJson: false)
@MoneyConverter()
class Transaction {
  const Transaction({
    required this.id,
    required this.bookingDate,
    required this.amount,
    required this.description,
    required this.counterparty,
    required this.status,
    required this.bank,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) => _$TransactionFromJson(json);

  final String id;

  /// A date with no time (`2026-11-01`), read as local midnight.
  final DateTime bookingDate;

  /// Signed: negative is an expense.
  final Money amount;

  /// `null` when the bank sends none (Trade Republic never does).
  final String? description;
  final String? counterparty;

  @JsonKey(unknownEnumValue: TransactionStatus.booked)
  final TransactionStatus status;

  /// The bank of the transaction's account.
  final TransactionBank bank;

  bool get isIncome => !amount.isNegative;
}

enum TransactionStatus { booked, pending }

@JsonSerializable(createToJson: false)
class TransactionBank {
  const TransactionBank({required this.id, required this.name});

  factory TransactionBank.fromJson(Map<String, dynamic> json) => _$TransactionBankFromJson(json);

  /// The bank's code (`caja-rural-navarra`), as in the summary.
  final String id;
  final String name;
}

enum TransactionDirection {
  income,
  expense;

  String get label => switch (this) {
    income => 'Ingresos',
    expense => 'Gastos',
  };
}

/// What the owner filters by. A record-like value class, so two equal filters share one provider.
@immutable
class TransactionFilter {
  const TransactionFilter({this.range, this.direction});

  final DateTimeRange? range;

  /// `null` for both.
  final TransactionDirection? direction;

  TransactionFilter copyWith({DateTimeRange? Function()? range, TransactionDirection? Function()? direction}) =>
      TransactionFilter(
        range: range != null ? range() : this.range,
        direction: direction != null ? direction() : this.direction,
      );

  @override
  bool operator ==(Object other) => other is TransactionFilter && other.range == range && other.direction == direction;

  @override
  int get hashCode => Object.hash(range, direction);
}
