import 'dart:async';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/database/database.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_text_styles.dart';
import '../../shared/utils/currency_utils.dart';
import '../../shared/widgets/btc_price_chip.dart';
import '../../shared/widgets/empty_state.dart';
import '../../main.dart' as app;

// ── Chart period ──────────────────────────────────────────────────────────────

enum _Period { threeM, sixM, oneY, all }

extension _PeriodLabel on _Period {
  String get label => switch (this) {
        _Period.threeM => '3M',
        _Period.sixM => '6M',
        _Period.oneY => '1Y',
        _Period.all => 'All',
      };
}

// ── Screen ────────────────────────────────────────────────────────────────────

class StackScreen extends StatefulWidget {
  const StackScreen({super.key});

  @override
  State<StackScreen> createState() => _StackScreenState();
}

class _StackScreenState extends State<StackScreen> {
  _Period _period = _Period.all;
  final _dcaController = TextEditingController(text: '100');
  int _dcaYears = 5;
  int? _stackGoalSats;
  StreamSubscription<List<Transaction>>? _txnSub;

  @override
  void initState() {
    super.initState();
    _loadGoal();
    _txnSub = app.transactionService.watchAll().listen(_checkGoalNotification);
  }

  @override
  void dispose() {
    _txnSub?.cancel();
    _dcaController.dispose();
    super.dispose();
  }

  void _checkGoalNotification(List<Transaction> txns) {
    final goal = _stackGoalSats;
    if (goal == null || goal <= 0) return;
    final total =
        txns.where((t) => t.isBitcoin).fold(0, (s, t) => s + t.amountSats);
    if (total >= goal) {
      app.notificationService.showStackGoalReached(
        goalSats: goal,
        currency: app.currencyNotifier.value,
        btcPrice: app.btcPriceService.priceNotifier.value,
      );
    }
  }

  Future<void> _loadGoal() async {
    final entry = await (app.db.select(app.db.appSettings)
          ..where((s) => s.key.equals(AppConstants.settingStackGoalSats)))
        .getSingleOrNull();
    if (mounted) {
      setState(() => _stackGoalSats = entry != null ? int.tryParse(entry.value) : null);
    }
  }

  Future<void> _saveGoal(int sats) async {
    await app.db.into(app.db.appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(
        key: AppConstants.settingStackGoalSats,
        value: sats.toString(),
      ),
    );
    setState(() => _stackGoalSats = sats);
  }

  void _openSetGoal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SetGoalSheet(
        current: _stackGoalSats,
        onSave: _saveGoal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stack'),
        actions: [
          BtcPriceChip(service: app.btcPriceService),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<List<Transaction>>(
        stream: app.transactionService.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline,
                      size: 48,
                      color: Theme.of(context)
                          .colorScheme
                          .error
                          .withAlpha(160)),
                  const SizedBox(height: 12),
                  Text('Failed to load stack data',
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final allTxns = snapshot.data ?? [];
          final hasBtc = allTxns.any((t) => t.isBitcoin);

          if (!hasBtc) {
            return EmptyState(
              icon: Icons.currency_bitcoin,
              title: 'No Bitcoin tracked yet',
              subtitle:
                  'Log income tagged as Bitcoin or sync an xpub wallet to start building your stack.',
              actionLabel: 'Add Transaction',
              onAction: () => context.go('/transactions'),
            );
          }

          return ValueListenableBuilder<double?>(
            valueListenable: app.btcPriceService.priceNotifier,
            builder: (context, btcPrice, _) {
              return ValueListenableBuilder<String>(
                valueListenable: app.currencyNotifier,
                builder: (context, _, __) {
                  return _StackContent(
                    allTxns: allTxns,
                    btcPrice: btcPrice,
                    period: _period,
                    onPeriodChanged: (p) => setState(() => _period = p),
                    stackGoalSats: _stackGoalSats,
                    onEditGoal: () => _openSetGoal(context),
                    dcaController: _dcaController,
                    dcaYears: _dcaYears,
                    onDcaYearsChanged: (y) => setState(() => _dcaYears = y),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// ── Content (stateless, receives all data) ────────────────────────────────────

class _StackContent extends StatelessWidget {
  const _StackContent({
    required this.allTxns,
    required this.btcPrice,
    required this.period,
    required this.onPeriodChanged,
    required this.stackGoalSats,
    required this.onEditGoal,
    required this.dcaController,
    required this.dcaYears,
    required this.onDcaYearsChanged,
  });

  final List<Transaction> allTxns;
  final double? btcPrice;
  final _Period period;
  final ValueChanged<_Period> onPeriodChanged;
  final int? stackGoalSats;
  final VoidCallback onEditGoal;
  final TextEditingController dcaController;
  final int dcaYears;
  final ValueChanged<int> onDcaYearsChanged;

  int get _totalSats =>
      allTxns.where((t) => t.isBitcoin).fold(0, (s, t) => s + t.amountSats);

  int get _monthSats {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, 1);
    return allTxns
        .where((t) => t.isBitcoin && !t.date.isBefore(first))
        .fold(0, (s, t) => s + t.amountSats);
  }

  /// Average sats stacked per complete calendar month (excludes the current
  /// partial month so it doesn't drag the average down mid-month).
  int get _avgMonthlySats {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final byMonth = <DateTime, int>{};
    for (final t in allTxns.where((t) => t.isBitcoin)) {
      final m = DateTime(t.date.year, t.date.month);
      if (m.isBefore(currentMonth)) {
        byMonth[m] = (byMonth[m] ?? 0) + t.amountSats;
      }
    }
    if (byMonth.isEmpty) return 0;
    final total = byMonth.values.fold(0, (s, v) => s + v);
    return (total / byMonth.length).round();
  }

  // Builds cumulative monthly history from all Bitcoin transactions.
  Map<DateTime, int> get _fullHistory {
    final byMonth = <DateTime, int>{};
    for (final t in allTxns.where((t) => t.isBitcoin)) {
      final month = DateTime(t.date.year, t.date.month);
      byMonth[month] = (byMonth[month] ?? 0) + t.amountSats;
    }
    final sorted = byMonth.keys.toList()..sort();
    int cumulative = 0;
    final result = <DateTime, int>{};
    for (final m in sorted) {
      cumulative += byMonth[m]!;
      result[m] = cumulative;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final history = _fullHistory;
    final hasBtc = history.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        const SizedBox(height: 8),

        // ── Hero ─────────────────────────────────────────────────────────────
        _StackHero(
          totalSats: _totalSats,
          monthSats: _monthSats,
          btcPrice: btcPrice,
        ),
        const SizedBox(height: 20),

        // ── History chart ─────────────────────────────────────────────────────
        if (hasBtc) ...[
          _SectionHeader(title: 'Stack History'),
          _HistoryChartCard(
            history: history,
            period: period,
            onPeriodChanged: onPeriodChanged,
            btcPrice: btcPrice,
          ),
          const SizedBox(height: 20),
        ],

        // ── Stack goal ────────────────────────────────────────────────────────
        _SectionHeader(title: 'Stack Goal'),
        _StackGoalCard(
          totalSats: _totalSats,
          goalSats: stackGoalSats,
          avgMonthlySats: _avgMonthlySats,
          btcPrice: btcPrice,
          onEdit: onEditGoal,
        ),
        const SizedBox(height: 20),

        // ── DCA simulator ─────────────────────────────────────────────────────
        _SectionHeader(title: 'DCA Simulator'),
        _DcaSimulator(
          btcPrice: btcPrice,
          controller: dcaController,
          years: dcaYears,
          onYearsChanged: onDcaYearsChanged,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Hero card ─────────────────────────────────────────────────────────────────

class _StackHero extends StatelessWidget {
  const _StackHero({required this.totalSats, required this.monthSats, this.btcPrice});

  final int totalSats;
  final int monthSats;
  final double? btcPrice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fiatFmt = NumberFormat.currency(symbol: CurrencyUtils.symbolFor(app.currencyNotifier.value), decimalDigits: 0);
    final fiatValue = btcPrice != null && btcPrice! > 0
        ? fiatFmt.format(totalSats / 1e8 * btcPrice!)
        : '--';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1200), Color(0xFF2A1F00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.bitcoinOrange.withAlpha(60),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.currency_bitcoin, size: 14, color: AppColors.bitcoinOrange),
              const SizedBox(width: 4),
              Text(
                'Total Stack',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.bitcoinOrange,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _formatSats(totalSats),
            style: AppTextStyles.heroSats.copyWith(color: Colors.white),
          ),
          Text(
            'sats',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '≈ $fiatValue',
                style: AppTextStyles.monoMedium.copyWith(
                  color: Colors.white.withAlpha(200),
                ),
              ),
              const Spacer(),
              if (monthSats != 0)
                _MonthChange(sats: monthSats),
            ],
          ),
        ],
      ),
    );
  }

  String _formatSats(int sats) {
    return sats.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }
}

class _MonthChange extends StatelessWidget {
  const _MonthChange({required this.sats});
  final int sats;

  @override
  Widget build(BuildContext context) {
    final positive = sats > 0;
    final color = positive ? AppColors.success : AppColors.danger;
    final sign = positive ? '+' : '';
    final formatted = '$sign${sats.abs().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(positive ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: color),
        const SizedBox(width: 2),
        Text(
          '$formatted sats this month',
          style: AppTextStyles.monoSmall.copyWith(color: color, fontSize: 11),
        ),
      ],
    );
  }
}

// ── History chart card ────────────────────────────────────────────────────────

class _HistoryChartCard extends StatelessWidget {
  const _HistoryChartCard({
    required this.history,
    required this.period,
    required this.onPeriodChanged,
    required this.btcPrice,
  });

  final Map<DateTime, int> history;
  final _Period period;
  final ValueChanged<_Period> onPeriodChanged;
  final double? btcPrice;

  List<MapEntry<DateTime, int>> _filtered() {
    final entries = history.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final now = DateTime.now();
    final cutoff = switch (period) {
      _Period.threeM => DateTime(now.year, now.month - 2),
      _Period.sixM => DateTime(now.year, now.month - 5),
      _Period.oneY => DateTime(now.year - 1, now.month),
      _Period.all => DateTime(2009),
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
                  for (final p in _Period.values)
                    _PeriodChip(
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
                child: filtered.length < 2
                    ? Center(
                        child: Text(
                          'Not enough data for this period',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      )
                    : _LineChart(entries: filtered, btcPrice: btcPrice),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart({required this.entries, this.btcPrice});

  final List<MapEntry<DateTime, int>> entries;
  final double? btcPrice;

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (int i = 0; i < entries.length; i++)
        FlSpot(i.toDouble(), entries[i].value.toDouble()),
    ];
    final maxY = entries.map((e) => e.value).reduce(max).toDouble();
    final minY = entries.map((e) => e.value).reduce(min).toDouble();
    final yPad = max((maxY - minY) * 0.1, 1.0);

    return LineChart(
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
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.white.withAlpha(12),
            strokeWidth: 0.5,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              getTitlesWidget: (value, _) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  _abbrevSats(value.toInt()),
                  style: TextStyle(
                    fontFamily: 'RobotoMono',
                    fontSize: 9,
                    color: AppColors.textSecondary,
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
                if (i < 0 || i >= entries.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    DateFormat('MMM yy').format(entries[i].key),
                    style: TextStyle(fontSize: 9, color: AppColors.textSecondary),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) {
              final i = s.spotIndex;
              if (i < 0 || i >= entries.length) return null;
              final sats = entries[i].value;
              final date = DateFormat('MMM yyyy').format(entries[i].key);
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
    );
  }

  String _abbrevSats(int sats) {
    if (sats >= 1000000) return '${(sats / 1000000).toStringAsFixed(1)}M';
    if (sats >= 1000) return '${(sats / 1000).toStringAsFixed(0)}k';
    return '$sats';
  }

  String _formatSats(int sats) => sats
      .toString()
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
}

// ── Stack goal card ───────────────────────────────────────────────────────────

class _StackGoalCard extends StatelessWidget {
  const _StackGoalCard({
    required this.totalSats,
    required this.goalSats,
    required this.avgMonthlySats,
    required this.btcPrice,
    required this.onEdit,
  });

  final int totalSats;
  final int? goalSats;
  final int avgMonthlySats;
  final double? btcPrice;
  final VoidCallback onEdit;

  /// Returns the projected completion month, or null if not computable.
  DateTime? _projectedDate(int remaining) {
    if (avgMonthlySats <= 0 || remaining <= 0) return null;
    final monthsNeeded = (remaining / avgMonthlySats).ceil();
    final now = DateTime.now();
    return DateTime(now.year, now.month + monthsNeeded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fiatFmt = NumberFormat.currency(symbol: CurrencyUtils.symbolFor(app.currencyNotifier.value), decimalDigits: 0);

    if (goalSats == null || goalSats! <= 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GestureDetector(
          onTap: onEdit,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outline.withAlpha(60),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.flag_outlined, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 10),
                Text(
                  'Set a stacking goal',
                  style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                ),
                const Spacer(),
                Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      );
    }

    final progress = (totalSats / goalSats!).clamp(0.0, 1.0);
    final remaining = goalSats! - totalSats;
    final progressColor = progress >= 1.0
        ? AppColors.success
        : progress > 0.7
            ? AppColors.bitcoinOrange
            : AppColors.success;
    final remainingFiat = btcPrice != null && btcPrice! > 0 && remaining > 0
        ? fiatFmt.format(remaining / 1e8 * btcPrice!)
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outline.withAlpha(60),
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${(progress * 100).toStringAsFixed(1)}%',
                    style: AppTextStyles.monoMedium.copyWith(
                      color: progressColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_formatSats(totalSats)} / ${_formatSats(goalSats!)} sats',
                    style: AppTextStyles.monoSmall.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.edit_outlined, size: 14, color: AppColors.textSecondary),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: progressColor.withAlpha(25),
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  minHeight: 8,
                ),
              ),
              if (remaining > 0 && remainingFiat != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${_formatSats(remaining)} sats to go ≈ $remainingFiat',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                // ── Projection row ──────────────────────────────────────
                Row(
                  children: [
                    if (avgMonthlySats > 0) ...[
                      Icon(Icons.trending_up, size: 13, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        '+${_formatSats(avgMonthlySats)} sats/mo avg',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (_projectedDate(remaining) case final date?) ...[
                      Icon(Icons.flag_outlined, size: 13, color: AppColors.bitcoinOrange),
                      const SizedBox(width: 4),
                      Text(
                        'Goal by ${DateFormat('MMM yyyy').format(date)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.bitcoinOrange,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ] else if (progress >= 1.0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.check_circle_outline, size: 14, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text(
                      'Goal reached!',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.success),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatSats(int sats) => sats
      .toString()
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
}

// ── DCA Simulator ─────────────────────────────────────────────────────────────

class _DcaSimulator extends StatelessWidget {
  const _DcaSimulator({
    required this.btcPrice,
    required this.controller,
    required this.years,
    required this.onYearsChanged,
  });

  final double? btcPrice;
  final TextEditingController controller;
  final int years;
  final ValueChanged<int> onYearsChanged;

  static const _yearOptions = [1, 2, 5, 10];

  static const _scenarios = [
    (label: 'Conservative', rate: 0.0, color: AppColors.success),
    (label: 'Moderate', rate: 0.20, color: AppColors.bitcoinOrange),
    (label: 'Optimistic', rate: 0.40, color: Color(0xFF6AB0E8)),
  ];

  int _simulate(double monthlyAmount, double startPrice, int months, double annualRate) {
    if (startPrice <= 0) return 0;
    int total = 0;
    for (int n = 0; n < months; n++) {
      final price = startPrice * pow(1 + annualRate, n / 12);
      total += (monthlyAmount / price * 1e8).round();
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = btcPrice ?? 0;
    final monthly = double.tryParse(controller.text.replaceAll(',', '')) ?? 0;
    final months = years * 12;
    final totalInvested = monthly * months;
    final fiatFmt = NumberFormat.currency(symbol: CurrencyUtils.symbolFor(app.currencyNotifier.value), decimalDigits: 0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Inputs
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                      ],
                      style: AppTextStyles.monoMedium.copyWith(color: theme.colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Monthly DCA',
                        prefixText: '${CurrencyUtils.symbolFor(app.currencyNotifier.value)} ',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Period',
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          for (final y in _yearOptions)
                            _PeriodChip(
                              label: '${y}y',
                              selected: years == y,
                              onTap: () => onYearsChanged(y),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (price <= 0)
                Text(
                  'BTC price unavailable — open the app with internet to fetch price.',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                )
              else ...[
                // Total invested line
                Row(
                  children: [
                    Text(
                      'Total invested:',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      fiatFmt.format(totalInvested),
                      style: AppTextStyles.monoSmall.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // Scenario rows
                for (final s in _scenarios) ...[
                  _ScenarioRow(
                    label: s.label,
                    rate: s.rate,
                    color: s.color,
                    sats: _simulate(monthly, price, months, s.rate),
                    btcPrice: price,
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 4),
                Text(
                  'Conservative = 0%/yr · Moderate = 20%/yr · Optimistic = 40%/yr BTC price appreciation. Values shown at today\'s price.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScenarioRow extends StatelessWidget {
  const _ScenarioRow({
    required this.label,
    required this.rate,
    required this.color,
    required this.sats,
    required this.btcPrice,
  });

  final String label;
  final double rate;
  final Color color;
  final int sats;
  final double btcPrice;

  @override
  Widget build(BuildContext context) {
    final fiatFmt = NumberFormat.currency(symbol: CurrencyUtils.symbolFor(app.currencyNotifier.value), decimalDigits: 0);
    final fiatValue = fiatFmt.format(sats / 1e8 * btcPrice);
    final satsStr = sats
        .toString()
        .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

    return Row(
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Text(
            '$satsStr sats',
            style: AppTextStyles.monoSmall.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          '≈ $fiatValue',
          style: AppTextStyles.monoSmall.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

// ── Set Goal sheet ────────────────────────────────────────────────────────────

class _SetGoalSheet extends StatefulWidget {
  const _SetGoalSheet({required this.current, required this.onSave});
  final int? current;
  final ValueChanged<int> onSave;

  @override
  State<_SetGoalSheet> createState() => _SetGoalSheetState();
}

class _SetGoalSheetState extends State<_SetGoalSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.current != null ? widget.current.toString() : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Set Stack Goal',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _ctrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  autofocus: true,
                  style: AppTextStyles.monoLarge.copyWith(color: theme.colorScheme.onSurface),
                  decoration: const InputDecoration(
                    labelText: 'Goal (sats)',
                    hintText: '1,000,000',
                    suffixText: 'sats',
                  ),
                ),
                const SizedBox(height: 8),
                // Quick-pick presets
                Wrap(
                  spacing: 8,
                  children: [
                    for (final preset in [100000, 1000000, 10000000, 21000000])
                      ActionChip(
                        label: Text(_abbrev(preset)),
                        onPressed: () => _ctrl.text = preset.toString(),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () {
                    final val = int.tryParse(_ctrl.text);
                    if (val != null && val > 0) {
                      widget.onSave(val);
                      Navigator.of(context).pop();
                    }
                  },
                  style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                  child: const Text('Save Goal'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _abbrev(int sats) {
    if (sats >= 1000000) return '${sats ~/ 1000000}M';
    if (sats >= 1000) return '${sats ~/ 1000}k';
    return '$sats';
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.bitcoinOrange.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? AppColors.bitcoinOrange : AppColors.textSecondary.withAlpha(60),
            width: selected ? 1.0 : 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? AppColors.bitcoinOrange : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
