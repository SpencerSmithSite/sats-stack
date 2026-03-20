import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/sat_converter.dart';

/// Displays a fiat amount as the primary label and its sat equivalent below.
/// Pass [btcPrice] = 0 or null to hide the sat conversion line.
class SatAmountDisplay extends StatelessWidget {
  const SatAmountDisplay({
    super.key,
    required this.amountFiat,
    required this.currency,
    this.amountSats,
    this.btcPrice,
    this.isNegative = false,
    this.fiatStyle,
    this.satsStyle,
    this.textAlign = TextAlign.end,
  });

  final double amountFiat;
  final String currency;
  final int? amountSats;
  final double? btcPrice;
  final bool isNegative;
  final TextStyle? fiatStyle;
  final TextStyle? satsStyle;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final fiatFmt = NumberFormat.currency(
      symbol: _symbolFor(currency),
      decimalDigits: 2,
    );
    final sign = isNegative ? '-' : '';
    final fiatString = '$sign${fiatFmt.format(amountFiat.abs())}';

    final effectiveSats = amountSats ??
        (btcPrice != null && btcPrice! > 0
            ? SatConverter.fiatToSats(amountFiat.abs(), btcPrice!)
            : null);

    final satsString = effectiveSats != null
        ? '${isNegative ? '-' : ''}${SatConverter.formatSats(effectiveSats)} sats'
        : null;

    return Column(
      crossAxisAlignment: textAlign == TextAlign.end
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          fiatString,
          style: fiatStyle ??
              Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isNegative
                        ? Theme.of(context).colorScheme.onSurface
                        : AppColors.success,
                  ),
          textAlign: textAlign,
        ),
        if (satsString != null)
          Text(
            satsString,
            style: satsStyle ??
                AppTextStyles.monoSmall.copyWith(
                  color: AppColors.bitcoinOrange,
                ),
            textAlign: textAlign,
          ),
      ],
    );
  }

  static String _symbolFor(String currency) {
    switch (currency.toUpperCase()) {
      case 'USD':
        return r'$';
      case 'GBP':
        return '£';
      case 'EUR':
        return '€';
      case 'CAD':
        return r'CA$';
      case 'AUD':
        return r'A$';
      default:
        return '$currency ';
    }
  }
}
