import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money.dart';
import '../../../core/widgets/states.dart';
import '../data/statistics.dart';
import 'chart_colors.dart';
import 'statistics_providers.dart';

/// Estadísticas: where the money went (a donut of the descriptions with the most expenses) and income against
/// expenses over time (bars), for the last 7, 30 or 90 days.
class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  StatisticsPeriod _period = StatisticsPeriod.month;

  @override
  Widget build(BuildContext context) {
    final statistics = ref.watch(statisticsProvider(_period));

    return Scaffold(
      appBar: AppBar(title: const Text('Estadísticas')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<StatisticsPeriod>(
                segments: [
                  for (final period in StatisticsPeriod.values) ButtonSegment(value: period, label: Text(period.label)),
                ],
                selected: {_period},
                showSelectedIcon: false,
                onSelectionChanged: (selection) => setState(() => _period = selection.single),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(statisticsProvider(_period).future),
              child: AsyncBody(
                value: statistics,
                onRetry: () => ref.invalidate(statisticsProvider(_period)),
                data: (statistics) => statistics.isEmpty
                    ? const EmptyView(message: 'No hay movimientos en este periodo.', icon: Icons.pie_chart_outline)
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          _ExpensesCard(statistics: statistics),
                          const SizedBox(height: 16),
                          _IncomeExpensesCard(statistics: statistics, period: _period),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The donut: each top description's share of the expenses, the rest as "Otros", and a legend with the amounts.
class _ExpensesCard extends StatelessWidget {
  const _ExpensesCard({required this.statistics});

  final Statistics statistics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ChartColors.of(context);
    final total = -statistics.expenses.amount;

    final slices = [
      for (final (i, group) in statistics.topExpenses.indexed)
        _Slice(group.description ?? 'Sin descripción', -group.amount.amount, colors.series[i]),
      if (statistics.otherExpenses.amount != Decimal.zero)
        _Slice('Otros', -statistics.otherExpenses.amount, colors.other),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('En qué gastas', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            if (slices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No hay gastos en este periodo.')),
              )
            else ...[
              SizedBox(
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        centerSpaceRadius: 64,
                        // A gap of the card's colour between slices, so neighbours never touch
                        sectionsSpace: 2,
                        startDegreeOffset: -90,
                        sections: [
                          for (final slice in slices)
                            PieChartSectionData(
                              // Only the slice's size: the amounts on screen come from the decimals
                              value: slice.amount.toDouble(),
                              color: slice.color,
                              radius: 28,
                              showTitle: false,
                            ),
                        ],
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Gastos', style: theme.textTheme.bodySmall),
                        Text(
                          Money(total, statistics.expenses.currency).format(),
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              for (final slice in slices)
                _LegendRow(
                  color: slice.color,
                  label: slice.label,
                  value: Money(slice.amount, statistics.expenses.currency).format(),
                  share: _share(slice.amount, total),
                ),
            ],
          ],
        ),
      ),
    );
  }

  static String _share(Decimal part, Decimal total) {
    if (total == Decimal.zero) return '';
    final percent = (part * Decimal.fromInt(100) / total).toDecimal(scaleOnInfinitePrecision: 2);
    return '${percent.round().toBigInt()} %';
  }
}

class _Slice {
  const _Slice(this.label, this.amount, this.color);

  final String label;

  /// Positive: how much went out.
  final Decimal amount;
  final Color color;
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.color, required this.label, required this.value, this.share = ''});

  final Color color;
  final String label;
  final String value;
  final String share;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
            child: const SizedBox.square(dimension: 12),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          if (share.isNotEmpty)
            SizedBox(
              width: 48,
              child: Text(
                share,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

/// The bars: income next to expenses, a pair per day (7 días) or per group of days (30 and 90 días).
class _IncomeExpensesCard extends StatelessWidget {
  const _IncomeExpensesCard({required this.statistics, required this.period});

  final Statistics statistics;
  final StatisticsPeriod period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ChartColors.of(context);
    final currency = statistics.income.currency;
    final periods = totalsByPeriod(statistics, period.bucketDays);
    final dayMonth = DateFormat('d/M', 'es_ES');
    final barWidth = periods.length > 5 ? 8.0 : 14.0;

    String label(PeriodTotals p) =>
        period.bucketDays == 1 ? DateFormat.E('es_ES').format(p.start) : dayMonth.format(p.start);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ingresos y gastos', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _LegendRow(color: colors.income, label: 'Ingresos', value: statistics.income.format()),
            _LegendRow(
              color: colors.expenses,
              label: 'Gastos',
              value: Money(-statistics.expenses.amount, statistics.expenses.currency).format(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        getTitlesWidget: (value, meta) =>
                            // The top of the axis is the largest bar, not a round step: its label would overlap
                            // the step below
                            value == meta.max && value % meta.appliedInterval != 0
                            ? const SizedBox.shrink()
                            : SideTitleWidget(
                                meta: meta,
                                child: Text(_compact(value), style: theme.textTheme.labelSmall),
                              ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          // With many bars only every other label fits
                          if (i < 0 || i >= periods.length || (periods.length > 5 && i.isOdd)) {
                            return const SizedBox.shrink();
                          }
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(label(periods[i]), style: theme.textTheme.labelSmall),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final p = periods[groupIndex];
                        final amount = rodIndex == 0 ? p.income : p.expenses;
                        final when = p.start == p.end
                            ? dayMonth.format(p.start)
                            : '${dayMonth.format(p.start)}–${dayMonth.format(p.end)}';
                        return BarTooltipItem(
                          '${rodIndex == 0 ? 'Ingresos' : 'Gastos'} · $when\n${Money(amount, currency).format()}',
                          TextStyle(color: theme.colorScheme.onInverseSurface, fontSize: 12),
                        );
                      },
                    ),
                  ),
                  barGroups: [
                    for (final (i, p) in periods.indexed)
                      BarChartGroupData(
                        x: i,
                        barsSpace: 2,
                        barRods: [_rod(p.income, colors.income, barWidth), _rod(p.expenses, colors.expenses, barWidth)],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Only the bar's height: the amounts on screen come from the decimals
  static BarChartRodData _rod(Decimal amount, Color color, double width) => BarChartRodData(
    toY: amount.toDouble(),
    color: color,
    width: width,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
  );

  /// Axis labels: "850", "1,2 mil", "15 mil".
  static String _compact(double value) => NumberFormat.compact(locale: 'es_ES').format(value);
}
