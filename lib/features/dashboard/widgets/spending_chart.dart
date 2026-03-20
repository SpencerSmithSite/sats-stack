import 'package:flutter/material.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/utils/currency_utils.dart';
import '../../../shared/utils/sat_converter.dart';

class SpendingChart extends StatelessWidget {
  const SpendingChart({
    super.key,
    required this.spendingByCategory,
    this.btcPrice,
    required this.currency,
  });

  final Map<String, double> spendingByCategory;
  final double? btcPrice;
  final String currency;

  @override
  Widget build(BuildContext context) {
    if (spendingByCategory.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No spending this month',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ),
      );
    }

    // Sort by amount descending, take top 6
    final sorted = spendingByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final entries = sorted.take(6).toList();
    final maxAmount = entries.first.value;

    return Column(
      children: [
        for (final entry in entries)
          _CategoryBar(
            category: entry.key,
            amount: entry.value,
            maxAmount: maxAmount,
            btcPrice: btcPrice,
            currency: currency,
          ),
      ],
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.category,
    required this.amount,
    required this.maxAmount,
    this.btcPrice,
    required this.currency,
  });

  final String category;
  final double amount;
  final double maxAmount;
  final double? btcPrice;
  final String currency;

  static const _categoryColors = <String, Color>{
    'Food & Dining': Color(0xFFE24B4A),
    'Transport': Color(0xFFF7931A),
    'Housing': Color(0xFF888780),
    'Shopping': Color(0xFF6E8ECC),
    'Subscriptions': Color(0xFF9B6FCF),
    'Entertainment': Color(0xFF1D9E75),
    'Bitcoin': Color(0xFFF7931A),
    'Income': Color(0xFF1D9E75),
    'Other': Color(0xFF888780),
  };

  @override
  Widget build(BuildContext context) {
    final barFraction = maxAmount > 0 ? (amount / maxAmount) : 0.0;
    final color = _categoryColors[category] ?? AppColors.textSecondary;
    final fiatStr = CurrencyUtils.format(amount, currency, decimalDigits: 0);
    final sats = btcPrice != null && btcPrice! > 0
        ? SatConverter.fiatToSats(amount, btcPrice!)
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          // Category name
          SizedBox(
            width: 100,
            child: Text(
              category,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Bar
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Stack(
                    children: [
                      Container(
                        height: 20,
                        decoration: BoxDecoration(
                          color: color.withAlpha(25),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: barFraction,
                        child: Container(
                          height: 20,
                          decoration: BoxDecoration(
                            color: color.withAlpha(180),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          // Amount
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                fiatStr,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (sats != null)
                Text(
                  '${SatConverter.formatSats(sats)} sats',
                  style: AppTextStyles.monoSmall.copyWith(
                    color: AppColors.bitcoinOrange,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
