/// Tests for the price map's integrity.
///
/// Everything on the dashboard is a fiat figure converted through this one
/// number, so a wrong entry — or a right entry under the wrong currency code —
/// is wrong money on every screen at once.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';

void main() {
  group('currencyEntries', () {
    test("mempool's time field is not stored as a price", () {
      // The real shape of mempool.space/api/v1/prices.
      final parsed = BtcPriceService.currencyEntries({
        'time': 1760000000,
        'USD': 97000.0,
        'EUR': 89000.0,
        'GBP': 76000.0,
      });

      expect(parsed.containsKey('TIME'), isFalse);
      expect(parsed['USD'], 97000.0);
      expect(parsed, hasLength(3));
    });

    test('codes are upper-cased and non-numeric values dropped', () {
      final parsed = BtcPriceService.currencyEntries({
        'usd': 97000,
        'eur': 'not a number',
        'cad': 132000.5,
      });

      expect(parsed['USD'], 97000.0);
      expect(parsed.containsKey('EUR'), isFalse);
      expect(parsed['CAD'], 132000.5);
    });

    test('anything that is not a 3-letter code is dropped', () {
      final parsed = BtcPriceService.currencyEntries({
        'USD': 97000,
        'latest': 1,
        'BITCOIN': 1,
        'US': 1,
        'U5D': 1,
      });

      expect(parsed.keys, ['USD']);
    });
  });

  group('switchCurrency', () {
    late AppDatabase db;
    late BtcPriceService service;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      service = BtcPriceService(db);
    });

    tearDown(() => db.close());

    test('does not leave the previous currency price on display', () {
      // No prices have been fetched, so there is nothing for either currency.
      // The old code left priceNotifier untouched here, which meant the getter
      // reported the new currency while the notifier still held the old
      // currency's number — every fiat figure relabelled rather than
      // reconverted, wrong by the exchange rate, with no error shown.
      service.priceNotifier.value = 97000;
      service.switchCurrency('EUR');

      expect(service.currency, 'EUR');
      expect(service.priceNotifier.value, isNull,
          reason: 'a USD figure must not be shown as euros');
    });
  });
}
