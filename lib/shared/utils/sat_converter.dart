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

  static final _thousands = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');

  /// Thousands-separated, e.g. `1,234,567`. Negative values keep their sign.
  ///
  /// This regex was hand-rolled in a dozen places, several of which differed
  /// in whether they kept the sign, so the same number could appear with and
  /// without its minus on two screens.
  static String formatSats(int sats) {
    final formatted = _groupDigits(sats.abs());
    return sats < 0 ? '-$formatted' : formatted;
  }

  /// Always signed, e.g. `+1,234` / `-1,234`. For deltas, where the direction
  /// is the point.
  static String formatSatsSigned(int sats) {
    final formatted = _groupDigits(sats.abs());
    return sats < 0 ? '-$formatted' : '+$formatted';
  }

  /// Short form for axis labels and tight tiles: `1.2M`, `45.6k`, `880`.
  static String abbreviateSats(int sats) {
    final abs = sats.abs();
    final sign = sats < 0 ? '-' : '';
    if (abs >= 100000000) {
      return '$sign${(abs / 100000000).toStringAsFixed(2)} BTC';
    }
    if (abs >= 1000000) return '$sign${(abs / 1000000).toStringAsFixed(1)}M';
    if (abs >= 1000) return '$sign${(abs / 1000).toStringAsFixed(1)}k';
    return '$sign$abs';
  }

  static String _groupDigits(int value) =>
      value.toString().replaceAllMapped(_thousands, (m) => '${m[1]},');
}
