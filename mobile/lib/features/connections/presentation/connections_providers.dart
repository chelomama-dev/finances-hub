import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/connections.dart';
import '../data/connections_repository.dart';

final connectionsProvider = FutureProvider.autoDispose<ConnectionList>(
  (ref) => ref.watch(connectionsRepositoryProvider).getConnections(),
);

/// The result of the last bank login, from the deep link, until the owner closes it or starts another one.
final linkOutcomeProvider = NotifierProvider<LinkOutcomeNotifier, LinkOutcome?>(LinkOutcomeNotifier.new);

class LinkOutcomeNotifier extends Notifier<LinkOutcome?> {
  @override
  LinkOutcome? build() => null;

  void show(LinkOutcome outcome) => state = outcome;

  void clear() => state = null;
}

/// Opens a URL and says whether it could.
typedef BrowserLauncher = Future<bool> Function(Uri url);

/// The external browser, never a WebView: some banks block logins inside one (docs/api.md → "Link a bank").
final browserLauncherProvider = Provider<BrowserLauncher>(
  (_) => (url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return false;
    }
  },
);

final connectionLinkerProvider = Provider<ConnectionLinker>(
  (ref) => ConnectionLinker(ref.watch(connectionsRepositoryProvider), ref.watch(browserLauncherProvider)),
);

/// Starts linking or reconnecting a bank and opens its login page. The result comes back later, through the
/// `financeshub://connections/result` deep link (see router.dart).
class ConnectionLinker {
  const ConnectionLinker(this._repository, this._openBrowser);

  final ConnectionsRepository _repository;
  final BrowserLauncher _openBrowser;

  /// `false` if the browser couldn't be opened. API errors are thrown as `ApiException`.
  Future<bool> link(String bankId) async => _openBrowser(await _repository.startLink(bankId));

  Future<bool> renew(String connectionId) async => _openBrowser(await _repository.startRenewal(connectionId));
}
