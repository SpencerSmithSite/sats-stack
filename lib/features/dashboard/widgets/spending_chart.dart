import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/theme/category_palette.dart';
import '../../../shared/utils/currency_utils.dart';
import '../../../shared/utils/sat_converter.dart';
import '../../../shared/widgets/shrink_to_fit.dart';

class SpendingChart extends StatelessWidget {
  const SpendingChart({
    super.key,
    required this.spendingByCategory,
    this.btcPrice,
    required this.currency,
    this.categoryColorHex = const {},
  });

  final Map<String, double> spendingByCategory;
  final double? btcPrice;
  final String currency;

  /// Category name → the colour the user chose in Settings → Categories.
  /// Empty is fine; [CategoryPalette] has a default for every name.
  final Map<String, String> categoryColorHex;

  @override
  Widget build(BuildContext context) {
    if (spendingByCategory.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No spending this month',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: context.textSecondary),
          ),
        ),
      );
    }

    // Sort by amount descending, take top 6
    final sorted =
        spendingByCategory.entries.toList()
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
            categoryColorHex: categoryColorHex[entry.key],
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
    this.categoryColorHex,
    this.btcPrice,
    required this.currency,
  });

  final String category;
  final String? categoryColorHex;
  final double amount;
  final double maxAmount;
  final double? btcPrice;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final barFraction = maxAmount > 0 ? (amount / maxAmount) : 0.0;
    // One palette for the whole app; this widget used to keep its own,
    // which disagreed with Analytics on Shopping and Subscriptions.
    final color = CategoryPalette.of(category, userHex: categoryColorHex);
    final fiatStr = CurrencyUtils.format(amount, currency, decimalDigits: 0);
    final sats =
        btcPrice != null && btcPrice! > 0
            ? SatConverter.fiatToSats(amount, btcPrice!)
            : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          // Category name. Its width follows the text size, so a large
          // accessibility setting does not cut every name to two letters —
          // but never more than a third of the row, so the bar survives.
          SizedBox(
            width: math.min(
              MediaQuery.textScalerOf(context).scale(100),
              MediaQuery.sizeOf(context).width / 3,
            ),
            child: Text(
              category,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.textSecondary),
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
          ShrinkToFit(
            maxFraction: 0.3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  fiatStr,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (sats != null)
                  Text(
                    '${SatConverter.formatSats(sats)} sats',
                    style: AppTextStyles.monoSmall.copyWith(
                      color: context.bitcoinOrangeText,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
