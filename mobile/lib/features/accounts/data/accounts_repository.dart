import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/config.dart';
import '../../../core/money.dart';
import 'bank_accounts.dart';

abstract interface class AccountsRepository {
  Future<BankAccounts> getBankAccounts(String bankId);
}

final accountsRepositoryProvider = Provider<AccountsRepository>(
  (ref) => ref.watch(appConfigProvider).demo
      ? const DemoAccountsRepository()
      : ApiAccountsRepository(ref.watch(apiClientProvider)),
);

class ApiAccountsRepository implements AccountsRepository {
  const ApiAccountsRepository(this._api);

  final ApiClient _api;

  @override
  Future<BankAccounts> getBankAccounts(String bankId) async =>
      BankAccounts.fromJson(await _api.get('/api/banks/${Uri.encodeComponent(bankId)}/accounts'));
}

/// Made-up data, shaped like the example in docs/api.md.
class DemoAccountsRepository implements AccountsRepository {
  const DemoAccountsRepository();

  static const cajaRuralAccountId = 'demo-account-caja-rural';
  static const tradeRepublicAccountId = 'demo-account-trade-republic';

  @override
  Future<BankAccounts> getBankAccounts(String bankId) async => switch (bankId) {
    'caja-rural-navarra' => BankAccounts(
      bank: const Bank(id: 'caja-rural-navarra', name: 'Caja Rural de Navarra'),
      accounts: [
        Account(
          id: cajaRuralAccountId,
          name: 'Cuenta Corriente',
          maskedIban: 'ES12 **** 4567',
          balance: Money(Decimal.parse('3120.80'), 'EUR'),
        ),
      ],
    ),
    'trade-republic' => BankAccounts(
      bank: const Bank(id: 'trade-republic', name: 'Trade Republic'),
      accounts: [
        Account(
          id: tradeRepublicAccountId,
          name: null,
          maskedIban: 'ES34 **** 8901',
          balance: Money(Decimal.parse('9752.65'), 'EUR'),
        ),
      ],
    ),
    _ => throw const ApiException('No se ha encontrado.', statusCode: 404),
  };
}
