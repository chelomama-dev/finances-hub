import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/dates.dart';
import '../../../core/widgets/states.dart';
import '../data/connections.dart';
import 'connections_providers.dart';

/// Conexiones: each linked bank with its consent status and when it expires, "Reconectar" when it needs it, and
/// "Vincular banco" for the banks that aren't linked yet.
class ConnectionsScreen extends ConsumerStatefulWidget {
  const ConnectionsScreen({super.key, this.showLinkOutcome = false});

  /// Opened by the deep link after a bank login: shows how it went.
  final bool showLinkOutcome;

  @override
  ConsumerState<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends ConsumerState<ConnectionsScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final connections = ref.watch(connectionsProvider);
    final unlinked = connections.value?.unlinkedBanks ?? const [];
    final outcome = widget.showLinkOutcome ? ref.watch(linkOutcomeProvider) : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Conexiones')),
      floatingActionButton: unlinked.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : () => _chooseBank(unlinked),
              icon: const Icon(Icons.add_link),
              label: const Text('Vincular banco'),
            ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (outcome != null)
            _OutcomeBanner(outcome: outcome, onClose: () => ref.read(linkOutcomeProvider.notifier).clear()),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(connectionsProvider.future),
              child: AsyncBody(
                value: connections,
                onRetry: () => ref.invalidate(connectionsProvider),
                data: (list) => list.items.isEmpty
                    ? const EmptyView(
                        message: 'Aún no hay ningún banco vinculado.',
                        icon: Icons.account_balance_outlined,
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        // Room at the end so the button never covers the last card
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                        children: [for (final connection in list.items) _connectionCard(connection)],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _connectionCard(Connection connection) {
    final needsAttention = connection.status.needsAttention;
    return Card(
      child: ListTile(
        leading: Icon(
          needsAttention ? Icons.warning_amber : Icons.check_circle_outline,
          color: needsAttention ? Theme.of(context).colorScheme.error : null,
        ),
        title: Text(connection.bankName),
        subtitle: Text('${connection.status.label} · hasta el ${shortDate(connection.expiresAt)}'),
        trailing: needsAttention
            ? TextButton(
                onPressed: _busy ? null : () => _openBankLogin((linker) => linker.renew(connection.id)),
                child: const Text('Reconectar'),
              )
            : null,
      ),
    );
  }

  Future<void> _chooseBank(List<LinkableBank> banks) async {
    final bank = await showModalBottomSheet<LinkableBank>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('¿Qué banco quieres vincular?', style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final bank in banks)
              ListTile(
                leading: const Icon(Icons.account_balance_outlined),
                title: Text(bank.name),
                onTap: () => Navigator.of(context).pop(bank),
              ),
          ],
        ),
      ),
    );
    if (bank != null) await _openBankLogin((linker) => linker.link(bank.id));
  }

  /// Asks the API for the bank's login page and opens it in the browser. The app comes back through the deep link.
  Future<void> _openBankLogin(Future<bool> Function(ConnectionLinker linker) start) async {
    final messenger = ScaffoldMessenger.of(context);
    ref.read(linkOutcomeProvider.notifier).clear();
    setState(() => _busy = true);

    String? problem;
    try {
      if (!await start(ref.read(connectionLinkerProvider))) problem = 'No se ha podido abrir el navegador.';
    } catch (e) {
      problem = errorMessage(e);
    }

    if (!mounted) return;
    setState(() => _busy = false);
    if (problem != null) messenger.showSnackBar(SnackBar(content: Text(problem)));
  }
}

class _OutcomeBanner extends StatelessWidget {
  const _OutcomeBanner({required this.outcome, required this.onClose});

  final LinkOutcome outcome;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ok = outcome.linked;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      color: ok ? colors.primaryContainer : colors.errorContainer,
      child: ListTile(
        leading: Icon(
          ok ? Icons.check_circle_outline : Icons.error_outline,
          color: ok ? colors.onPrimaryContainer : colors.onErrorContainer,
        ),
        title: Text(
          _message(outcome),
          style: TextStyle(color: ok ? colors.onPrimaryContainer : colors.onErrorContainer),
        ),
        trailing: IconButton(tooltip: 'Cerrar', icon: const Icon(Icons.close), onPressed: onClose),
      ),
    );
  }

  static String _message(LinkOutcome outcome) => switch (outcome) {
    LinkOutcome.synced => 'Banco vinculado. Sus datos ya están cargados.',
    LinkOutcome.linkedNotSynced =>
      'Banco vinculado, pero no se han podido cargar sus datos. Se reintentará en la próxima sincronización.',
    LinkOutcome.cancelled => 'Has cancelado la vinculación.',
    LinkOutcome.denied => 'El banco ha denegado el acceso.',
    LinkOutcome.failed => 'No se ha podido vincular el banco. Inténtalo de nuevo.',
  };
}
