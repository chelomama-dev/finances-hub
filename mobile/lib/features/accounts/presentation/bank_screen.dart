import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/states.dart';
import 'accounts_providers.dart';

/// Banco: the bank's accounts with their balances.
class BankScreen extends ConsumerWidget {
  const BankScreen({super.key, required this.bankId});

  final String bankId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(bankAccountsProvider(bankId));

    return Scaffold(
      appBar: AppBar(title: Text(accounts.value?.bank.name ?? 'Banco')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(bankAccountsProvider(bankId).future),
        child: AsyncBody(
          value: accounts,
          onRetry: () => ref.invalidate(bankAccountsProvider(bankId)),
          data: (data) => data.accounts.isEmpty
              ? const EmptyView(message: 'Este banco no tiene cuentas vinculadas.')
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final account in data.accounts)
                      Card(
                        child: ListTile(
                          title: Text(account.displayName),
                          subtitle: account.name != null && account.maskedIban != null
                              ? Text(account.maskedIban!)
                              : null,
                          trailing: Text(account.balance.format(), style: Theme.of(context).textTheme.titleMedium),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
