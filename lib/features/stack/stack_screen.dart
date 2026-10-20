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
import 'widgets/stack_stats.dart';

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
  ///
  /// Single-subscription, and the one subscriber is [_txnSub]; the UI reads
  /// [_txns], which that listener keeps current. Handing the same stream to a
  /// `StreamBuilder` as well would be a second listener on a
  /// single-subscription stream, and a second query if it were two streams.
  late final Stream<List<Transaction>> _transactions;

  /// Aggregates over the latest rows, or null until the first emission.
  ///
  /// Computed when the rows change, not in `build`. They used to be getters
  /// on the content widget, so every BTC price tick — which rebuilds the
  /// content — walked the whole transaction list four times.
  StackStats? _stats;
  Object? _txnError;

  @override
  void initState() {
    super.initState();
    _transactions = app.transactionService.watchAll();
    _init();
  }

  /// The goal is loaded *before* the notification listener starts.
  ///
  /// It used to subscribe on the line after an un-awaited `_loadGoal()`, and
  /// the first emission usually won that race — so `_checkGoalNotification`
  /// returned early on a null goal, and because the notification is one-shot
  /// per session, a user who had already passed their goal was never told,
  /// this visit or any visit, unless a transaction happened to change while
  /// the tab was open.
  Future<void> _init() async {
    await _loadGoal();
    if (!mounted) return;
    // One subscription, not two. This screen used to call `watchAll()` twice —
    // once for the StreamBuilder and once for the goal check — so every
    // insert, edit and xpub sync ran the full unfiltered table query and
    // decoded every row twice.
    _txnSub = _transactions.listen(
      _onTransactions,
      onError: (Object e) {
        if (mounted) setState(() => _txnError = e);
      },
    );
  }

  @override
  void dispose() {
    _txnSub?.cancel();
    _dcaController.dispose();
    super.dispose();
  }

  void _onTransactions(List<Transaction> txns) {
    final stats = StackStats.from(txns, DateTime.now());
    if (mounted) {
      setState(() {
        _txns = txns;
        _stats = stats;
        _txnError = null;
      });
    }
    _checkGoalNotification(stats.totalSats);
  }

  /// Latest rows, kept so the stats can be recomputed when the month turns.
  List<Transaction> _txns = const [];

  /// [_stats], recomputed first if the calendar month has changed since —
  /// "this month" and the monthly average both depend on it, and an app left
  /// open across midnight on the 1st would otherwise keep last month's.
  StackStats? _currentStats() {
    final stats = _stats;
    if (stats == null) return null;
    final now = DateTime.now();
    if (stats.isFor(now)) return stats;
    return _stats = StackStats.from(_txns, now);
  }

  void _checkGoalNotification(int total) {
    final goal = _stackGoalSats;
    if (goal == null || goal <= 0) return;
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
      body: Builder(
        builder: (context) {
          if (_txnError != null) {
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
          final stats = _currentStats();
          if (stats == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!stats.hasBitcoin) {
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
                builder: (context, currency, _) {
                  return _StackContent(
                    stats: stats,
                    currency: currency,
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
    required this.stats,
    required this.currency,
    required this.btcPrice,
    required this.period,
    required this.onPeriodChanged,
    required this.stackGoalSats,
    required this.onEditGoal,
    required this.dcaController,
    required this.dcaYears,
    required this.onDcaYearsChanged,
  });

  final StackStats stats;
  final String currency;
  final double? btcPrice;
  final StackPeriod period;
  final ValueChanged<StackPeriod> onPeriodChanged;
  final int? stackGoalSats;
  final VoidCallback onEditGoal;
  final TextEditingController dcaController;
  final int dcaYears;
  final ValueChanged<int> onDcaYearsChanged;

  @override
  Widget build(BuildContext context) {
    final history = stats.history;
    final hasBtc = history.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        const SizedBox(height: 8),

        // ── Hero ─────────────────────────────────────────────────────────────
        StackHero(
          totalSats: stats.totalSats,
          monthSats: stats.monthSats,
          btcPrice: btcPrice,
          currency: currency,
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
          totalSats: stats.totalSats,
          goalSats: stackGoalSats,
          avgMonthlySats: stats.avgMonthlySats,
          btcPrice: btcPrice,
          onEdit: onEditGoal,
          currency: currency,
        ),
        const SizedBox(height: 20),

        // ── DCA simulator ─────────────────────────────────────────────────────
        _SectionHeader(title: 'DCA Simulator'),
        DcaSimulator(
          btcPrice: btcPrice,
          controller: dcaController,
          years: dcaYears,
          onYearsChanged: onDcaYearsChanged,
          currency: currency,
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

