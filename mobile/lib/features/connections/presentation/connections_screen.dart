import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/dates.dart';
import '../../../core/widgets/states.dart';
import 'connections_providers.dart';

/// Conexiones: each linked bank with its consent status and when it expires.
class ConnectionsScreen extends ConsumerWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(connectionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Conexiones')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(connectionsProvider.future),
        child: AsyncBody(
          value: connections,
          onRetry: () => ref.invalidate(connectionsProvider),
          data: (list) => list.items.isEmpty
              ? const EmptyView(message: 'Aún no hay ningún banco vinculado.', icon: Icons.account_balance_outlined)
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final connection in list.items)
                      Card(
                        child: ListTile(
                          leading: Icon(
                            connection.status.needsAttention ? Icons.warning_amber : Icons.check_circle_outline,
                            color: connection.status.needsAttention ? Theme.of(context).colorScheme.error : null,
                          ),
                          title: Text(connection.bankName),
                          subtitle: Text('${connection.status.label} · hasta el ${shortDate(connection.expiresAt)}'),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
