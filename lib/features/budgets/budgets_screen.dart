import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/budget_progress.dart';
import '../../main.dart' as app;
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_text_styles.dart';
import '../../shared/utils/currency_utils.dart';
import '../../shared/utils/month_cursor.dart';
import '../../shared/widgets/btc_price_chip.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/month_selector.dart';
import 'widgets/budget_card.dart';
import 'widgets/set_budget_sheet.dart';

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  // One subscription, owned by the state rather than by `build()`.
  //
  // `watchProgress` returns a new stream per call, so a StreamBuilder fed from
  // build() re-subscribed — and re-ran the aggregate — on every currency and
  // BTC price tick, flashing a spinner each time. Holding the latest value
  // here also gives the overspend check somewhere legitimate to live: it used
  // to fire a notification from inside build().
  StreamSubscription<List<BudgetProgress>>? _progressSub;
  List<BudgetProgress>? _items; // null until the first event
  Object? _error;

  @override
  void initState() {
    super.initState();
    _subscribe();
    // Spending is converted into the display currency before it is compared
    // with a budget, so a currency switch needs a fresh read.
    app.currencyNotifier.addListener(_subscribe);
  }

  @override
  void dispose() {
    app.currencyNotifier.removeListener(_subscribe);
    _progressSub?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _progressSub?.cancel();
    _items = null;
    _error = null;
    _progressSub = app.budgetService
        .watchProgress(_selectedMonth)
        .listen(
          (items) {
            if (!mounted) return;
            setState(() {
              _items = items;
              _error = null;
            });
            if (_isCurrentMonth) _notifyOverspend();
          },
          onError: (Object e) {
            if (mounted) setState(() => _error = e);
          },
        );
  }

  void _previousMonth() => setState(() {
    _selectedMonth = MonthCursor(_selectedMonth).previous.month;
    _subscribe();
  });

  void _nextMonth() => setState(() {
    _selectedMonth = MonthCursor(_selectedMonth).next.month;
    _subscribe();
  });

  bool get _isCurrentMonth => MonthCursor(_selectedMonth).isCurrent();

  void _openSetBudget({BudgetProgress? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => SetBudgetSheet(
            budgetService: app.budgetService,
            categoryService: app.categoryService,
            existing: existing,
          ),
    );
  }

  Future<void> _deleteBudget(int id) async {
    await app.budgetService.deleteById(id);
  }

  /// Hands the check to [BudgetService], which goes through
  /// [NotificationService].
  ///
  /// The screen used to raise these itself from a bare
  /// `FlutterLocalNotificationsPlugin()` — never initialised, so on iOS no
  /// permission had been asked for and nothing appeared — keyed on
  /// `p.budget.id`, which can collide with the stack-goal id, and deduplicated
  /// by a module-level Set that was never cleared, so re-exceeding a budget in
  /// the same month never alerted again. main.dart already runs this same
  /// check on every transaction change; this catches the other case, a budget
  /// lowered below what has already been spent.
  void _notifyOverspend() {
    app.budgetService
        .checkAndNotify(
          notifications: app.notificationService,
          currency: app.currencyNotifier.value,
        )
        .ignore();
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
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(context),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openSetBudget(),
        backgroundColor: AppColors.bitcoinOrange,
        foregroundColor: Colors.white,
        tooltip: 'Add budget',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error.withAlpha(160),
            ),
            const SizedBox(height: 12),
            Text(
              'Failed to load budgets',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      );
    }

    final items = _items;
    if (items == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: 'No budgets set',
        subtitle:
            'Set monthly spending limits per category to track your fiat leak.',
        actionLabel: 'Set a Budget',
        onAction: () => _openSetBudget(),
      );
    }

    return ValueListenableBuilder<String>(
      valueListenable: app.currencyNotifier,
      builder: (context, currency, _) {
        return ValueListenableBuilder<double?>(
          valueListenable: app.btcPriceService.priceNotifier,
          builder: (context, btcPrice, _) {
            return _BudgetList(
              items: items,
              btcPrice: btcPrice,
              currency: currency,
              onEdit: (p) => _openSetBudget(existing: p),
              onDelete: (id) => _deleteBudget(id),
            );
          },
        );
      },
    );
  }
}

// ── Budget list with summary header ──────────────────────────────────────────

class _BudgetList extends StatelessWidget {
  const _BudgetList({
    required this.items,
    required this.btcPrice,
    required this.currency,
    required this.onEdit,
    required this.onDelete,
  });

  final List<BudgetProgress> items;
  final double? btcPrice;
  final String currency;
  final void Function(BudgetProgress) onEdit;
  final void Function(int id) onDelete;

  @override
  Widget build(BuildContext context) {
    final totalBudgeted = items.fold<double>(
      0,
      (s, p) => s + p.budget.amountFiat,
    );
    final totalSpent = items.fold<double>(0, (s, p) => s + p.spentFiat);
    final overCount = items.where((p) => p.isOverBudget).length;

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        const SizedBox(height: 12),
        _SummaryBar(
          totalBudgeted: totalBudgeted,
          totalSpent: totalSpent,
          overCount: overCount,
          btcPrice: btcPrice,
          currency: currency,
        ),
        const SizedBox(height: 8),
        for (final p in items)
          BudgetCard(
            key: ValueKey(p.budget.id),
            progress: p,
            btcPrice: btcPrice,
            currency: currency,
            onEdit: () => onEdit(p),
            onDelete: () => onDelete(p.budget.id),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

// ── Summary bar ───────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.totalBudgeted,
    required this.totalSpent,
    required this.overCount,
    required this.btcPrice,
    required this.currency,
  });

  final double totalBudgeted;
  final double totalSpent;
  final int overCount;
  final double? btcPrice;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = totalBudgeted - totalSpent;
    final remainingColor =
        remaining >= 0 ? AppColors.success : AppColors.danger;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
            Expanded(
              child: _SummaryItem(
                label: 'Budgeted',
                value: CurrencyUtils.format(
                  totalBudgeted,
                  currency,
                  decimalDigits: 0,
                ),
                color: context.textSecondary,
              ),
            ),
            Container(
              width: 0.5,
              height: 32,
              color: theme.colorScheme.outline.withAlpha(80),
            ),
            Expanded(
              child: _SummaryItem(
                label: 'Spent',
                value: CurrencyUtils.format(
                  totalSpent,
                  currency,
                  decimalDigits: 0,
                ),
                color: theme.colorScheme.onSurface,
              ),
            ),
            Container(
              width: 0.5,
              height: 32,
              color: theme.colorScheme.outline.withAlpha(80),
            ),
            Expanded(
              child: _SummaryItem(
                label: remaining >= 0 ? 'Remaining' : 'Over',
                value: CurrencyUtils.format(
                  remaining.abs(),
                  currency,
                  decimalDigits: 0,
                ),
                color: remainingColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppTextStyles.monoMedium.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
