/// A sync deletes rows the chain no longer backs only when it can be trusted
/// to have seen the whole history (audit B-1).
///
/// It used to delete every stored row the scan did not return. An address
/// with more history than the page cap returned only its newest part, and a
/// self-hosted server still indexing answers every address with an empty
/// list — either way, rows were deleted with the user's categories and notes,
/// and the only sign was a count.
library;

import 'dart:convert';

import 'package:drift/drift.dart'
    show StringExpressionOperators, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/xpub_service.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // BIP84 test vector, account m/84'/0'/0'.
  const zpub =
      'zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1ADqtf'
      'SdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs';
  const funded = 'bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu';
  final blockTime = DateTime.utc(2025, 3, 4, 12).millisecondsSinceEpoch ~/ 1000;

  late AppDatabase db;
  late BtcPriceService prices;
  late Wallet wallet;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    prices = BtcPriceService(db);
    await db
        .into(db.btcPriceHistory)
        .insert(
          BtcPriceHistoryCompanion.insert(
            date: '2025-03-04',
            currency: prices.currency,
            price: 80000,
          ),
        );
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

  Map<String, dynamic> tx(String txid) => {
    'txid': txid,
    'status': {'confirmed': true, 'block_time': blockTime},
    'vin': const [],
    'vout': [
      {'scriptpubkey_address': funded, 'value': 1000},
    ],
  };

  Future<void> storeOld(int n) async {
    for (var i = 0; i < n; i++) {
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              walletId: wallet.id,
              date: DateTime(2020, 1, 1 + i),
              description: 'BTC old$i',
              amountSats: 5000 + i,
              amountFiat: 0,
              fiatCurrency: 'USD',
              category: const Value('Savings'), // the user's own
              source: 'xpub',
              dedupHash: 'old$i',
            ),
          );
    }
  }

  Future<int> oldRowsLeft() async =>
      (await (db.select(db.transactions)
            ..where((t) => t.description.like('BTC old%'))).get())
          .length;

  test(
    'an address past the page cap keeps the rows it did not reach',
    () async {
      await storeOld(2);
      var page = 0;
      // A server with endless history on the first address: every page full.
      final sync = XpubService(
        db,
        client: MockClient((req) async {
          if (!req.url.path.contains(funded)) return http.Response('[]', 200);
          final p = page++;
          return http.Response(
            jsonEncode([
              for (var i = 0; i < 25; i++)
                tx(
                  '${p.toRadixString(16).padLeft(4, '0')}'
                  '${i.toRadixString(16).padLeft(60, '0')}',
                ),
            ]),
            200,
          );
        }),
      );

      final result = await sync.syncWallet(
        wallet: wallet,
        btcPriceService: prices,
      );

      expect(result.historyCapped, isTrue);
      expect(result.removed, 0);
      expect(result.kept, 2);
      expect(await oldRowsLeft(), 2);
      expect(result.keptNote, contains('more history than Sats Stack reads'));
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test('a server that answers with nothing keeps the wallet', () async {
    await storeOld(3);
    final sync = XpubService(
      db,
      client: MockClient((_) async => http.Response('[]', 200)),
    );

    final result = await sync.syncWallet(
      wallet: wallet,
      btcPriceService: prices,
    );

    expect(result.removed, 0);
    expect(result.kept, 3);
    expect(await oldRowsLeft(), 3);
    expect(result.keptNote, contains('server still catching up'));
    // The user's category survived with the row.
    final row = await (db.select(db.transactions)..limit(1)).getSingle();
    expect(row.category, 'Savings');
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('a few rows the chain no longer backs are still removed', () async {
    await storeOld(1);
    // The server knows five other transactions; one stored row is stale.
    final sync = XpubService(
      db,
      client: MockClient((req) async {
        final body =
            req.url.path.contains(funded) && !req.url.path.contains('/chain/')
                ? [for (var i = 0; i < 5; i++) tx('${'a' * 63}$i')]
                : const [];
        return http.Response(jsonEncode(body), 200);
      }),
    );

    final result = await sync.syncWallet(
      wallet: wallet,
      btcPriceService: prices,
    );

    expect(result.removed, 1);
    expect(result.kept, 0);
    expect(result.keptNote, isNull);
    expect(await oldRowsLeft(), 0);
  }, timeout: const Timeout(Duration(minutes: 1)));
}
