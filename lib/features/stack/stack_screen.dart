import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/widgets/btc_price_chip.dart';
import '../../shared/widgets/empty_state.dart';
import '../../main.dart' as app;
import 'widgets/dca_simulator.dart';
import 'widgets/stack_goal_card.dart';
import 'widgets/stack_hero.dart';
import 'widgets/stack_history_chart.dart';
import 'widgets/stack_period.dart';

// ── Chart period ──────────────────────────────────────────────────────────────

// ── Screen ────────────────────────────────────────────────────────────────────

class StackScreen extends StatefulWidget {
  const StackScreen({super.key});

  @override
  State<StackScreen> createState() => _StackScreenState();
}

class _StackScreenState extends State<StackScreen> {
  StackPeriod _period = StackPeriod.all;
  final _dcaController = TextEditingController(text: '100');
  int _dcaYears = 5;
  int? _stackGoalSats;
  StreamSubscription<List<Transaction>>? _txnSub;

  /// Built once. `watchAll()` hands back a new Drift stream per call, so
  /// building it in `build()` re-subscribed and re-queried the table on every
  /// rebuild — including every period-filter tap and BTC price tick.
  late final Stream<List<Transaction>> _transactions;

  @override
  void initState() {
    super.initState();
    _loadGoal();
    _transactions = app.transactionService.watchAll();
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
    if (mounted) setState(() => _stackGoalSats = sats);
  }

  void _openSetGoal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SetGoalSheet(
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
        stream: _transactions,
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
  final StackPeriod period;
  final ValueChanged<StackPeriod> onPeriodChanged;
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
        StackHero(
          totalSats: _totalSats,
          monthSats: _monthSats,
          btcPrice: btcPrice,
        ),
        const SizedBox(height: 20),

        // ── History chart ─────────────────────────────────────────────────────
        if (hasBtc) ...[
          _SectionHeader(title: 'Stack History'),
          HistoryChartCard(
            history: history,
            period: period,
            onPeriodChanged: onPeriodChanged,
            btcPrice: btcPrice,
          ),
          const SizedBox(height: 20),
        ],

        // ── Stack goal ────────────────────────────────────────────────────────
        _SectionHeader(title: 'Stack Goal'),
        StackGoalCard(
          totalSats: _totalSats,
          goalSats: stackGoalSats,
          avgMonthlySats: _avgMonthlySats,
          btcPrice: btcPrice,
          onEdit: onEditGoal,
        ),
        const SizedBox(height: 20),

        // ── DCA simulator ─────────────────────────────────────────────────────
        _SectionHeader(title: 'DCA Simulator'),
        DcaSimulator(
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

// ── History chart card ────────────────────────────────────────────────────────

// ── Stack goal card ───────────────────────────────────────────────────────────

// ── DCA Simulator ─────────────────────────────────────────────────────────────

// ── Set Goal sheet ────────────────────────────────────────────────────────────

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

