import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/analytics_data.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_text_styles.dart';
import '../../shared/utils/currency_utils.dart';
import '../../shared/widgets/empty_state.dart';
import '../../main.dart' as app;

// ── Colour palette for categories ─────────────────────────────────────────────

const _categoryColors = <String, Color>{
  'Food & Dining': Color(0xFFE24B4A),
  'Transport': Color(0xFFF7931A),
  'Housing': Color(0xFF888780),
  'Shopping': Color(0xFF9B59B6),
  'Subscriptions': Color(0xFF3498DB),
  'Entertainment': Color(0xFF1D9E75),
  'Bitcoin': Color(0xFFF7931A),
  'Income': Color(0xFF1D9E75),
  'Other': Color(0xFF888780),
};

Color _colorFor(String category) =>
    _categoryColors[category] ?? const Color(0xFF888780);

// ── Screen ────────────────────────────────────────────────────────────────────

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  void _previousMonth() => setState(() {
        _selectedMonth =
            DateTime(_selectedMonth.year, _selectedMonth.month - 1);
      });

  void _nextMonth() => setState(() {
        _selectedMonth =
            DateTime(_selectedMonth.year, _selectedMonth.month + 1);
      });

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _selectedMonth.year == now.year &&
        _selectedMonth.month == now.month;
  }

  Future<void> _exportCsv() async {
    final currency = app.currencyNotifier.value;
    final btcPrice = app.btcPriceService.currentPrice;
    final monthLabel = DateFormat('yyyy-MM').format(_selectedMonth);

    try {
      final csv = await app.dashboardService.exportMonthlySummary(
        month: _selectedMonth,
        currency: currency,
        btcPrice: btcPrice,
      );

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export spending summary',
        fileName: 'sats_stack_spending_$monthLabel.csv',
        allowedExtensions: ['csv'],
        type: FileType.custom,
      );
      if (savePath == null) return;
      await File(savePath).writeAsString(csv);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Spending summary exported')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _MonthSelector(
          month: _selectedMonth,
          onPrevious: _previousMonth,
          onNext: _isCurrentMonth ? null : _nextMonth,
        ),
        centerTitle: false,
      ),
      body: ValueListenableBuilder<String>(
        valueListenable: app.currencyNotifier,
        builder: (context, currency, _) {
          return StreamBuilder<AnalyticsData>(
            stream: app.dashboardService.watchAnalytics(_selectedMonth),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text('Failed to load analytics: ${snapshot.error}'),
                );
              }
              final data = snapshot.data ?? AnalyticsData.empty;
              final hasData = data.spendingByCategory.isNotEmpty ||
                  data.monthlyTotals.any((m) => m.spending > 0);

              if (!hasData) {
                return const EmptyState(
                  icon: Icons.bar_chart_outlined,
                  title: 'No spending data yet',
                  subtitle:
                      'Add transactions or import a CSV to see your analytics.',
                );
              }

              return ListView(
                padding: const EdgeInsets.only(bottom: 40),
                children: [
                  const SizedBox(height: 8),

                  // ── Pie chart ─────────────────────────────────────────
                  if (data.spendingByCategory.isNotEmpty) ...[
                    _SectionHeader(
                      title: 'Spending by Category',
                      trailing: IconButton(
                        icon: const Icon(Icons.download_outlined, size: 18),
                        tooltip: 'Export CSV',
                        onPressed: _exportCsv,
                      ),
                    ),
                    _PieSection(data: data, currency: currency),
                    const SizedBox(height: 24),
                  ],

                  // ── 6-month trend ──────────────────────────────────────
                  _SectionHeader(title: '6-Month Spending Trend'),
                  _TrendChart(
                      monthlyTotals: data.monthlyTotals, currency: currency),
                  const SizedBox(height: 24),

                  // ── YTD summary ────────────────────────────────────────
                  _SectionHeader(
                      title: 'Year to Date (${_selectedMonth.year})'),
                  _YtdCard(data: data, currency: currency),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ── Month selector ────────────────────────────────────────────────────────────

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({
    required this.month,
    required this.onPrevious,
    this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: onPrevious,
          visualDensity: VisualDensity.compact,
        ),
        Text(
          DateFormat('MMMM yyyy').format(month),
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: onNext,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

// ── Pie chart + legend ────────────────────────────────────────────────────────

class _PieSection extends StatefulWidget {
  const _PieSection({required this.data, required this.currency});
  final AnalyticsData data;
  final String currency;

  @override
  State<_PieSection> createState() => _PieSectionState();
}

class _PieSectionState extends State<_PieSection> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final sorted = widget.data.spendingByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = sorted.fold(0.0, (s, e) => s + e.value);

    final sections = sorted.asMap().entries.map((entry) {
      final i = entry.key;
      final e = entry.value;
      final isTouched = i == _touched;
      return PieChartSectionData(
        value: e.value,
        color: _colorFor(e.key),
        radius: isTouched ? 72 : 60,
        title: isTouched ? '${(e.value / total * 100).toStringAsFixed(0)}%' : '',
        titleStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 44,
                sectionsSpace: 2,
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    setState(() {
                      if (!event.isInterestedForInteractions ||
                          response?.touchedSection == null) {
                        _touched = -1;
                      } else {
                        _touched = response!
                            .touchedSection!.touchedSectionIndex;
                      }
                    });
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Legend
          ...sorted.asMap().entries.map((entry) {
            final i = entry.key;
            final e = entry.value;
            final pct = total > 0 ? e.value / total * 100 : 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _colorFor(e.key),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      e.key,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    '${pct.toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    CurrencyUtils.format(e.value, widget.currency, decimalDigits: 0),
                    style: AppTextStyles.monoSmall.copyWith(
                      fontWeight: i == _touched
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── 6-month bar chart ─────────────────────────────────────────────────────────

class _TrendChart extends StatefulWidget {
  const _TrendChart({required this.monthlyTotals, required this.currency});
  final List<MonthlyTotal> monthlyTotals;
  final String currency;

  @override
  State<_TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<_TrendChart> {
  // null = "All spending"
  String? _selectedCategory;

  List<String> get _categories {
    final cats = <String>{};
    for (final m in widget.monthlyTotals) {
      cats.addAll(m.byCategory.keys);
    }
    return cats.toList()..sort();
  }

  double _valueFor(MonthlyTotal m) {
    if (_selectedCategory == null) return m.spending;
    return m.byCategory[_selectedCategory!] ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.monthlyTotals.isEmpty) return const SizedBox.shrink();

    final categories = _categories;
    final values = widget.monthlyTotals.map(_valueFor).toList();
    final maxY = values.fold(0.0, (a, b) => a > b ? a : b);
    final chartMax = maxY > 0 ? (maxY * 1.2).ceilToDouble() : 100.0;
    final barColor = _selectedCategory != null
        ? _colorFor(_selectedCategory!).withAlpha(200)
        : AppColors.danger.withAlpha(200);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Category filter chips ────────────────────────────────────────
        if (categories.isNotEmpty)
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _ChipOption(
                  label: 'All',
                  selected: _selectedCategory == null,
                  color: AppColors.danger,
                  onTap: () => setState(() => _selectedCategory = null),
                ),
                for (final cat in categories)
                  _ChipOption(
                    label: cat,
                    selected: _selectedCategory == cat,
                    color: _colorFor(cat),
                    onTap: () => setState(() => _selectedCategory = cat),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),

        // ── Bar chart ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                maxY: chartMax,
                barGroups: widget.monthlyTotals.asMap().entries.map((entry) {
                  final i = entry.key;
                  final m = entry.value;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: _valueFor(m),
                        color: barColor,
                        width: 18,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                    ],
                  );
                }).toList(),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= widget.monthlyTotals.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            DateFormat('MMM')
                                .format(widget.monthlyTotals[i].month),
                            style: const TextStyle(
                                fontSize: 10, color: AppColors.textSecondary),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      getTitlesWidget: (value, meta) {
                        if (value == 0 || value == chartMax) {
                          return Text(
                            CurrencyUtils.formatCompact(value, widget.currency),
                            style: const TextStyle(
                                fontSize: 9, color: AppColors.textSecondary),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: chartMax / 4,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: AppColors.textSecondary.withAlpha(30),
                    strokeWidth: 0.5,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final m = widget.monthlyTotals[group.x];
                      return BarTooltipItem(
                        '${DateFormat('MMM yyyy').format(m.month)}\n'
                        '${CurrencyUtils.format(rod.toY, widget.currency, decimalDigits: 0)}',
                        const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChipOption extends StatelessWidget {
  const _ChipOption({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? color.withAlpha(40) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? color : AppColors.textSecondary.withAlpha(60),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? color : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ── YTD summary card ──────────────────────────────────────────────────────────

class _YtdCard extends StatelessWidget {
  const _YtdCard({required this.data, required this.currency});
  final AnalyticsData data;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final surplusPositive = data.ytdSurplus >= 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline,
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            _YtdStat(
              label: 'Income',
              value: CurrencyUtils.format(data.ytdIncome, currency, decimalDigits: 0),
              color: AppColors.success,
            ),
            const _Divider(),
            _YtdStat(
              label: 'Spending',
              value: CurrencyUtils.format(data.ytdSpending, currency, decimalDigits: 0),
              color: AppColors.danger,
            ),
            const _Divider(),
            _YtdStat(
              label: 'Surplus',
              value: '${surplusPositive ? '+' : ''}${CurrencyUtils.format(data.ytdSurplus, currency, decimalDigits: 0)}',
              color: surplusPositive ? AppColors.success : AppColors.danger,
            ),
          ],
        ),
      ),
    );
  }
}

class _YtdStat extends StatelessWidget {
  const _YtdStat({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTextStyles.monoSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 0.5,
      height: 32,
      color: Theme.of(context).colorScheme.outline,
      margin: const EdgeInsets.symmetric(horizontal: 8),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 1.2,
                ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
