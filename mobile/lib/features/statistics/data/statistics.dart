import 'package:decimal/decimal.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../../core/money.dart';

part 'statistics.g.dart';

/// `GET /api/statistics` (docs/api.md → "Get statistics"). Expenses are negative, as in transactions.
@JsonSerializable(createToJson: false)
@MoneyConverter()
class Statistics {
  const Statistics({
    required this.from,
    required this.to,
    required this.income,
    required this.expenses,
    required this.topExpenses,
    required this.otherExpenses,
    required this.days,
  });

  factory Statistics.fromJson(Map<String, dynamic> json) => _$StatisticsFromJson(json);

  /// Dates with no time, read as local midnight.
  final DateTime from;
  final DateTime to;

  final Money income;
  final Money expenses;

  /// Up to 5 descriptions with the largest expenses, largest first.
  final List<ExpenseGroup> topExpenses;

  /// Every other description's expenses: [topExpenses] plus this add up to [expenses].
  final Money otherExpenses;

  /// Only the days with transactions, oldest first.
  final List<DayTotals> days;

  bool get isEmpty => days.isEmpty;
}

@JsonSerializable(createToJson: false)
@MoneyConverter()
class ExpenseGroup {
  const ExpenseGroup({required this.description, required this.amount, required this.count});

  factory ExpenseGroup.fromJson(Map<String, dynamic> json) => _$ExpenseGroupFromJson(json);

  /// `null` groups the transactions without description.
  final String? description;
  final Money amount;
  final int count;
}

@JsonSerializable(createToJson: false)
@MoneyConverter()
class DayTotals {
  const DayTotals({required this.date, required this.income, required this.expenses});

  factory DayTotals.fromJson(Map<String, dynamic> json) => _$DayTotalsFromJson(json);

  final DateTime date;
  final Money income;
  final Money expenses;
}

/// The ranges the screen offers, counted back from today (today included).
enum StatisticsPeriod {
  week(7, bucketDays: 1),
  month(30, bucketDays: 7),
  quarter(90, bucketDays: 15);

  const StatisticsPeriod(this.days, {required this.bucketDays});

  final int days;

  /// How many days each bar of the income and expenses chart adds up.
  final int bucketDays;

  String get label => '$days días';

  /// From `days - 1` days ago to today, as dates with no time.
  ({DateTime from, DateTime to}) range(DateTime today) {
    final to = DateTime(today.year, today.month, today.day);
    return (from: DateTime(to.year, to.month, to.day - (days - 1)), to: to);
  }
}

/// One bar pair of the income and expenses chart: the totals from [start] to [end], both included.
class PeriodTotals {
  const PeriodTotals({required this.start, required this.end, required this.income, required this.expenses});

  final DateTime start;
  final DateTime end;
  final Decimal income;

  /// Positive: how much went out.
  final Decimal expenses;
}

/// Splits [statistics]' range into periods of [bucketDays] counted back from its last day, so the newest bar is
/// always complete and only the oldest one can be shorter. Days without transactions count as zero.
List<PeriodTotals> totalsByPeriod(Statistics statistics, int bucketDays) {
  final from = statistics.from;
  final periods = <PeriodTotals>[];
  var end = statistics.to;
  while (!end.isBefore(from)) {
    final candidate = DateTime(end.year, end.month, end.day - (bucketDays - 1));
    final start = candidate.isBefore(from) ? from : candidate;
    var income = Decimal.zero;
    var expenses = Decimal.zero;
    for (final day in statistics.days) {
      if (day.date.isBefore(start) || day.date.isAfter(end)) continue;
      income += day.income.amount;
      expenses -= day.expenses.amount;
    }
    periods.add(PeriodTotals(start: start, end: end, income: income, expenses: expenses));
    end = DateTime(start.year, start.month, start.day - 1);
  }
  return periods.reversed.toList();
}
