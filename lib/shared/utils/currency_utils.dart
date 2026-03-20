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

  static String format(double amount, String currency, {int decimalDigits = 2}) =>
      NumberFormat.currency(
        symbol: symbolFor(currency),
        decimalDigits: decimalDigits,
      ).format(amount);

  static String formatCompact(double amount, String currency) =>
      NumberFormat.compactCurrency(
        symbol: symbolFor(currency),
        decimalDigits: 0,
      ).format(amount);
}
