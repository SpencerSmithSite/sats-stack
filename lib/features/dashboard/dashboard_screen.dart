import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../core/models/dashboard_data.dart';
import '../../core/models/wallet_summary.dart';
import '../../features/transactions/widgets/transaction_list_item.dart';
import '../../main.dart' as app;
import '../../shared/theme/app_colors.dart';
import '../../shared/utils/currency_utils.dart';
import '../../shared/utils/month_cursor.dart';
import '../../shared/utils/sat_converter.dart';
import '../../shared/widgets/btc_price_chip.dart';
import '../../shared/widgets/month_selector.dart';
import '../../shared/widgets/shrink_to_fit.dart';
import '../../shared/widgets/tappable.dart';
import 'widgets/ai_insight_card.dart';
import 'widgets/hero_card.dart';
import 'widgets/metric_tile.dart';
import 'widgets/spending_chart.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  String? _cachedInsight;
  bool _isGeneratingInsight = false;

  /// Who would receive this month's figures, or null when the active backend
  /// keeps them on the device (or on the user's own server).
  String? _insightRecipient;

  /// Rebuilt only when the month or the inflation rate actually changes.
  ///
  /// These were constructed inside `build()`, and `watch*()` returns a new
  /// Drift stream every call, so each rebuild re-subscribed and reset to
  /// `waiting` — the Wallets section vanished and came back on every BTC
  /// price tick, and the whole dashboard re-queried the table with it.
  late Stream<DashboardData> _dashboard;
  late Stream<List<WalletSummary>> _perWallet;

  /// Category name → category, for the recent-transaction rows. Previously a
  /// `getAll()` future rebuilt on every price tick.
  Map<String, Category> _categoriesByName = const {};
  StreamSubscription<List<Category>>? _categorySub;

  @override
  void initState() {
    super.initState();
    _rebuildStreams();
    app.inflationRateNotifier.addListener(_onInflationChange);
    app.currencyNotifier.addListener(_onCurrencyChange);
    _categorySub = app.categoryService.watchAll().listen((cats) {
      if (!mounted) return;
      setState(() => _categoriesByName = {for (final c in cats) c.name: c});
    });
    if (app.aiEnabledNotifier.value) _initInsight();
  }

  @override
  void dispose() {
    app.inflationRateNotifier.removeListener(_onInflationChange);
    app.currencyNotifier.removeListener(_onCurrencyChange);
    _categorySub?.cancel();
    super.dispose();
  }

  void _rebuildStreams() {
    _dashboard = app.dashboardService.watchDashboard(
      _selectedMonth,
      inflationRate: app.inflationRateNotifier.value,
    );
    _perWallet = app.dashboardService.watchPerWallet(_selectedMonth);
  }

  /// The rate is baked into the aggregate, so a change does need a new stream
  /// — just not one per frame.
  void _onInflationChange() => setState(_rebuildStreams);

  /// Every fiat figure is converted into the display currency inside the
  /// aggregate, so switching currency needs a recompute — the streams only
  /// re-emit when a table changes, and the currency is not in a table.
  void _onCurrencyChange() => setState(_rebuildStreams);

  void _showInsightError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _initInsight() async {
    _cachedInsight = await app.ollamaService.loadCachedInsight();
    // A hosted provider is told nothing unless the user asks. Generating this
    // automatically meant that selecting Claude in Settings and opening the
    // Dashboard uploaded the month's income, spending, surplus, stack total
    // and full category breakdown to a third party with no user action and no
    // disclosure — while the disclosure widget promised the opposite.
    final offDevice = app.ollamaService.sendsDataOffDevice;
    _insightRecipient =
        offDevice ? app.ollamaService.activeDataRecipient : null;
    if (mounted) setState(() {});
    if (offDevice) return;
    final stale = await app.ollamaService.isInsightStale();
    // Not awaited: the card shows the cached insight meanwhile, and the
    // generator handles its own failures.
    if (stale) unawaited(_generateInsight(userAsked: false));
  }

  /// Generates on an explicit tap. For a hosted provider this is the only way
  /// an insight is ever generated.
  /// [userAsked] is whether this came from a tap. A tap that fails says why;
  /// the automatic refresh stays quiet, since a stopped Ollama would otherwise
  /// greet every Dashboard visit with an error. Both used to stay quiet, so a
  /// tap on Generate with a rejected key or an unreachable server did nothing
  /// visible at all — and the backend's own explanation, which
  /// `CloudBackend.describeError` takes care to make readable, was dropped.
  Future<void> _generateInsight({bool userAsked = true}) async {
    if (_isGeneratingInsight) return;
    // Set before the first await: set after `isAvailable`, a double tap got
    // two generations in — two paid requests, and the figures sent twice.
    setState(() => _isGeneratingInsight = true);
    try {
      final available = await app.ollamaService.isAvailable();
      if (!mounted) return;
      if (!available) {
        if (userAsked) {
          _showInsightError(
            '${app.ollamaService.backend.displayName} is not available right '
            'now. Check it in Settings → Servers.',
          );
        }
        return;
      }

      // The last complete month — which the card says, and the prompt names.
      final now = DateTime.now();
      final lastMonth = DateTime(now.year, now.month - 1);
      final data = await app.dashboardService.getDashboard(lastMonth);
      final insight = await app.ollamaService.generateMonthlyInsight(
        totalStackSats: data.totalStackSats,
        btcPrice: app.btcPriceService.priceNotifier.value,
        currency: app.currencyNotifier.value,
        month: lastMonth,
        monthlyIncome: data.monthlyIncomeFiat,
        monthlySpending: data.monthlySpendingFiat,
        monthlySurplus: data.monthlySurplusFiat,
        spendingByCategory: data.spendingByCategory,
        stackGoalSats: data.stackGoalSats,
      );
      if (mounted) setState(() => _cachedInsight = insight);
    } catch (e) {
      debugPrint('Insight generation failed: $e');
      if (userAsked && mounted) _showInsightError('No insight: $e');
    } finally {
      if (mounted) setState(() => _isGeneratingInsight = false);
    }
  }

  void _previousMonth() {
    setState(() {
      _selectedMonth = MonthCursor(_selectedMonth).previous.month;
      _rebuildStreams();
    });
  }

  void _nextMonth() {
    setState(() {
      _selectedMonth = MonthCursor(_selectedMonth).next.month;
      _rebuildStreams();
    });
  }

  bool get _isCurrentMonth => MonthCursor(_selectedMonth).isCurrent();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: MonthSelector(
          month: _selectedMonth,
          onPrevious: _previousMonth,
          onNext: _isCurrentMonth ? null : _nextMonth,
        ),
        centerTitle: false,
        actions: [
          BtcPriceChip(service: app.btcPriceService),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
            tooltip: 'Settings',
          ),
        ],
      ),
      // The StreamBuilder is outermost and its stream is not rebuilt here, so
      // a price or currency tick only repaints — it no longer re-subscribes.
      body: StreamBuilder<DashboardData>(
        stream: _dashboard,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorState(message: snapshot.error.toString());
          }
          final data = snapshot.data ?? DashboardData.empty;
          // No price or currency listener here: each section that shows a
          // price-derived figure listens for itself (`_Live`). Wrapping the
          // whole content rebuilt every section and every transaction row on
          // each price poll.
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeOut,
            child: _DashboardContent(
              key: ValueKey(_selectedMonth),
              data: data,
              categoriesByName: _categoriesByName,
              perWallet: _perWallet,
              selectedMonth: _selectedMonth,
              inflationRate: app.inflationRateNotifier.value,
              cachedInsight: _cachedInsight,
              isGeneratingInsight: _isGeneratingInsight,
              onRefreshInsight: _generateInsight,
              insightRecipient: _insightRecipient,
            ),
          );
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error.withAlpha(160),
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Rebuilds [builder] — and only it — when the BTC price or the display
/// currency changes.
class _Live extends StatelessWidget {
  const _Live({required this.builder});

  final Widget Function(BuildContext context, double? btcPrice, String currency)
  builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double?>(
      valueListenable: app.btcPriceService.priceNotifier,
      builder:
          (context, btcPrice, _) => ValueListenableBuilder<String>(
            valueListenable: app.currencyNotifier,
            builder:
                (context, currency, _) => builder(context, btcPrice, currency),
          ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    super.key,
    required this.data,
    required this.categoriesByName,
    required this.perWallet,
    required this.selectedMonth,
    required this.inflationRate,
    this.cachedInsight,
    this.isGeneratingInsight = false,
    this.onRefreshInsight,
    this.insightRecipient,
  });

  final DashboardData data;
  final Map<String, Category> categoriesByName;
  final Stream<List<WalletSummary>> perWallet;
  final DateTime selectedMonth;
  final double inflationRate;
  final String? cachedInsight;
  final bool isGeneratingInsight;
  final VoidCallback? onRefreshInsight;

  /// Named third party that would receive the figures, or null when the
  /// insight is generated without anything leaving the device.
  final String? insightRecipient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const SizedBox(height: 8),

        // ── Hero card ─────────────────────────────────────────────────────
        _Live(
          builder:
              (context, btcPrice, currency) => HeroCard(
                totalStackSats: data.totalStackSats,
                monthChangeSats: data.monthStackChangeSats,
                btcPrice: btcPrice,
                currency: currency,
              ),
        ),
        const SizedBox(height: 16),

        // Said, rather than shown as a quietly smaller total. Only happens for
        // a foreign-currency row before the first price fetch has landed, and
        // clears itself once it does.
        if (data.unconvertedCount > 0) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 15,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${data.unconvertedCount} '
                    '${data.unconvertedCount == 1 ? 'transaction is' : 'transactions are'} '
                    'in another currency and not yet in these totals — '
                    'waiting for an exchange rate.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── 2×2 Metric grid ───────────────────────────────────────────────
        _Live(
          builder:
              (context, btcPrice, currency) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: MetricTile(
                            label: 'Monthly Surplus',
                            value: CurrencyUtils.format(
                              data.monthlySurplusFiat,
                              currency,
                            ),
                            subValue:
                                btcPrice != null && btcPrice > 0
                                    ? _satConversion(
                                      data.monthlySurplusFiat.abs(),
                                      btcPrice,
                                    )
                                    : null,
                            valueColor:
                                data.monthlySurplusFiat >= 0
                                    ? AppColors.success
                                    : AppColors.danger,
                            icon: Icons.savings_outlined,
                            iconColor:
                                data.monthlySurplusFiat >= 0
                                    ? AppColors.success
                                    : AppColors.danger,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: MetricTile(
                            label: 'Fiat Leak Rate',
                            value: '${data.fiatLeakRate.toStringAsFixed(1)}%',
                            subValue: 'of income spent',
                            valueColor:
                                data.fiatLeakRate > 80
                                    ? AppColors.danger
                                    : data.fiatLeakRate > 50
                                    ? AppColors.bitcoinOrange
                                    : AppColors.success,
                            icon: Icons.water_drop_outlined,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: StackGoalTile(
                            progress: data.stackGoalProgress,
                            currentSats: data.totalStackSats,
                            goalSats: data.stackGoalSats,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: MetricTile(
                            label: 'Inflation Cost',
                            value: CurrencyUtils.format(
                              data.inflationCostFiat,
                              currency,
                            ),
                            subValue:
                                'per month @ ${inflationRate % 1 == 0 ? inflationRate.toStringAsFixed(0) : inflationRate.toString()}%',
                            valueColor: AppColors.danger,
                            icon: Icons.trending_down_outlined,
                            iconColor: AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        ),
        const SizedBox(height: 20),

        // ── Wallet breakdown (only when ≥ 2 wallets have activity) ─────────
        StreamBuilder<List<WalletSummary>>(
          stream: perWallet,
          builder: (context, snapshot) {
            final summaries =
                (snapshot.data ?? []).where((s) => s.hasActivity).toList();
            if (summaries.length < 2) return const SizedBox.shrink();
            return Column(
              children: [
                _SectionHeader(title: 'Wallets'),
                _Live(
                  builder:
                      (context, btcPrice, currency) => _WalletBreakdownSection(
                        summaries: summaries,
                        btcPrice: btcPrice,
                        currency: currency,
                      ),
                ),
                const SizedBox(height: 20),
              ],
            );
          },
        ),

        // ── Spending breakdown ─────────────────────────────────────────────
        _SectionHeader(
          title: 'Spending Breakdown',
          action: data.spendingByCategory.isEmpty ? null : 'View Analytics',
          onAction: () => context.push('/analytics'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _Live(
                builder:
                    (context, btcPrice, currency) => SpendingChart(
                      spendingByCategory: data.spendingByCategory,
                      btcPrice: btcPrice,
                      currency: currency,
                      // The colours the user actually chose. The chart used to
                      // draw its own fixed palette and ignore them.
                      categoryColorHex: {
                        for (final e in categoriesByName.entries)
                          e.key: e.value.color,
                      },
                    ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ── Recent transactions ────────────────────────────────────────────
        _SectionHeader(
          title: 'Recent Transactions',
          action: data.recentTransactions.isEmpty ? null : 'See all',
          onAction: () => context.go('/transactions'),
        ),
        if (data.recentTransactions.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No transactions yet',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: context.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Column(
                children: [
                  for (int i = 0; i < data.recentTransactions.length; i++) ...[
                    _recentRow(data.recentTransactions[i]),
                    if (i < data.recentTransactions.length - 1)
                      const Divider(indent: 16, endIndent: 16),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: 20),

        // ── AI insight card ────────────────────────────────────────────────
        // Listens, rather than reading the notifier once: enabling AI in
        // Settings and coming back used to leave the card in its old state
        // until the Dashboard was rebuilt from scratch.
        ValueListenableBuilder<bool>(
          valueListenable: app.aiEnabledNotifier,
          builder:
              (_, aiEnabled, _) => AiInsightCard(
                aiEnabled: aiEnabled,
                cachedInsight: cachedInsight,
                isGenerating: isGeneratingInsight,
                onRefresh: onRefreshInsight,
                offDeviceRecipient: insightRecipient,
              ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// A row with stored sats shows them and never needs the live price, so
  /// only a row without them listens for it.
  Widget _recentRow(Transaction tx) {
    final category = categoriesByName[tx.category];
    if (tx.amountSats != 0) {
      return TransactionListItem(transaction: tx, category: category);
    }
    return _Live(
      builder:
          (context, btcPrice, _) => TransactionListItem(
            transaction: tx,
            category: category,
            btcPrice: btcPrice,
          ),
    );
  }

  String _satConversion(double fiat, double price) =>
      '≈ ${SatConverter.formatSats(SatConverter.fiatToSats(fiat, price))} sats';
}

// ── Wallet breakdown ──────────────────────────────────────────────────────────

class _WalletBreakdownSection extends StatelessWidget {
  const _WalletBreakdownSection({
    required this.summaries,
    required this.btcPrice,
    required this.currency,
  });

  final List<WalletSummary> summaries;
  final double? btcPrice;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Column(
          children: [
            for (int i = 0; i < summaries.length; i++) ...[
              _WalletRow(
                summary: summaries[i],
                btcPrice: btcPrice,
                currency: currency,
              ),
              if (i < summaries.length - 1)
                const Divider(indent: 16, endIndent: 16, height: 1),
            ],
          ],
        ),
      ),
    );
  }
}

class _WalletRow extends StatelessWidget {
  const _WalletRow({
    required this.summary,
    required this.btcPrice,
    required this.currency,
  });

  final WalletSummary summary;
  final double? btcPrice;
  final String currency;

  Color get _walletColor {
    try {
      final hex = summary.wallet.color.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return AppColors.bitcoinOrange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wallet = summary.wallet;

    final typeLabel = switch (wallet.type) {
      'xpub' => 'xpub',
      'csv' => 'CSV',
      _ => 'manual',
    };

    // Primary value: sats if any BTC, otherwise monthly fiat flow
    final String primaryValue;
    final String? secondaryValue;
    final Color? changeColor;

    if (summary.hasBitcoin) {
      primaryValue = _formatSats(summary.totalSats);
      final change = summary.monthChangeSats;
      if (change != 0) {
        final sign = change > 0 ? '+' : '';
        secondaryValue = '$sign${_formatSats(change)} this month';
        changeColor = change > 0 ? AppColors.success : AppColors.danger;
      } else {
        secondaryValue = null;
        changeColor = null;
      }
    } else {
      // Fiat-only wallet
      primaryValue = CurrencyUtils.format(summary.monthIncomeFiat, currency);
      if (summary.monthSpendFiat > 0) {
        secondaryValue =
            '${CurrencyUtils.format(summary.monthSpendFiat, currency)} spent';
        changeColor = context.textSecondary;
      } else {
        secondaryValue = null;
        changeColor = null;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Wallet colour dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _walletColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          // Label + type badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wallet.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: _walletColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    typeLabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: context.legibleAccent(_walletColor),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Values (right-aligned)
          ShrinkToFit(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  summary.hasBitcoin ? '$primaryValue sats' : primaryValue,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'RobotoMono',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (secondaryValue != null)
                  Text(
                    secondaryValue,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: changeColor ?? context.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                if (summary.hasBitcoin &&
                    btcPrice != null &&
                    btcPrice! > 0 &&
                    summary.totalSats != 0)
                  Text(
                    '≈ ${CurrencyUtils.formatCompact(summary.totalSats / 1e8 * btcPrice!, currency)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.textSecondary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatSats(int sats) => SatConverter.formatSats(sats.abs());
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Flexible, so a long title gives way to the action at large text
          // sizes instead of overflowing the row.
          Flexible(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (action != null && onAction != null)
            Tappable(
              onTap: onAction,
              child: Text(
                action!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.bitcoinOrangeText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
