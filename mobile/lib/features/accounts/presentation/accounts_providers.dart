import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/accounts_repository.dart';
import '../data/bank_accounts.dart';

final bankAccountsProvider = FutureProvider.autoDispose.family<BankAccounts, String>(
  (ref, bankId) => ref.watch(accountsRepositoryProvider).getBankAccounts(bankId),
);
