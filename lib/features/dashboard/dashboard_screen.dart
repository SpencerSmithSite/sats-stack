import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/dashboard_data.dart';
import '../../core/models/wallet_summary.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/btc_price_chip.dart';
import '../../features/transactions/widgets/transaction_list_item.dart';
import '../../core/services/category_service.dart';
import '../../shared/utils/currency_utils.dart';
import 'widgets/month_selector.dart';
import 'widgets/hero_card.dart';
import 'widgets/metric_tile.dart';
import 'widgets/spending_chart.dart';
import 'widgets/ai_insight_card.dart';
import '../../main.dart' as app;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DateTime _selectedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );

  String? _cachedInsight;
  bool _isGeneratingInsight = false;

  @override
  void initState() {
    super.initState();
    if (app.aiEnabledNotifier.value) _initInsight();
  }

  Future<void> _initInsight() async {
    _cachedInsight = await app.ollamaService.loadCachedInsight();
    if (mounted) setState(() {});
    final stale = await app.ollamaService.isInsightStale();
    if (stale) _generateInsight();
  }

  Future<void> _generateInsight() async {
    if (_isGeneratingInsight) return;
    final available = await app.ollamaService.isAvailable();
    if (!available || !mounted) return;

    setState(() => _isGeneratingInsight = true);
    try {
      final now = DateTime.now();
      final lastMonth = DateTime(now.year, now.month - 1);
      final data = await app.dashboardService.getDashboard(lastMonth);
      final btcPrice = app.btcPriceService.priceNotifier.value ?? 0;
      final insight = await app.ollamaService.generateMonthlyInsight(
        totalStackSats: data.totalStackSats,
        btcPrice: btcPrice,
        monthlyIncome: data.monthlyIncomeFiat,
        monthlySpending: data.monthlySpendingFiat,
        monthlySurplus: data.monthlySurplusFiat,
        spendingByCategory: data.spendingByCategory,
        stackGoalSats: data.stackGoalSats,
      );
      if (mounted) setState(() => _cachedInsight = insight);
    } catch (_) {
      // Insight generation is best-effort — fail silently
    } finally {
      if (mounted) setState(() => _isGeneratingInsight = false);
    }
  }

  void _previousMonth() {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month - 1,
      );
    });
  }

  void _nextMonth() {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + 1,
      );
    });
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _selectedMonth.year == now.year && _selectedMonth.month == now.month;
  }

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
      body: StreamBuilder<DashboardData>(
        stream: app.dashboardService.watchDashboard(_selectedMonth),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorState(message: snapshot.error.toString());
          }
          final data = snapshot.data ?? DashboardData.empty;
          return ValueListenableBuilder<double?>(
            valueListenable: app.btcPriceService.priceNotifier,
            builder: (context, btcPrice, _) {
              return ValueListenableBuilder<String>(
                valueListenable: app.currencyNotifier,
                builder: (context, currency, _) {
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    switchInCurve: Curves.easeOut,
                    child: _DashboardContent(
                      key: ValueKey(_selectedMonth),
                      data: data,
                      btcPrice: btcPrice,
                      currency: currency,
                      categoryService: app.categoryService,
                      selectedMonth: _selectedMonth,
                      cachedInsight: _cachedInsight,
                      isGeneratingInsight: _isGeneratingInsight,
                      onRefreshInsight: _generateInsight,
                    ),
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
            Icon(Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error.withAlpha(160)),
            const SizedBox(height: 16),
            Text('Something went wrong',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    super.key,
    required this.data,
    required this.btcPrice,
    required this.currency,
    required this.categoryService,
    required this.selectedMonth,
    this.cachedInsight,
    this.isGeneratingInsight = false,
    this.onRefreshInsight,
  });

  final DashboardData data;
  final double? btcPrice;
  final String currency;
  final CategoryService categoryService;
  final DateTime selectedMonth;
  final String? cachedInsight;
  final bool isGeneratingInsight;
  final VoidCallback? onRefreshInsight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const SizedBox(height: 8),

        // ── Hero card ─────────────────────────────────────────────────────
        HeroCard(
          totalStackSats: data.totalStackSats,
          monthChangeSats: data.monthStackChangeSats,
          btcPrice: btcPrice,
          currency: currency,
        ),
        const SizedBox(height: 16),

        // ── 2×2 Metric grid ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: MetricTile(
                  label: 'Monthly Surplus',
                  value: CurrencyUtils.format(data.monthlySurplusFiat, currency),
                  subValue: btcPrice != null && btcPrice! > 0
                      ? _satConversion(data.monthlySurplusFiat.abs(), btcPrice!)
                      : null,
                  valueColor: data.monthlySurplusFiat >= 0
                      ? AppColors.success
                      : AppColors.danger,
                  icon: Icons.savings_outlined,
                  iconColor: data.monthlySurplusFiat >= 0
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
                  valueColor: data.fiatLeakRate > 80
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
                  value: CurrencyUtils.format(data.inflationCostFiat, currency),
                  subValue: 'per month @ 3.5%',
                  valueColor: AppColors.danger,
                  icon: Icons.trending_down_outlined,
                  iconColor: AppColors.danger,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Wallet breakdown (only when ≥ 2 wallets have activity) ─────────
        StreamBuilder<List<WalletSummary>>(
          stream: app.dashboardService.watchPerWallet(selectedMonth),
          builder: (context, snapshot) {
            final summaries = (snapshot.data ?? [])
                .where((s) => s.hasActivity)
                .toList();
            if (summaries.length < 2) return const SizedBox.shrink();
            return Column(
              children: [
                _SectionHeader(title: 'Wallets'),
                _WalletBreakdownSection(
                  summaries: summaries,
                  btcPrice: btcPrice,
                  currency: currency,
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
              child: SpendingChart(
                spendingByCategory: data.spendingByCategory,
                btcPrice: btcPrice,
                currency: currency,
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
                      color: AppColors.textSecondary,
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
              child: FutureBuilder(
                future: categoryService.getAll(),
                builder: (context, snapshot) {
                  final cats = snapshot.data ?? [];
                  return Column(
                    children: [
                      for (int i = 0;
                          i < data.recentTransactions.length;
                          i++) ...[
                        TransactionListItem(
                          transaction: data.recentTransactions[i],
                          category: cats
                              .where((c) =>
                                  c.name ==
                                  data.recentTransactions[i].category)
                              .firstOrNull,
                          btcPrice: btcPrice,
                        ),
                        if (i < data.recentTransactions.length - 1)
                          const Divider(indent: 16, endIndent: 16),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        const SizedBox(height: 20),

        // ── AI insight card ────────────────────────────────────────────────
        AiInsightCard(
          cachedInsight: cachedInsight,
          isGenerating: isGeneratingInsight,
          onRefresh: onRefreshInsight,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  String _satConversion(double fiat, double price) {
    final sats = (fiat / price * 100000000).round();
    final formatted = sats
        .toString()
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
    return '≈ $formatted sats';
  }
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
        changeColor = AppColors.textSecondary;
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
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: _walletColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    typeLabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: _walletColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Values (right-aligned)
          Column(
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
                    color: changeColor ?? AppColors.textSecondary,
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
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatSats(int sats) => sats
      .abs()
      .toString()
      .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.action,
    this.onAction,
  });

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
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (action != null && onAction != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                action!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.bitcoinOrange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
