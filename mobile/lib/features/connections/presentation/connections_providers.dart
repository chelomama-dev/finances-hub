import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/connections.dart';
import '../data/connections_repository.dart';

final connectionsProvider = FutureProvider.autoDispose<ConnectionList>(
  (ref) => ref.watch(connectionsRepositoryProvider).getConnections(),
);
