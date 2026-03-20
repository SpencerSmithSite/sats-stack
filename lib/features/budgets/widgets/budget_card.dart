import 'package:flutter/material.dart';
import '../../../core/models/budget_progress.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/utils/currency_utils.dart';

class BudgetCard extends StatelessWidget {
  const BudgetCard({
    super.key,
    required this.progress,
    required this.btcPrice,
    required this.currency,
    required this.onEdit,
    required this.onDelete,
  });

  final BudgetProgress progress;
  final double? btcPrice;
  final String currency;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _parseColor(progress.category.color) ?? AppColors.bitcoinOrange;

    final clampedProgress = progress.progress.clamp(0.0, 1.0);
    final progressColor = progress.isOverBudget
        ? AppColors.danger
        : progress.progress > 0.8
            ? AppColors.bitcoinOrange
            : AppColors.success;

    return GestureDetector(
      onLongPress: () => _showOptions(context),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: progress.isOverBudget
                ? AppColors.danger.withAlpha(80)
                : theme.colorScheme.outline.withAlpha(60),
            width: progress.isOverBudget ? 1.0 : 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────────────
            Row(
              children: [
                // Category colour dot
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    progress.category.name,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (progress.isOverBudget)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Over budget',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  Text(
                    progress.remainingFiat >= 0
                        ? '${CurrencyUtils.format(progress.remainingFiat, currency, decimalDigits: 0)} left'
                        : '',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: progressColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Progress bar ────────────────────────────────────────────────────
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: clampedProgress),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: value,
                    backgroundColor: progressColor.withAlpha(25),
                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                    minHeight: 8,
                  ),
                );
              },
            ),
            const SizedBox(height: 10),

            // ── Amounts row ─────────────────────────────────────────────────────
            Row(
              children: [
                Text(
                  CurrencyUtils.format(progress.spentFiat, currency, decimalDigits: 0),
                  style: AppTextStyles.monoSmall.copyWith(
                    color: progressColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  ' / ${CurrencyUtils.format(progress.budget.amountFiat, currency, decimalDigits: 0)}',
                  style: AppTextStyles.monoSmall.copyWith(color: AppColors.textSecondary),
                ),
                const Spacer(),
                // Sats opportunity cost
                if (btcPrice != null && btcPrice! > 0 && progress.spentFiat > 0)
                  _SatsCost(fiat: progress.spentFiat, btcPrice: btcPrice!),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text('Edit ${progress.category.name} budget'),
                onTap: () {
                  Navigator.pop(context);
                  onEdit();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.danger),
                title: Text(
                  'Delete budget',
                  style: const TextStyle(color: AppColors.danger),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onDelete();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Color? _parseColor(String hex) {
    final clean = hex.replaceFirst('#', '');
    if (clean.length != 6) return null;
    final value = int.tryParse('FF$clean', radix: 16);
    return value != null ? Color(value) : null;
  }
}

class _SatsCost extends StatelessWidget {
  const _SatsCost({required this.fiat, required this.btcPrice});

  final double fiat;
  final double btcPrice;

  @override
  Widget build(BuildContext context) {
    final sats = (fiat / btcPrice * 100000000).round();
    final formatted = sats
        .toString()
        .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.currency_bitcoin, size: 11, color: AppColors.bitcoinOrange),
        Text(
          '$formatted sats',
          style: AppTextStyles.monoSmall.copyWith(
            color: AppColors.bitcoinOrange,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
