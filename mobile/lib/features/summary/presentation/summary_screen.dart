import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/dates.dart';
import '../../../core/widgets/states.dart';
import '../data/summary.dart';
import 'summary_providers.dart';

/// Inicio: the total balance, one card per bank, and a warning when a consent needs renewing.
class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(summaryProvider);
    final hasAuth = ref.watch(authenticatorProvider) != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finances Hub'),
        actions: [
          IconButton(
            tooltip: 'Conexiones',
            icon: const Icon(Icons.account_balance_outlined),
            onPressed: () => context.push('/connections'),
          ),
          if (hasAuth)
            IconButton(
              tooltip: 'Cerrar sesión',
              icon: const Icon(Icons.logout),
              onPressed: () => _confirmSignOut(context, ref),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(summaryProvider.future),
        child: AsyncBody(
          value: summary,
          onRetry: () => ref.invalidate(summaryProvider),
          data: (summary) => summary.banks.isEmpty
              ? EmptyView(
                  message: 'Aún no hay ningún banco vinculado.',
                  icon: Icons.account_balance_outlined,
                  action: FilledButton(
                    onPressed: () => context.push('/connections'),
                    child: const Text('Vincular banco'),
                  ),
                )
              : _SummaryList(summary: summary),
        ),
      ),
    );
  }
}

Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('¿Cerrar sesión?'),
      content: const Text('Tendrás que volver a iniciar sesión con tu cuenta de Microsoft.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cerrar sesión')),
      ],
    ),
  );
  if (confirmed ?? false) await ref.read(authProvider.notifier).signOut();
}

class _SummaryList extends StatelessWidget {
  const _SummaryList({required this.summary});

  final Summary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastSynced = summary.lastSyncedAt;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        if (summary.needsAttention)
          Card(
            color: theme.colorScheme.errorContainer,
            child: ListTile(
              leading: Icon(Icons.warning_amber, color: theme.colorScheme.onErrorContainer),
              title: Text(
                'Hay un banco que necesita reconectarse',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
              trailing: Icon(Icons.chevron_right, color: theme.colorScheme.onErrorContainer),
              onTap: () => context.push('/connections'),
            ),
          ),
        const SizedBox(height: 16),
        Text('Saldo total', style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          summary.totalBalance.format(),
          style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          lastSynced == null ? 'Aún no se ha sincronizado' : 'Actualizado ${timeAgo(lastSynced)}',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        for (final bank in summary.banks)
          Card(
            child: ListTile(
              title: Text(bank.name),
              subtitle: bank.connectionStatus.needsAttention ? Text(bank.connectionStatus.label) : null,
              trailing: Text(bank.balance.format(), style: theme.textTheme.titleMedium),
              onTap: () => context.push('/banks/${bank.id}'),
            ),
          ),
      ],
    );
  }
}
