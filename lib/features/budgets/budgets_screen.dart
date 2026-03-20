import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import '../../core/models/budget_progress.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_text_styles.dart';
import '../../shared/utils/currency_utils.dart';
import '../../shared/widgets/btc_price_chip.dart';
import '../../shared/widgets/empty_state.dart';
import 'widgets/budget_card.dart';
import 'widgets/set_budget_sheet.dart';
import '../../main.dart' as app;

/// One notification per category per month — tracked in-memory per session.
final _notifiedCategories = <String>{};

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  void _previousMonth() => setState(() {
        _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
      });

  void _nextMonth() => setState(() {
        _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
      });

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _selectedMonth.year == now.year && _selectedMonth.month == now.month;
  }

  void _openSetBudget({BudgetProgress? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SetBudgetSheet(
        budgetService: app.budgetService,
        categoryService: app.categoryService,
        existing: existing,
      ),
    );
  }

  void _deleteBudget(int id) async {
    await app.budgetService.deleteById(id);
  }

  void _checkNotifications(List<BudgetProgress> items) {
    for (final p in items) {
      if (!p.isOverBudget) continue;
      final key = '${p.category.name}_${_selectedMonth.year}_${_selectedMonth.month}';
      if (_notifiedCategories.contains(key)) continue;
      _notifiedCategories.add(key);
      _sendOverBudgetNotification(p);
    }
  }

  Future<void> _sendOverBudgetNotification(BudgetProgress p) async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      final currency = app.currencyNotifier.value;
      await plugin.show(
        p.budget.id,
        '${p.category.name} over budget',
        'Spent ${CurrencyUtils.format(p.spentFiat, currency, decimalDigits: 0)} of ${CurrencyUtils.format(p.budget.amountFiat, currency, decimalDigits: 0)} budget.',
        const NotificationDetails(
          macOS: DarwinNotificationDetails(subtitle: 'Sats Stack'),
        ),
      );
    } catch (_) {
      // Notifications unavailable (permission not granted or platform issue) — ignore.
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
        actions: [
          BtcPriceChip(service: app.btcPriceService),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<List<BudgetProgress>>(
        stream: app.budgetService.watchProgress(_selectedMonth),
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
                  Text('Failed to load budgets',
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? [];

          // Trigger over-budget notifications (only for current month)
          if (_isCurrentMonth) _checkNotifications(items);

          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No budgets set',
              subtitle: 'Set monthly spending limits per category to track your fiat leak.',
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
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openSetBudget(),
        backgroundColor: AppColors.bitcoinOrange,
        foregroundColor: Colors.white,
        tooltip: 'Add budget',
        child: const Icon(Icons.add),
      ),
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
    final totalBudgeted = items.fold<double>(0, (s, p) => s + p.budget.amountFiat);
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
    final remainingColor = remaining >= 0 ? AppColors.success : AppColors.danger;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outline.withAlpha(60), width: 0.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: _SummaryItem(
                label: 'Budgeted',
                value: CurrencyUtils.format(totalBudgeted, currency, decimalDigits: 0),
                color: AppColors.textSecondary,
              ),
            ),
            Container(width: 0.5, height: 32, color: theme.colorScheme.outline.withAlpha(80)),
            Expanded(
              child: _SummaryItem(
                label: 'Spent',
                value: CurrencyUtils.format(totalSpent, currency, decimalDigits: 0),
                color: theme.colorScheme.onSurface,
              ),
            ),
            Container(width: 0.5, height: 32, color: theme.colorScheme.outline.withAlpha(80)),
            Expanded(
              child: _SummaryItem(
                label: remaining >= 0 ? 'Remaining' : 'Over',
                value: CurrencyUtils.format(remaining.abs(), currency, decimalDigits: 0),
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
  const _SummaryItem({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppTextStyles.monoMedium.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

// ── Month selector (local copy for budgets) ───────────────────────────────────

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({required this.month, required this.onPrevious, this.onNext});

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onPrevious,
          child: Icon(Icons.chevron_left, size: 22, color: theme.colorScheme.onSurface),
        ),
        const SizedBox(width: 4),
        Text(
          DateFormat('MMMM yyyy').format(month),
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onNext,
          child: Icon(
            Icons.chevron_right,
            size: 22,
            color: onNext != null ? theme.colorScheme.onSurface : AppColors.textSecondary.withAlpha(80),
          ),
        ),
      ],
    );
  }
}
