/// Reading an amount the user typed.
library;

import 'package:flutter/services.dart';

/// Digits and the two separators, nothing else.
///
/// The fields used to allow `^\d*\.?\d*` only, which on a German or French
/// decimal keypad — where the key is a comma — silently dropped the comma:
/// "4,50" became "450".
final amountInputFormatter = FilteringTextInputFormatter.allow(
  RegExp(r'[\d.,]'),
);

/// [text] as a number, whichever character the user's keypad uses for the
/// decimal point; null if it is not one.
///
/// - Both `,` and `.`: the last of the two is the decimal point, so
///   `1,250.50` and `1.250,50` both read as 1250.5.
/// - A lone `,` followed by one or two digits is a decimal comma (`12,50`);
///   otherwise commas group thousands (`1,250`).
/// - Dots alone: one is a decimal point, several group thousands.
///
/// Stripping every comma — what this replaced — read a decimal comma as a
/// thousands separator, so editing an amount to "12,50" saved 1250.
double? parseUserAmount(String text) {
  var s = text.trim().replaceAll(' ', '').replaceAll(' ', '');
  if (s.isEmpty) return null;
  final lastComma = s.lastIndexOf(',');
  final lastDot = s.lastIndexOf('.');
  if (lastComma != -1 && lastDot != -1) {
    s =
        lastComma > lastDot
            ? s.replaceAll('.', '').replaceAll(',', '.')
            : s.replaceAll(',', '');
  } else if (lastComma != -1) {
    final decimalComma =
        ','.allMatches(s).length == 1 && RegExp(r',\d{1,2}$').hasMatch(s);
    s = decimalComma ? s.replaceAll(',', '.') : s.replaceAll(',', '');
  } else if ('.'.allMatches(s).length > 1) {
    s = s.replaceAll('.', '');
  }
  return double.tryParse(s);
}
