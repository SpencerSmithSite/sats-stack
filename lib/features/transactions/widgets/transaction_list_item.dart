import 'package:flutter/material.dart';
import '../../../core/database/database.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/utils/sat_converter.dart';

class TransactionListItem extends StatelessWidget {
  const TransactionListItem({
    super.key,
    required this.transaction,
    required this.category,
    this.btcPrice,
    this.onTap,
    this.onLongPress,
  });

  final Transaction transaction;
  final Category? category;
  final double? btcPrice;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExpense = transaction.amountFiat < 0;
    final isBtc = transaction.isBitcoin;

    final catColor = _parseColor(category?.color) ??
        (isBtc ? AppColors.bitcoinOrange : AppColors.textSecondary);

    final satsDisplay = transaction.amountSats != 0
        ? SatConverter.formatSats(transaction.amountSats.abs())
        : (btcPrice != null && btcPrice! > 0
            ? SatConverter.formatSats(
                SatConverter.fiatToSats(
                  transaction.amountFiat.abs(),
                  btcPrice!,
                ),
              )
            : null);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Category icon dot
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: catColor.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _iconData(category?.icon),
                size: 18,
                color: catColor,
              ),
            ),
            const SizedBox(width: 12),

            // Description + category
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.description.isEmpty
                        ? '—'
                        : transaction.description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: isBtc ? AppColors.bitcoinOrange : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (category != null || transaction.recurringPeriod != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (category != null)
                          Text(
                            category!.name,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        if (transaction.recurringPeriod != null) ...[
                          if (category != null) const SizedBox(width: 4),
                          Icon(
                            Icons.repeat,
                            size: 11,
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Amounts
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isExpense ? '-' : '+'}${_fiatString(transaction.amountFiat.abs(), transaction.fiatCurrency)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isExpense
                        ? theme.colorScheme.onSurface
                        : AppColors.success,
                  ),
                ),
                if (satsDisplay != null)
                  Text(
                    '${isExpense ? '-' : '+'}$satsDisplay sats',
                    style: AppTextStyles.monoSmall.copyWith(
                      color: AppColors.bitcoinOrange,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fiatString(double amount, String currency) {
    final symbols = {
      'USD': r'$',
      'GBP': '£',
      'EUR': '€',
      'CAD': r'CA$',
      'AUD': r'A$',
    };
    final sym = symbols[currency.toUpperCase()] ?? '$currency ';
    return '$sym${amount.toStringAsFixed(2)}';
  }

  Color? _parseColor(String? hex) {
    if (hex == null) return null;
    final clean = hex.replaceFirst('#', '');
    if (clean.length != 6) return null;
    final value = int.tryParse('FF$clean', radix: 16);
    return value != null ? Color(value) : null;
  }

  IconData _iconData(String? name) {
    const map = <String, IconData>{
      'restaurant': Icons.restaurant,
      'coffee': Icons.coffee,
      'directions_car': Icons.directions_car,
      'local_gas_station': Icons.local_gas_station,
      'flight': Icons.flight,
      'home': Icons.home,
      'bed': Icons.bed,
      'shopping_bag': Icons.shopping_bag,
      'shopping_cart': Icons.shopping_cart,
      'subscriptions': Icons.subscriptions,
      'movie': Icons.movie,
      'sports_esports': Icons.sports_esports,
      'fitness_center': Icons.fitness_center,
      'local_hospital': Icons.local_hospital,
      'school': Icons.school,
      'work': Icons.work,
      'computer': Icons.computer,
      'phone_android': Icons.phone_android,
      'currency_bitcoin': Icons.currency_bitcoin,
      'payments': Icons.payments,
      'savings': Icons.savings,
      'attach_money': Icons.attach_money,
      'pets': Icons.pets,
      'child_care': Icons.child_care,
      'park': Icons.park,
      'celebration': Icons.celebration,
      'card_giftcard': Icons.card_giftcard,
      'more_horiz': Icons.more_horiz,
    };
    return map[name] ?? Icons.receipt_long;
  }
}
