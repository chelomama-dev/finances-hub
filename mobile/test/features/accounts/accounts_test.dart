import 'dart:async';

import 'package:finances_hub/core/api/api_exception.dart';
import 'package:finances_hub/features/accounts/data/accounts_repository.dart';
import 'package:finances_hub/features/accounts/data/bank_accounts.dart';
import 'package:finances_hub/features/accounts/presentation/bank_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

// The example of docs/api.md → "List a bank's accounts", plus an account with no name
const example = {
  'bank': {'id': 'caja-rural-navarra', 'name': 'Caja Rural de Navarra'},
  'accounts': [
    {
      'id': '3f2c8d71-5a0b-4e9f-8c16-b7d2e4a90f55',
      'name': 'Cuenta Corriente',
      'maskedIban': 'ES12 **** 4567',
      'balance': {'amount': '3120.80', 'currency': 'EUR'},
    },
    {
      'id': 'a1',
      'name': null,
      'maskedIban': 'ES34 **** 8901',
      'balance': {'amount': '0.00', 'currency': 'EUR'},
    },
  ],
};

class FakeAccountsRepository implements AccountsRepository {
  FakeAccountsRepository(this.result);

  final Future<BankAccounts> Function(String bankId) result;

  @override
  Future<BankAccounts> getBankAccounts(String bankId) => result(bankId);
}

void main() {
  test('reads the contract example; an account without name shows its IBAN', () {
    final accounts = BankAccounts.fromJson(example);

    expect(accounts.bank.name, 'Caja Rural de Navarra');
    expect(accounts.accounts.first.displayName, 'Cuenta Corriente');
    expect(accounts.accounts.last.displayName, 'ES34 **** 8901');
  });

  test('the repository calls the bank\'s accounts', () async {
    final adapter = FakeAdapter((_) => (200, example));

    await ApiAccountsRepository(fakeApi(adapter)).getBankAccounts('caja-rural-navarra');

    expect(adapter.requests.single.path, '/api/banks/caja-rural-navarra/accounts');
  });

  testWidgets('shows each account', (tester) async {
    await pumpScreen(tester, const BankScreen(bankId: 'caja-rural-navarra'),
        overrides: [accountsRepositoryProvider.overrideWithValue(FakeAccountsRepository((_) async => BankAccounts.fromJson(example)))]);
    await tester.pumpAndSettle();

    expect(find.text('Caja Rural de Navarra'), findsOneWidget);
    expect(find.text('ES12 **** 4567'), findsOneWidget);
    expect(find.text('3.120,80 €'), findsOneWidget);
  });

  testWidgets('empty', (tester) async {
    await pumpScreen(tester, const BankScreen(bankId: 'trade-republic'),
        overrides: [accountsRepositoryProvider.overrideWithValue(FakeAccountsRepository((_) async => BankAccounts.fromJson({...example, 'accounts': []})))]);
    await tester.pumpAndSettle();

    expect(find.text('Este banco no tiene cuentas vinculadas.'), findsOneWidget);
  });

  testWidgets('loading', (tester) async {
    await pumpScreen(tester, const BankScreen(bankId: 'trade-republic'),
        overrides: [accountsRepositoryProvider.overrideWithValue(FakeAccountsRepository((_) => Completer<Never>().future))]);
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('error', (tester) async {
    await pumpScreen(tester, const BankScreen(bankId: 'unknown'),
        overrides: [accountsRepositoryProvider.overrideWithValue(FakeAccountsRepository((_) async => throw const ApiException('No se ha encontrado.', statusCode: 404)))]);
    await tester.pumpAndSettle();

    expect(find.text('No se ha encontrado.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });
}
