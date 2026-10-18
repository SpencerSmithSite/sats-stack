/// The total-stack hero card at the top of the Stack tab, and the month-change
/// line under it.
library;

import 'package:flutter/material.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/utils/currency_utils.dart';
import '../../../shared/utils/sat_converter.dart';
import '../../../main.dart' as app;
import '../../../shared/theme/app_text_styles.dart';
import 'package:intl/intl.dart';

class StackHero extends StatelessWidget {
  const StackHero({
    super.key,required this.totalSats, required this.monthSats, this.btcPrice});

  final int totalSats;
  final int monthSats;
  final double? btcPrice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fiatFmt = NumberFormat.currency(symbol: CurrencyUtils.symbolFor(app.currencyNotifier.value), decimalDigits: 0);
    final fiatValue = btcPrice != null && btcPrice! > 0
        ? fiatFmt.format(totalSats / 1e8 * btcPrice!)
        : '--';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // An orange wash over the theme's own surface. The fixed 0xFF1A1200 →
        // 0xFF2A1F00 gradient underneath white text was a survivor of the
        // light-mode pass: in light mode it stayed a dark brown slab.
        gradient: LinearGradient(
          colors: [
            Color.alphaBlend(AppColors.bitcoinOrange.withAlpha(20),
                theme.colorScheme.surfaceContainerHighest),
            Color.alphaBlend(AppColors.bitcoinOrange.withAlpha(48),
                theme.colorScheme.surfaceContainerHighest),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.bitcoinOrange.withAlpha(60),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.currency_bitcoin, size: 14, color: AppColors.bitcoinOrange),
              const SizedBox(width: 4),
              Text(
                'Total Stack',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.bitcoinOrange,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _formatSats(totalSats),
            style: AppTextStyles.heroSats
                .copyWith(color: theme.colorScheme.onSurface),
          ),
          Text(
            'sats',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '≈ $fiatValue',
                style: AppTextStyles.monoMedium.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(200),
                ),
              ),
              const Spacer(),
              if (monthSats != 0)
                MonthChange(sats: monthSats),
            ],
          ),
        ],
      ),
    );
  }

  String _formatSats(int sats) => SatConverter.formatSats(sats);
}

class MonthChange extends StatelessWidget {
  const MonthChange({
    super.key,required this.sats});
  final int sats;

  @override
  Widget build(BuildContext context) {
    final positive = sats > 0;
    final color = positive ? AppColors.success : AppColors.danger;
    final formatted = SatConverter.formatSatsSigned(sats);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(positive ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: color),
        const SizedBox(width: 2),
        Text(
          '$formatted sats this month',
          style: AppTextStyles.monoSmall.copyWith(color: color, fontSize: 11),
        ),
      ],
    );
  }
}
