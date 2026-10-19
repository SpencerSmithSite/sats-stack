/// Tests for converting stored amounts into the display currency.
///
/// Every aggregate in the app used to add `amountFiat` across currencies, so a
/// GBP user with a USD card saw dollars added to pounds under a `£` label.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/models/fx_rates.dart';

void main() {
  // BTC priced in three currencies: 1 USD = 0.8 GBP, 1 USD = 0.9 EUR.
  const prices = {'USD': 100000.0, 'GBP': 80000.0, 'EUR': 90000.0};
  const gbp = FxRates(display: 'GBP', btcPrices: prices);

  group('same currency', () {
    test('is returned exactly, untouched', () {
      expect(gbp.convert(-42.17, 'GBP'), -42.17);
    });

    test('needs no rate at all, so it works offline', () {
      // The common case for nearly every user must not depend on a price
      // fetch having landed.
      const offline = FxRates(display: 'GBP', btcPrices: {});
      expect(offline.convert(-42.17, 'GBP'), -42.17);
    });

    test('is case-insensitive', () {
      expect(gbp.convert(10, 'gbp'), 10);
    });
  });

  group('cross-currency', () {
    test('converts through BTC', () {
      // $100 → £80, at 1 USD = 0.8 GBP.
      expect(gbp.convert(-100, 'USD'), closeTo(-80, 1e-9));
    });

    test('keeps the sign', () {
      expect(gbp.convert(250, 'USD'), closeTo(200, 1e-9));
      expect(gbp.convert(-250, 'USD'), closeTo(-200, 1e-9));
    });

    test('works between two non-display currencies', () {
      const eur = FxRates(display: 'EUR', btcPrices: prices);
      expect(eur.convert(-80, 'GBP'), closeTo(-90, 1e-9));
    });

    test('a mixed month sums correctly once converted', () {
      // The bug, end to end: £100 of groceries plus a $50 card charge used
      // to total "£150". At 1 USD = 0.8 GBP it is £140.
      final total = [
        gbp.convert(-100, 'GBP')!,
        gbp.convert(-50, 'USD')!,
      ].fold<double>(0, (a, b) => a + b);
      expect(total, closeTo(-140, 1e-9));
    });
  });

  group('legacy BTC-denominated rows', () {
    test('BTC is priced directly', () {
      expect(gbp.convert(0.5, 'BTC'), closeTo(40000, 1e-9));
    });

    test('SATS is priced directly', () {
      expect(gbp.convert(100000000, 'SATS'), closeTo(80000, 1e-9));
    });
  });

  group('no rate available', () {
    test('returns null rather than a guess', () {
      // The caller excludes and counts it. Mixing it in unconverted is the
      // bug this class exists to fix.
      expect(gbp.convert(-10, 'JPY'), isNull);
    });

    test('a missing display-currency price is also null', () {
      const noTarget = FxRates(display: 'CAD', btcPrices: prices);
      expect(noTarget.convert(-10, 'USD'), isNull);
    });

    test('a zero or negative price is treated as missing', () {
      const broken = FxRates(display: 'GBP', btcPrices: {'GBP': 0, 'USD': 1});
      expect(broken.convert(-10, 'USD'), isNull);
    });
  });

  group('passthrough', () {
    test('returns every amount unchanged', () {
      const raw = FxRates.passthrough();
      expect(raw.convert(-10, 'USD'), -10);
      expect(raw.convert(-10, 'JPY'), -10);
    });
  });
}
