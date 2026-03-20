/// Utilities for converting between fiat and satoshis.
abstract final class SatConverter {
  static const _satsPerBtc = 100000000;

  /// Convert a fiat amount to satoshis given a BTC price in fiat.
  static int fiatToSats(double fiatAmount, double btcPriceFiat) {
    if (btcPriceFiat <= 0) return 0;
    return (fiatAmount / btcPriceFiat * _satsPerBtc).round();
  }

  /// Convert satoshis to fiat given a BTC price in fiat.
  static double satsToFiat(int sats, double btcPriceFiat) {
    return sats / _satsPerBtc * btcPriceFiat;
  }

  /// Format sat amount for display: e.g. 1,234,567 sats
  static String formatSats(int sats) {
    final abs = sats.abs();
    final formatted = abs.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
    return sats < 0 ? '-$formatted' : formatted;
  }
}
