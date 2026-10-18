/// Tests for the two helpers that replaced copy-pasted formatting.
///
/// Both existed in several divergent copies — the sats regex in a dozen places
/// with inconsistent sign handling, the category colours in three maps that
/// disagreed — so the point of these is that there is now one answer per input.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/shared/theme/category_palette.dart';
import 'package:sats_stack/shared/utils/month_cursor.dart';
import 'package:sats_stack/shared/utils/sat_converter.dart';

void main() {
  group('formatSats', () {
    test('groups thousands', () {
      expect(SatConverter.formatSats(0), '0');
      expect(SatConverter.formatSats(999), '999');
      expect(SatConverter.formatSats(1000), '1,000');
      expect(SatConverter.formatSats(1234567), '1,234,567');
      expect(SatConverter.formatSats(100000000), '100,000,000');
    });

    test('keeps the sign', () {
      // Some of the old copies dropped it, so the same number appeared with
      // and without its minus depending on the screen.
      expect(SatConverter.formatSats(-1234567), '-1,234,567');
    });

    test('formatSatsSigned always shows direction', () {
      expect(SatConverter.formatSatsSigned(1234), '+1,234');
      expect(SatConverter.formatSatsSigned(-1234), '-1,234');
      expect(SatConverter.formatSatsSigned(0), '+0');
    });

    test('abbreviateSats shortens for tight labels', () {
      expect(SatConverter.abbreviateSats(880), '880');
      expect(SatConverter.abbreviateSats(45600), '45.6k');
      expect(SatConverter.abbreviateSats(1200000), '1.2M');
      expect(SatConverter.abbreviateSats(150000000), '1.50 BTC');
      expect(SatConverter.abbreviateSats(-45600), '-45.6k');
    });
  });

  group('fiat and sats round-trip', () {
    test('conversions round rather than truncate', () {
      // 1 sat either way is real money at scale; truncation would lose it.
      expect(SatConverter.fiatToSats(1, 100000000), 1);
      expect(SatConverter.fiatToSats(0.000000009, 1), 1);
      expect(SatConverter.fiatToSats(10, 0), 0, reason: 'no price, no guess');
    });
  });

  group('CategoryPalette', () {
    test("the user's own colour wins", () {
      expect(CategoryPalette.of('Food & Dining', userHex: '#123456'),
          const Color(0xFF123456));
    });

    test('a seeded category keeps its shipped colour', () {
      expect(CategoryPalette.of('Food & Dining'), const Color(0xFFE24B4A));
      expect(CategoryPalette.of('Bitcoin'), const Color(0xFFF7931A));
    });

    test('every screen gets the same colour for the same name', () {
      // The whole point: Shopping was purple, blue-grey or plain grey
      // depending on which file you were looking at.
      expect(CategoryPalette.of('Shopping'), CategoryPalette.of('Shopping'));
      expect(CategoryPalette.of('Subscriptions'),
          CategoryPalette.of('Subscriptions'));
    });

    test('a custom category gets a stable, distinct colour', () {
      final first = CategoryPalette.of('Boat Maintenance');
      expect(CategoryPalette.of('Boat Maintenance'), first);
      // Not the grey everything unknown used to fall back to.
      expect(first, isNot(const Color(0xFF888780)));
    });

    test('a bad stored colour does not take a chart down', () {
      expect(CategoryPalette.parseHex('not a colour'), isNull);
      expect(CategoryPalette.parseHex(''), isNull);
      expect(CategoryPalette.of('Housing', userHex: 'garbage'),
          CategoryPalette.of('Housing'));
    });

    test('hex is accepted with or without a hash, and with alpha', () {
      expect(CategoryPalette.parseHex('#F7931A'), const Color(0xFFF7931A));
      expect(CategoryPalette.parseHex('F7931A'), const Color(0xFFF7931A));
      expect(CategoryPalette.parseHex('80F7931A'), const Color(0x80F7931A));
    });
  });

  group('MonthCursor', () {
    test('normalises to the first of the month', () {
      expect(MonthCursor(DateTime(2026, 3, 17, 23, 59)).month,
          DateTime(2026, 3, 1));
    });

    test('steps backwards and forwards across a year boundary', () {
      expect(MonthCursor(DateTime(2026, 1)).previous.month, DateTime(2025, 12));
      expect(MonthCursor(DateTime(2026, 12)).next.month, DateTime(2027, 1));
    });

    test('isCurrent compares year and month only', () {
      final now = DateTime(2026, 3, 17, 14, 30);
      expect(MonthCursor(DateTime(2026, 3, 1)).isCurrent(now), isTrue);
      expect(MonthCursor(DateTime(2026, 2, 28)).isCurrent(now), isFalse);
      expect(MonthCursor(DateTime(2025, 3, 17)).isCurrent(now), isFalse);
    });

    test('range is the half-open month', () {
      final range = MonthCursor(DateTime(2026, 2, 10)).range;
      expect(range.start, DateTime(2026, 2, 1));
      expect(range.end, DateTime(2026, 3, 1));
      // The boundary case the three screens used to get wrong on their own.
      expect(range.contains(DateTime(2026, 2, 28, 23, 59, 59, 400)), isTrue);
      expect(range.contains(DateTime(2026, 3, 1)), isFalse);
    });

    test('label is what the app bar shows', () {
      expect(MonthCursor(DateTime(2026, 3)).label, 'March 2026');
    });
  });
}
