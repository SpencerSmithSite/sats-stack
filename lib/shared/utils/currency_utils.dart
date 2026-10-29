import 'package:intl/intl.dart';

abstract final class CurrencyUtils {
  static const supported = ['USD', 'GBP', 'EUR', 'CAD', 'AUD'];

  static String symbolFor(String currency) {
    const map = {
      'USD': r'$',
      'GBP': '£',
      'EUR': '€',
      'CAD': r'CA$',
      'AUD': r'A$',
    };
    return map[currency.toUpperCase()] ?? '$currency ';
  }

  static String format(
    double amount,
    String currency, {
    int decimalDigits = 2,
  }) => NumberFormat.currency(
    symbol: symbolFor(currency),
    decimalDigits: decimalDigits,
  ).format(amount);

  /// The decimal places for a set of figures shown together: none when every
  /// one is a whole amount, two otherwise.
  ///
  /// Rounding each to a whole unit on its own is how a £12.50 spend against a
  /// £100 budget showed as "£13 spent, £88 remaining" — figures that do not
  /// add up, and neither of which the user entered.
  static int decimalsFor(Iterable<double> amounts) =>
      amounts.every((a) => (a * 100).round() % 100 == 0) ? 0 : 2;

  static String formatCompact(double amount, String currency) =>
      NumberFormat.compactCurrency(
        symbol: symbolFor(currency),
        decimalDigits: 0,
      ).format(amount);
}
