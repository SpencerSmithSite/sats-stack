import 'package:flutter/material.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/utils/currency_utils.dart';
import '../../../shared/utils/sat_converter.dart';

class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.totalStackSats,
    required this.monthChangeSats,
    required this.btcPrice,
    required this.currency,
  });

  final int totalStackSats;
  final int monthChangeSats;
  final double? btcPrice;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final fiatValue = btcPrice != null && btcPrice! > 0
        ? SatConverter.satsToFiat(totalStackSats, btcPrice!)
        : null;

    final isPositiveChange = monthChangeSats >= 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE8840F), AppColors.bitcoinOrange],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.bitcoinOrange.withAlpha(80),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total Stack',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withAlpha(180),
                  letterSpacing: 0.5,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            totalStackSats == 0
                ? '0 sats'
                : '${SatConverter.formatSats(totalStackSats)} sats',
            style: AppTextStyles.heroSats.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (fiatValue != null)
                Text(
                  '≈ ${CurrencyUtils.format(fiatValue, currency)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withAlpha(200),
                      ),
                ),
              if (fiatValue != null && monthChangeSats != 0)
                Text(
                  '  ·  ',
                  style: TextStyle(color: Colors.white.withAlpha(120)),
                ),
              if (monthChangeSats != 0) ...[
                Icon(
                  isPositiveChange
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 12,
                  color: Colors.white.withAlpha(200),
                ),
                const SizedBox(width: 2),
                Text(
                  '${SatConverter.formatSats(monthChangeSats.abs())} sats this month',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withAlpha(200),
                      ),
                ),
              ],
            ],
          ),
          if (totalStackSats == 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Import a Bitcoin wallet to track your stack',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withAlpha(220),
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
