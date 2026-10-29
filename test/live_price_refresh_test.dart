/// The live price is refreshed while the app is open.
///
/// It was fetched at launch, if stale, and never again — an app left open all
/// day showed the morning's price on every sats figure.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('a recent price is kept; an old one is fetched again', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var now = DateTime(2026, 10, 29, 9);
    var requests = 0;
    final prices = BtcPriceService(
      db,
      clock: () => now,
      client: MockClient((_) async {
        requests++;
        return http.Response('{"USD": 80000, "GBP": 64000}', 200);
      }),
    );
    prices.lastFetchedAt = now;

    now = now.add(const Duration(minutes: 5));
    await prices.refreshIfOlderThan(BtcPriceService.liveRefreshInterval);
    expect(requests, 0);

    now = now.add(const Duration(minutes: 10));
    await prices.refreshIfOlderThan(BtcPriceService.liveRefreshInterval);
    expect(requests, 1);
    expect(prices.priceNotifier.value, 80000);
  });
}
