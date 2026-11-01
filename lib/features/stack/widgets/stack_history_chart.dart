/// The cumulative-sats history chart, its card, and the period chips that
/// select the range.
library;

import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/utils/sat_converter.dart';
import 'period_chip.dart';
import 'stack_period.dart';

class HistoryChartCard extends StatelessWidget {
  const HistoryChartCard({
    super.key,
    required this.history,
    required this.period,
    required this.onPeriodChanged,
  });

  /// Every month's closing balance — see `StackStats.history` — so the
  /// window below always starts from the balance carried into it, and a
  /// stack that sat still has a flat line rather than "Not enough data".
  final Map<DateTime, int> history;
  final StackPeriod period;
  final ValueChanged<StackPeriod> onPeriodChanged;

  List<MapEntry<DateTime, int>> _filtered() {
    final entries =
        history.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final now = DateTime.now();
    final cutoff = switch (period) {
      StackPeriod.threeM => DateTime(now.year, now.month - 2),
      StackPeriod.sixM => DateTime(now.year, now.month - 5),
      StackPeriod.oneY => DateTime(now.year - 1, now.month),
      StackPeriod.all => DateTime(2009),
    };
    return entries.where((e) => !e.key.isBefore(cutoff)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
          child: Column(
            children: [
              // Period chips
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final p in StackPeriod.values)
                    PeriodChip(
                      label: p.label,
                      selected: period == p,
                      onTap: () => onPeriodChanged(p),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Chart
              SizedBox(
                height: 160,
                child:
                    filtered.length < 2
                        ? Center(
                          child: Text(
                            'Not enough data for this period',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: context.textSecondary,
                            ),
                          ),
                        )
                        : StackLineChart(entries: filtered),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StackLineChart extends StatelessWidget {
  const StackLineChart({super.key, required this.entries});

  /// One per calendar month, in order, so the index is time.
  final List<MapEntry<DateTime, int>> entries;

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (int i = 0; i < entries.length; i++)
        FlSpot(i.toDouble(), entries[i].value.toDouble()),
    ];
    final maxY = entries.map((e) => e.value).reduce(max).toDouble();
    final minY = entries.map((e) => e.value).reduce(min).toDouble();
    final yPad = max((maxY - minY) * 0.1, 1.0);

    return Semantics(
      // The chart itself says nothing to a screen reader: give it the
      // numbers a sighted user reads off it.
      label:
          'Stack history: from ${SatConverter.formatSats(entries.first.value)} '
          'to ${SatConverter.formatSats(entries.last.value)} sats, '
          'peaking at ${SatConverter.formatSats(maxY.round())}',
      excludeSemantics: true,
      child: LineChart(
        LineChartData(
          minY: max(0, minY - yPad),
          maxY: maxY + yPad,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.3,
              color: AppColors.bitcoinOrange,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    AppColors.bitcoinOrange.withAlpha(60),
                    AppColors.bitcoinOrange.withAlpha(0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            // 5 %-opacity white was invisible on a light background.
            getDrawingHorizontalLine:
                (_) => FlLine(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(24),
                  strokeWidth: 0.5,
                ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                getTitlesWidget:
                    (value, _) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        _abbrevSats(value.toInt()),
                        style: TextStyle(
                          fontFamily: 'RobotoMono',
                          fontSize: 9,
                          color: context.textSecondary,
                        ),
                      ),
                    ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: max(1, (entries.length / 4).ceilToDouble()),
                getTitlesWidget: (value, _) {
                  final i = value.toInt();
                  if (i < 0 || i >= entries.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      DateFormat('MMM yy').format(entries[i].key),
                      style: TextStyle(
                        fontSize: 9,
                        color: context.textSecondary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems:
                  (spots) =>
                      spots.map((s) {
                        final i = s.spotIndex;
                        if (i < 0 || i >= entries.length) return null;
                        final sats = entries[i].value;
                        final date = DateFormat(
                          'MMM yyyy',
                        ).format(entries[i].key);
                        return LineTooltipItem(
                          '${_formatSats(sats)} sats\n$date',
                          const TextStyle(
                            fontFamily: 'RobotoMono',
                            fontSize: 11,
                            color: Colors.white,
                          ),
                        );
                      }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  String _abbrevSats(int sats) => SatConverter.abbreviateSats(sats);

  String _formatSats(int sats) => SatConverter.formatSats(sats);
}
