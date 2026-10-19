/// Converts stored fiat amounts into the currency the user is looking at.
///
/// Every aggregate in the app — the dashboard's monthly income and spending,
/// budget progress, the analytics pie and trend, the year-to-date figures and
/// the exported summary — used to sum `amountFiat` without looking at
/// `fiatCurrency`. The import flow deliberately supports a per-source currency,
/// so a GBP user with a USD card got dollars added to pounds under a `£` label,
/// while the transactions list showed each row correctly and the two screens
/// visibly disagreed.
///
/// BTC is the bridge currency, because it is the one rate table the app
/// already holds for every supported currency: `amount × price[to] /
/// price[from]`.
///
/// **This is today's cross rate, applied to every row.** A March USD charge is
/// converted at October's USD/GBP rate, not March's. That is a deliberate
/// trade: major-currency cross rates move a few percent a year, against the
/// 20–30% error of adding the two numbers together, and it is synchronous —
/// the historical alternative would mean a network fetch inside every
/// aggregate. Rows already in the display currency, which is nearly all of
/// them for nearly every user, are returned untouched and exact.
class FxRates {
  const FxRates({required this.display, required this.btcPrices})
      : _passthrough = false;

  /// Returns every amount unchanged.
  ///
  /// The behaviour a service has when no converter is wired in — used by tests
  /// that construct a service directly and by nothing in production, where
  /// `main.dart` supplies real rates.
  const FxRates.passthrough()
      : display = '',
        btcPrices = const {},
        _passthrough = true;

  /// The currency amounts are converted into.
  final String display;

  /// BTC price in each currency, keyed by upper-case ISO code.
  final Map<String, double> btcPrices;

  final bool _passthrough;

  /// [amount], stored in [from], expressed in [display] — or null when there
  /// is no rate for one side.
  ///
  /// Null rather than a guess, deliberately. The caller excludes the row and
  /// counts it, so the UI can say a total is incomplete; the alternative is the
  /// very bug this class exists to fix.
  double? convert(double amount, String from) {
    if (_passthrough) return amount;

    final source = from.toUpperCase();
    final target = display.toUpperCase();

    // The common case, and exact: no rate involved at all, so it works offline
    // and before the first price fetch has landed.
    if (source == target) return amount;

    final targetPrice = btcPrices[target];
    if (targetPrice == null || targetPrice <= 0) return null;

    // Legacy rows from before BTC imports were converted at write time stored
    // the BTC figure itself in amountFiat.
    if (source == 'BTC') return amount * targetPrice;
    if (source == 'SATS') return amount / 100000000 * targetPrice;

    final sourcePrice = btcPrices[source];
    if (sourcePrice == null || sourcePrice <= 0) return null;
    return amount * targetPrice / sourcePrice;
  }
}
