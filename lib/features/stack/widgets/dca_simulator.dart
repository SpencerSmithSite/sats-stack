/// The DCA simulator: what a fixed recurring buy would have accumulated.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/utils/amount_input.dart';
import '../../../shared/utils/currency_utils.dart';
import '../../../shared/utils/sat_converter.dart';
import '../../../shared/widgets/shrink_to_fit.dart';
import 'period_chip.dart';

class DcaSimulator extends StatelessWidget {
  const DcaSimulator({
    super.key,
    required this.btcPrice,
    required this.controller,
    required this.years,
    required this.onYearsChanged,
    required this.currency,
  });

  final double? btcPrice;

  /// See `StackHero.currency`.
  final String currency;
  final TextEditingController controller;
  final int years;
  final ValueChanged<int> onYearsChanged;

  static const _yearOptions = [1, 2, 5, 10];

  static const _scenarios = [
    (label: 'Conservative', rate: 0.0, color: AppColors.success),
    (label: 'Moderate', rate: 0.20, color: AppColors.bitcoinOrange),
    (label: 'Optimistic', rate: 0.40, color: Color(0xFF6AB0E8)),
  ];

  int _simulate(
    double monthlyAmount,
    double startPrice,
    int months,
    double annualRate,
  ) {
    if (startPrice <= 0) return 0;
    int total = 0;
    for (int n = 0; n < months; n++) {
      final price = startPrice * pow(1 + annualRate, n / 12);
      total += (monthlyAmount / price * 1e8).round();
    }
    return total;
  }

  /// What [sats] would be worth at the end of [months] at [annualRate].
  ///
  /// Each scenario's sats are valued at the price that scenario assumes. All
  /// three used to be valued at *today's* price, so the scenario that assumed
  /// the most growth — and so bought the fewest sats — showed the smallest
  /// figure, and "Optimistic" read as the worst outcome.
  static double endValue(
    int sats,
    double startPrice,
    int months,
    double annualRate,
  ) => sats / 1e8 * startPrice * pow(1 + annualRate, months / 12);

  @override
  Widget build(BuildContext context) {
    // Rebuilt as the amount is typed. It read the controller only when
    // something else rebuilt the screen, so typing a new amount changed
    // nothing until the period was tapped.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final price = btcPrice ?? 0;
    final monthly = parseUserAmount(controller.text) ?? 0;
    final months = years * 12;
    final totalInvested = monthly * months;
    final fiatFmt = NumberFormat.currency(
      symbol: CurrencyUtils.symbolFor(currency),
      decimalDigits: 0,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Inputs — the field, then the period chips beneath it. Side by
              // side, the four chips beside the field overflowed a small
              // phone at a large text size (audit U-7).
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: TextField(
                      controller: controller,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [amountInputFormatter],
                      style: AppTextStyles.monoMedium.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Monthly DCA',
                        prefixText: '${CurrencyUtils.symbolFor(currency)} ',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Period',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    children: [
                      for (final y in _yearOptions)
                        PeriodChip(
                          label: '${y}y',
                          selected: years == y,
                          onTap: () => onYearsChanged(y),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (price <= 0)
                Text(
                  'BTC price unavailable — open the app with internet to fetch price.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.textSecondary,
                  ),
                )
              else ...[
                // Total invested line
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Total invested:',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      fiatFmt.format(totalInvested),
                      style: AppTextStyles.monoSmall.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // Scenario rows
                for (final s in _scenarios) ...[
                  Builder(
                    builder: (_) {
                      final sats = _simulate(monthly, price, months, s.rate);
                      return ScenarioRow(
                        label: s.label,
                        rate: s.rate,
                        color: s.color,
                        sats: sats,
                        value: endValue(sats, price, months, s.rate),
                        currency: currency,
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 4),
                Text(
                  'Conservative = 0%/yr · Moderate = 20%/yr · Optimistic = 40%/yr BTC price appreciation. Each value is at that scenario\'s price at the end of the period.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.textSecondary,
                    fontSize: 10,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ScenarioRow extends StatelessWidget {
  const ScenarioRow({
    super.key,
    required this.label,
    required this.rate,
    required this.color,
    required this.sats,
    required this.value,
    required this.currency,
  });

  final String label;
  final String currency;
  final double rate;
  final Color color;
  final int sats;

  /// What [sats] are worth at the end of the period, in [currency].
  final double value;

  @override
  Widget build(BuildContext context) {
    final fiatFmt = NumberFormat.currency(
      symbol: CurrencyUtils.symbolFor(currency),
      decimalDigits: 0,
    );
    final fiatValue = fiatFmt.format(value);
    final satsStr = SatConverter.formatSats(sats);

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Text(
            '$satsStr sats',
            style: AppTextStyles.monoSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // Scaled down rather than pushed off the edge (audit U-7).
        ShrinkToFit(
          maxFraction: 0.3,
          child: Text(
            '≈ $fiatValue',
            style: AppTextStyles.monoSmall.copyWith(
              color: context.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
