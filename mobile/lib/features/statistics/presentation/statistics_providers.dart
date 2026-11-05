import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/statistics.dart';
import '../data/statistics_repository.dart';

/// The statistics of a period, counted back from today.
final statisticsProvider = FutureProvider.autoDispose.family<Statistics, StatisticsPeriod>((ref, period) {
  final range = period.range(DateTime.now());
  return ref.watch(statisticsRepositoryProvider).getStatistics(from: range.from, to: range.to);
});
