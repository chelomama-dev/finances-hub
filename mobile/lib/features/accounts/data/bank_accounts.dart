import 'package:json_annotation/json_annotation.dart';

import '../../../core/money.dart';

part 'bank_accounts.g.dart';

/// `GET /api/banks/{bankId}/accounts` (docs/api.md → "List a bank's accounts").
@JsonSerializable(createToJson: false)
class BankAccounts {
  const BankAccounts({required this.bank, required this.accounts});

  factory BankAccounts.fromJson(Map<String, dynamic> json) => _$BankAccountsFromJson(json);

  final Bank bank;
  final List<Account> accounts;
}

@JsonSerializable(createToJson: false)
class Bank {
  const Bank({required this.id, required this.name});

  factory Bank.fromJson(Map<String, dynamic> json) => _$BankFromJson(json);

  final String id;
  final String name;
}

@JsonSerializable(createToJson: false)
@MoneyConverter()
class Account {
  const Account({required this.id, required this.name, required this.maskedIban, required this.balance});

  factory Account.fromJson(Map<String, dynamic> json) => _$AccountFromJson(json);

  final String id;

  /// `null` when the bank sends none.
  final String? name;

  /// `ES12 **** 4567`; `null` for accounts without IBAN.
  final String? maskedIban;

  final Money balance;

  String get displayName => name ?? maskedIban ?? 'Cuenta';
}
