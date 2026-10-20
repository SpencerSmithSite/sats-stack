/// Tests for the price map's integrity.
///
/// Everything on the dashboard is a fiat figure converted through this one
/// number, so a wrong entry — or a right entry under the wrong currency code —
/// is wrong money on every screen at once.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

  group('historical prices', () {
    late AppDatabase db;
    late BtcPriceService service;
    var requests = 0;
    var quote = 60000.0;

    // "Now" is mid-afternoon on 20 October.
    final now = DateTime(2026, 10, 20, 15);

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      service = BtcPriceService(db, clock: () => now);
      requests = 0;
      quote = 60000.0;
    });
    tearDown(() => db.close());

    /// Runs [body] with every `http.get` answered by a fake mempool.
    Future<T> offline<T>(Future<T> Function() body) => http.runWithClient(
          body,
          () => MockClient((_) async {
            requests++;
            return http.Response(
                jsonEncode({
                  'prices': [
                    {'time': 0, 'USD': quote},
                  ],
                }),
                200);
          }),
        );

    Future<List<BtcPriceHistoryData>> stored() =>
        db.select(db.btcPriceHistory).get();

    test("today's moving quote is not cached permanently", () async {
      final price = await offline(() => service.getHistoricalPrice(now, 'USD'));

      expect(price, 60000);
      // Was written with DoNothing, so the mid-day quote stuck for good.
      expect(await stored(), isEmpty);
    });

    test('but one import still asks for today only once', () async {
      await offline(() async {
        await service.getHistoricalPrice(now, 'USD');
        await service.getHistoricalPrice(now, 'USD');
      });
      expect(requests, 1);
    });

    test('a settled day is cached permanently, as before', () async {
      final march = DateTime(2026, 3, 4);
      await offline(() => service.getHistoricalPrice(march, 'USD'));
      quote = 1; // a later answer must not be asked for
      final again = await offline(() => service.getHistoricalPrice(march, 'USD'));

      expect(again, 60000);
      expect(requests, 1);
      expect((await stored()).single.date, '2026-03-04');
    });

    test('a mid-day row from an earlier build is not served as final',
        () async {
      await db.into(db.btcPriceHistory).insert(BtcPriceHistoryCompanion.insert(
          date: '2026-10-20', currency: 'USD', price: 1));

      final price = await offline(() => service.getHistoricalPrice(now, 'USD'));

      expect(price, 60000);
      expect(await stored(), isEmpty);
    });
  });
}
