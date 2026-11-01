/// A wallet sync prices its transactions from the bulk price history, and
/// a one-day lookup names the day, not the moment (audit B-5).
///
/// Every transaction day was asked for on its own, one a second, each
/// request carrying that transaction's block time — so a user who chose
/// Electrum for privacy still told mempool.space when each transaction
/// happened, down to the block.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/xpub_service.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const zpub =
      'zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1ADqtf'
      'SdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs';
  const funded = 'bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu';

  late AppDatabase db;
  late Wallet wallet;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final id = await db
        .into(db.wallets)
        .insert(
          WalletsCompanion.insert(
            label: 'Cold',
            type: 'xpub',
            xpub: const Value(zpub),
            color: '#F7931A',
          ),
        );
    wallet =
        await (db.select(db.wallets)
          ..where((w) => w.id.equals(id))).getSingle();
  });
  tearDown(() => db.close());

  /// A chain with one payment on each of [days], at 14:37:11 UTC.
  XpubService chain(List<DateTime> days) => XpubService(
    db,
    client: MockClient((req) async {
      final txs =
          req.url.path.contains('/address/$funded/txs') &&
                  !req.url.path.contains('/chain/')
              ? [
                for (final (i, d) in days.indexed)
                  {
                    'txid': i.toRadixString(16).padLeft(64, 'a'),
                    'status': {
                      'confirmed': true,
                      'block_time':
                          DateTime.utc(
                            d.year,
                            d.month,
                            d.day,
                            14,
                            37,
                            11,
                          ).millisecondsSinceEpoch ~/
                          1000,
                    },
                    'vin': const [],
                    'vout': [
                      {'scriptpubkey_address': funded, 'value': 10000},
                    ],
                  },
              ]
              : const [];
      return http.Response(jsonEncode(txs), 200);
    }),
  );

  /// Mempool's price endpoints, recording what was asked.
  (BtcPriceService, List<Uri>) prices() {
    final asked = <Uri>[];
    final service = BtcPriceService(
      db,
      client: MockClient((req) async {
        asked.add(req.url);
        if (req.url.queryParameters.containsKey('currency')) {
          // The whole history, a point a day.
          final start = DateTime.utc(2025, 1, 1);
          return http.Response(
            jsonEncode({
              'prices': [
                for (var d = 0; d < 400; d++)
                  {
                    'time':
                        start.add(Duration(days: d)).millisecondsSinceEpoch ~/
                        1000,
                    'USD': 90000 + d,
                  },
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'prices': [
              {'time': 0, 'USD': 95000},
            ],
          }),
          200,
        );
      }),
    );
    return (service, asked);
  }

  test('a sync prices many days with one request that names none', () async {
    final days = [for (var d = 1; d <= 8; d++) DateTime(2025, 3, d * 3)];
    final (service, asked) = prices();

    final result = await chain(
      days,
    ).syncWallet(wallet: wallet, btcPriceService: service);

    expect(result.imported, 8);
    expect(result.unpriced, 0);
    expect(asked, hasLength(1));
    expect(asked.single.queryParameters.keys, ['currency']);
  });

  test('a single day asks for its midday, not the block time', () async {
    final (service, asked) = prices();
    await chain([
      DateTime(2025, 3, 4),
    ]).syncWallet(wallet: wallet, btcPriceService: service);

    final oneDay = asked.where(
      (u) => u.queryParameters.containsKey('timestamp'),
    );
    expect(oneDay, hasLength(1));
    final sent = DateTime.fromMillisecondsSinceEpoch(
      int.parse(oneDay.single.queryParameters['timestamp']!) * 1000,
    );
    expect((sent.hour, sent.minute, sent.second), (12, 0, 0));
  });
}
