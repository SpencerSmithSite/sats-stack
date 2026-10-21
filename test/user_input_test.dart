/// Amounts as the user types them, and the figures shown back to them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/utils/amount_input.dart';
import 'package:sats_stack/shared/utils/currency_utils.dart';

void main() {
  group('parseUserAmount', () {
    test('a decimal comma is a decimal point', () {
      // On a German or French keypad the decimal key is a comma: "12,50" was
      // saved as 1250.
      expect(parseUserAmount('12,50'), 12.5);
      expect(parseUserAmount('4,5'), 4.5);
    });

    test('a comma grouping thousands is not', () {
      expect(parseUserAmount('1,250'), 1250);
      expect(parseUserAmount('1,250.50'), 1250.5);
      expect(parseUserAmount('1.250,50'), 1250.5);
      expect(parseUserAmount('1.250.000'), 1250000);
    });

    test('plain numbers and rubbish', () {
      expect(parseUserAmount('12.50'), 12.5);
      expect(parseUserAmount(' 7 '), 7);
      expect(parseUserAmount(''), isNull);
      expect(parseUserAmount(','), isNull);
    });

    test('the field keeps the comma', () {
      final formatted = amountInputFormatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '4,50'),
      );
      expect(formatted.text, '4,50');
    });
  });

  group('CurrencyUtils.decimalsFor', () {
    test('whole figures stay whole', () {
      expect(CurrencyUtils.decimalsFor([100, 25, 75]), 0);
    });

    test('one fractional figure shows them all to the penny', () {
      // £12.50 of £100 used to read "£13 spent, £88 remaining".
      expect(CurrencyUtils.decimalsFor([100, 12.5, 87.5]), 2);
    });
  });

  test('a saved System theme comes back as System', () {
    expect(app.themeModeFromSetting('system'), ThemeMode.system);
    expect(app.themeModeFromSetting('light'), ThemeMode.light);
    expect(app.themeModeFromSetting('dark'), ThemeMode.dark);
    expect(app.themeModeFromSetting(null), ThemeMode.dark);
  });
}
