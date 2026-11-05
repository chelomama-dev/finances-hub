import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/dates.dart';
import '../../../core/widgets/states.dart';
import '../data/transactions.dart';
import 'transactions_providers.dart';

/// Movimientos: every bank's transactions together, newest first, with filters and infinite scroll.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  TransactionFilter _filter = const TransactionFilter();

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(transactionsProvider(_filter));

    return Scaffold(
      appBar: AppBar(title: const Text('Movimientos')),
      body: Column(
        children: [
          _Filters(filter: _filter, onChanged: (filter) => setState(() => _filter = filter)),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(transactionsProvider(_filter).future),
              child: AsyncBody(
                value: transactions,
                onRetry: () => ref.invalidate(transactionsProvider(_filter)),
                data: (state) => state.items.isEmpty
                    ? const EmptyView(message: 'No hay movimientos con estos filtros.')
                    : _TransactionList(
                        state: state,
                        onLoadMore: () => ref.read(transactionsProvider(_filter).notifier).loadMore(),
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
    final items = state.items;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 400) onLoadMore();
        return false;
      },
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length + 1,
        separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (context, index) => index == items.length
            ? _Footer(state: state, onLoadMore: onLoadMore)
            : TransactionRow(transaction: items[index]),
      ),
    );
  }
}

/// One line per transaction: a green dot for income or a red one for an expense, the description cut with "…", the
/// date, the amount, and the bank's badge when the row is wide enough for it.
class TransactionRow extends StatelessWidget {
  const TransactionRow({super.key, required this.transaction});

  /// Below this width the bank's badge is left out, so the description keeps room to be read.
  static const minWidthForBank = 340.0;

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final dotColor = transaction.isIncome
        ? (dark ? Colors.green.shade300 : Colors.green.shade700)
        : (dark ? Colors.red.shade300 : Colors.red.shade700);
    final pending = transaction.status == TransactionStatus.pending;

    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Semantics(
              label: transaction.isIncome ? 'Ingreso' : 'Gasto',
              child: DecoratedBox(
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                child: const SizedBox.square(dimension: 10),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.description ?? 'Sin descripción',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                  Text(
                    [rowDate(transaction.bookingDate), if (pending) 'Pendiente'].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(transaction.amount.format(), style: theme.textTheme.titleMedium),
            if (constraints.maxWidth >= minWidthForBank) ...[
              const SizedBox(width: 12),
              BankBadge(bank: transaction.bank),
            ],
          ],
        ),
      ),
    );
  }
}

/// A bank's "icon": its initials in a circle with a colour of its own. No logos, which are the banks' trademarks.
class BankBadge extends StatelessWidget {
  const BankBadge({super.key, required this.bank});

  final TransactionBank bank;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (bank.id) {
      'caja-rural-navarra' => (scheme.primaryContainer, scheme.onPrimaryContainer),
      'trade-republic' => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      _ => (scheme.secondaryContainer, scheme.onSecondaryContainer),
    };

    return Tooltip(
      message: bank.name,
      child: CircleAvatar(
        radius: 14,
        backgroundColor: background,
        child: Text(
          bankInitials(bank.name),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: foreground, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// "Caja Rural de Navarra" → "CR", "Trade Republic" → "TR": the first letters of the first two words that aren't
/// short connectors like "de".
String bankInitials(String name) {
  final words = name.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
  if (words.isEmpty) return name.isEmpty ? '?' : name[0].toUpperCase();
  return words.take(2).map((w) => w[0].toUpperCase()).join();
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
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const SizedBox(height: 32);
  }
}
