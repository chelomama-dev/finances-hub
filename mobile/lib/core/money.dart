import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:json_annotation/json_annotation.dart';

/// An amount in a currency. The amount is a [Decimal], never a `double`, so cents are exact.
@immutable
class Money {
  const Money(this.amount, this.currency);

  final Decimal amount;

  /// ISO 4217 code, as the API sends it (`EUR`).
  final String currency;

  /// `{ "amount": "-23.40", "currency": "EUR" }`, as in docs/api.md.
  factory Money.fromJson(Map<String, dynamic> json) =>
      Money(Decimal.parse(json['amount'] as String), json['currency'] as String);

  Map<String, dynamic> toJson() => {'amount': amount.toString(), 'currency': currency};

  bool get isNegative => amount < Decimal.zero;

  /// Spanish format with the currency's symbol: `1.234,56 €`, `-23,40 €`.
  ///
  /// Formatted by hand from the decimal digits, because `NumberFormat` works with doubles; only the symbol comes
  /// from intl.
  String format() {
    final fixed = amount.round(scale: 2).abs().toStringAsFixed(2);
    final [whole, cents] = fixed.split('.');

    final grouped = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) grouped.write('.');
      grouped.write(whole[i]);
    }

    final symbol = NumberFormat.simpleCurrency(locale: 'es_ES', name: currency).currencySymbol;
    return '${isNegative ? '-' : ''}$grouped,$cents $symbol';
  }

  @override
  bool operator ==(Object other) => other is Money && other.amount == amount && other.currency == currency;

  @override
  int get hashCode => Object.hash(amount, currency);

  @override
  String toString() => '$amount $currency';
}

/// Lets json_serializable read and write [Money] fields.
class MoneyConverter implements JsonConverter<Money, Map<String, dynamic>> {
  const MoneyConverter();

  @override
  Money fromJson(Map<String, dynamic> json) => Money.fromJson(json);

  @override
  Map<String, dynamic> toJson(Money money) => money.toJson();
}
