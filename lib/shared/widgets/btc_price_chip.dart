import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/currency_utils.dart';
import 'tappable.dart';
import '../../core/services/btc_price_service.dart';
import '../../main.dart' as app;

/// A compact chip showing the current BTC/USD price with a last-updated
/// timestamp. Tapping triggers a manual refresh.
class BtcPriceChip extends StatefulWidget {
  const BtcPriceChip({super.key, required this.service});

  final BtcPriceService service;

  @override
  State<BtcPriceChip> createState() => _BtcPriceChipState();
}

class _BtcPriceChipState extends State<BtcPriceChip> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await widget.service.fetchAndCache(force: true);
    if (mounted) setState(() => _refreshing = false);
  }

  String _ageLabel(DateTime fetchedAt) {
    final diff = DateTime.now().difference(fetchedAt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d').format(fetchedAt);
  }

  /// [_ageLabel] for a screen reader, which reads "2m" as "two metres".
  String _spokenAge(DateTime fetchedAt) {
    final diff = DateTime.now().difference(fetchedAt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    }
    return 'on ${DateFormat('MMMM d').format(fetchedAt)}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: app.showBtcPriceNotifier,
      builder: (context, show, _) {
        if (!show) return const SizedBox.shrink();
        return _chip();
      },
    );
  }

  Widget _chip() {
    return ValueListenableBuilder<String>(
      valueListenable: app.currencyNotifier,
      builder: (context, currency, _) =>
          ValueListenableBuilder<double?>(
        valueListenable: widget.service.priceNotifier,
        builder: (context, price, _) {
          final lastUpdated = widget.service.lastFetchedAt;
          final symbol = CurrencyUtils.symbolFor(currency);

          return Tappable(
          label: price == null
              ? 'Bitcoin price not loaded'
              : 'Bitcoin price ${CurrencyUtils.format(price, currency, decimalDigits: 0)}'
                  '${lastUpdated == null ? '' : ', updated ${_spokenAge(lastUpdated)}'}',
          hint: 'Refreshes the price',
          onTap: _refreshing ? null : _refresh,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.bitcoinOrange.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.bitcoinOrange.withAlpha(70),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_refreshing)
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppColors.bitcoinOrange,
                    ),
                  )
                else
                  Text(
                    '₿',
                    style: AppTextStyles.monoSmall.copyWith(
                      color: context.bitcoinOrangeText,
                      fontSize: 11,
                    ),
                  ),
                const SizedBox(width: 5),
                if (price != null) ...[
                  Text(
                    NumberFormat.currency(
                      symbol: symbol,
                      decimalDigits: 0,
                    ).format(price),
                    style: AppTextStyles.monoSmall.copyWith(
                      color: context.bitcoinOrangeText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (lastUpdated != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      '· ${_ageLabel(lastUpdated)}',
                      style: AppTextStyles.monoSmall.copyWith(
                        color: context.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ] else
                  Text(
                    'no price',
                    style: AppTextStyles.monoSmall.copyWith(
                      color: context.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
    );
  }
}

