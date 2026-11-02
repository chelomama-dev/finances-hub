import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/summary.dart';
import '../data/summary_repository.dart';

final summaryProvider = FutureProvider.autoDispose<Summary>((ref) => ref.watch(summaryRepositoryProvider).getSummary());
