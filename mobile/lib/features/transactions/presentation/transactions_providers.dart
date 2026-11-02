import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/transactions.dart';
import '../data/transactions_repository.dart';

/// Which list: an account with a filter. A new filter is a new list, read from its first page.
typedef TransactionsQuery = ({String accountId, TransactionFilter filter});

class TransactionsState {
  const TransactionsState({required this.items, required this.nextCursor, this.loadingMore = false, this.loadMoreError});

  final List<Transaction> items;
  final String? nextCursor;
  final bool loadingMore;

  /// The last attempt to load the next page failed; the items read so far stay.
  final Object? loadMoreError;

  bool get hasMore => nextCursor != null;

  TransactionsState copyWith({
    List<Transaction>? items,
    String? Function()? nextCursor,
    bool? loadingMore,
    Object? Function()? loadMoreError,
  }) => TransactionsState(
    items: items ?? this.items,
    nextCursor: nextCursor != null ? nextCursor() : this.nextCursor,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: loadMoreError != null ? loadMoreError() : this.loadMoreError,
  );
}

final transactionsProvider = AsyncNotifierProvider.autoDispose
    .family<TransactionsNotifier, TransactionsState, TransactionsQuery>(TransactionsNotifier.new);

/// The first page on build, then the next ones as the list scrolls to the end.
class TransactionsNotifier extends AsyncNotifier<TransactionsState> {
  TransactionsNotifier(this.query);

  final TransactionsQuery query;

  TransactionsRepository get _repository => ref.read(transactionsRepositoryProvider);

  @override
  Future<TransactionsState> build() async {
    final page = await ref
        .watch(transactionsRepositoryProvider)
        .getTransactions(query.accountId, filter: query.filter);
    return TransactionsState(items: page.items, nextCursor: page.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;

    state = AsyncData(current.copyWith(loadingMore: true, loadMoreError: () => null));
    try {
      final page = await _repository.getTransactions(query.accountId, filter: query.filter, cursor: current.nextCursor);
      if (!ref.mounted) return;
      state = AsyncData(
        current.copyWith(items: [...current.items, ...page.items], nextCursor: () => page.nextCursor, loadingMore: false),
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: () => e));
    }
  }
}
