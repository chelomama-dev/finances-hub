import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/dates.dart';
import '../../../core/widgets/states.dart';
import '../data/transactions.dart';
import 'transactions_providers.dart';

/// Movimientos: an account's transactions, newest first and grouped by day, with filters and infinite scroll.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key, required this.accountId, this.accountName});

  final String accountId;
  final String? accountName;

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  TransactionFilter _filter = const TransactionFilter();

  TransactionsQuery get _query => (accountId: widget.accountId, filter: _filter);

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(transactionsProvider(_query));

    return Scaffold(
      appBar: AppBar(title: Text(widget.accountName ?? 'Movimientos')),
      body: Column(
        children: [
          _Filters(filter: _filter, onChanged: (filter) => setState(() => _filter = filter)),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(transactionsProvider(_query).future),
              child: AsyncBody(
                value: transactions,
                onRetry: () => ref.invalidate(transactionsProvider(_query)),
                data: (state) => state.items.isEmpty
                    ? const EmptyView(message: 'No hay movimientos con estos filtros.')
                    : _TransactionList(
                        state: state,
                        onLoadMore: () => ref.read(transactionsProvider(_query).notifier).loadMore(),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.filter, required this.onChanged});

  final TransactionFilter filter;
  final ValueChanged<TransactionFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final range = filter.range;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<TransactionDirection?>(
            segments: [
              const ButtonSegment(value: null, label: Text('Todos')),
              for (final direction in TransactionDirection.values)
                ButtonSegment(value: direction, label: Text(direction.label)),
            ],
            selected: {filter.direction},
            onSelectionChanged: (selection) => onChanged(filter.copyWith(direction: () => selection.single)),
          ),
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.date_range),
                label: Text(range == null ? 'Todas las fechas' : '${shortDate(range.start)} – ${shortDate(range.end)}'),
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(now.year - 5),
                    lastDate: now,
                    initialDateRange: range,
                  );
                  if (picked != null) onChanged(filter.copyWith(range: () => picked));
                },
              ),
              if (range != null)
                IconButton(
                  tooltip: 'Quitar fechas',
                  icon: const Icon(Icons.close),
                  onPressed: () => onChanged(filter.copyWith(range: () => null)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TransactionList extends StatelessWidget {
  const _TransactionList({required this.state, required this.onLoadMore});

  final TransactionsState state;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    // Day headers and transactions in one flat list, so the list can be built lazily
    final rows = <Object>[];
    DateTime? day;
    for (final transaction in state.items) {
      if (transaction.bookingDate != day) {
        day = transaction.bookingDate;
        rows.add(day);
      }
      rows.add(transaction);
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 400) onLoadMore();
        return false;
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: rows.length + 1,
        itemBuilder: (context, index) {
          if (index == rows.length) return _Footer(state: state, onLoadMore: onLoadMore);
          return switch (rows[index]) {
            DateTime day => _DayHeader(day: day),
            Transaction transaction => _TransactionTile(transaction: transaction),
            _ => const SizedBox.shrink(),
          };
        },
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(dayHeader(day), style: Theme.of(context).textTheme.labelLarge),
  );
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final income = theme.brightness == Brightness.dark ? Colors.green.shade300 : Colors.green.shade700;
    final subtitle = [
      ?transaction.counterparty,
      if (transaction.status == TransactionStatus.pending) 'Pendiente',
    ].join(' · ');

    return ListTile(
      title: Text(transaction.description ?? 'Sin descripción', maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: Text(
        transaction.amount.format(),
        style: theme.textTheme.titleMedium?.copyWith(color: transaction.isIncome ? income : null),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state, required this.onLoadMore});

  final TransactionsState state;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (state.loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(errorMessage(state.loadMoreError!), textAlign: TextAlign.center),
            TextButton(onPressed: onLoadMore, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    if (state.hasMore) {
      return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
    }
    return const SizedBox(height: 32);
  }
}
