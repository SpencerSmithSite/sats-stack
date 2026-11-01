/// Which addresses a key is scanned for, and rows that could not be priced.
///
/// An `xpub` exported for a SegWit account was scanned as legacy and looked
/// empty. A testnet key was accepted, scanned against a mainnet server and
/// priced as real BTC. A row whose day had no price was stored at 0 and never
/// priced again — and a self-hosted Esplora server, which has no price
/// endpoint, made that every row, without a word.
library;

import 'dart:convert';

import 'package:bs58check/bs58check.dart' as bs58check;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/wallet_service.dart';
import 'package:sats_stack/core/services/xpub_service.dart';

// BIP84 test vector, account m/84'/0'/0'.
const _zpub =
    'zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1ADqtf'
    'SdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs';
const _firstReceive = 'bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu';

/// [_zpub]'s key under other version bytes.
String _reversioned(int version) {
  final payload = Uint8List.fromList(bs58check.decode(_zpub));
  payload.setRange(0, 4, [
    version >> 24 & 0xff,
    version >> 16 & 0xff,
    version >> 8 & 0xff,
    version & 0xff,
  ]);
  return bs58check.encode(payload);
}

/// Prices from a fixed table, never the network.
class _Prices extends BtcPriceService {
  _Prices(super.db, this.price);
  double? price;
  @override
  Future<double?> getHistoricalPrice(DateTime date, String currency) async =>
      price;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  final blockTime = DateTime.utc(2025, 3, 4, 12).millisecondsSinceEpoch ~/ 1000;

  /// A chain where the BIP84 vector's first receive address was paid once.
  XpubService chain() => XpubService(
    db,
    client: MockClient((req) async {
      final paid =
          req.url.path.contains('/address/$_firstReceive/txs') &&
          !req.url.path.contains('/chain/');
      return http.Response(
        jsonEncode(
          paid
              ? [
                {
                  'txid': 'f00d' * 16,
                  'status': {'confirmed': true, 'block_time': blockTime},
                  'vin': const [],
                  'vout': [
                    {'scriptpubkey_address': _firstReceive, 'value': 50000},
                  ],
                },
              ]
              : const [],
        ),
        200,
      );
    }),
  );

  group('an xpub is checked for the addresses it really uses', () {
    final xpub = _reversioned(0x0488b21e);

    test('re-encoding keeps the key and changes only the script type', () {
      final service = XpubService(db);
      expect(xpub, startsWith('xpub'));
      expect(service.isAmbiguous(xpub), isTrue);
      expect(service.isAmbiguous(_zpub), isFalse);
      expect(XpubService.withFormat(xpub, XpubFormat.p2wpkh), _zpub);
      expect(service.deriveAddresses(xpub, 0, 1, format: XpubFormat.p2wpkh), [
        _firstReceive,
      ]);
    });

    test('a SegWit account exported as an xpub is found', () async {
      expect(await chain().detectUsedFormat(xpub), XpubFormat.p2wpkh);
    });

    test('an unused key reports nothing rather than guessing', () async {
      final empty = XpubService(
        db,
        client: MockClient((_) async => http.Response('[]', 200)),
      );
      expect(await empty.detectUsedFormat(xpub), isNull);
    });

    // Audit B-7: the type was looked for only when the wallet was added.
    Future<Wallet> walletFor(String key, {String label = 'Ledger'}) async {
      final id = await db
          .into(db.wallets)
          .insert(
            WalletsCompanion.insert(
              label: label,
              type: 'xpub',
              xpub: Value(key),
              color: '#F7931A',
            ),
          );
      return (db.select(db.wallets)..where((w) => w.id.equals(id))).getSingle();
    }

    Future<String?> storedKey(int id) =>
        (db.select(db.wallets)
          ..where((w) => w.id.equals(id))).getSingle().then((w) => w.xpub);

    test(
      'an xpub added before its first payment is found on a rescan',
      () async {
        final wallet = await walletFor(xpub);
        final before = XpubService(
          db,
          client: MockClient((_) async => http.Response('[]', 200)),
        );
        final first = await before.syncWallet(
          wallet: wallet,
          btcPriceService: _Prices(db, 80000),
        );
        expect(first.imported, 0);
        expect(await storedKey(wallet.id), xpub);

        // The first payment arrives, to a native SegWit address.
        final again = await chain().syncWallet(
          wallet: wallet,
          btcPriceService: _Prices(db, 80000),
        );

        expect(again.imported, 1);
        expect(await storedKey(wallet.id), _zpub);
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test('the window that showed the type is not fetched again', () async {
      var firstReceiveFetches = 0;
      final counting = XpubService(
        db,
        client: MockClient((req) async {
          if (req.url.path.contains('/address/$_firstReceive/')) {
            firstReceiveFetches++;
          }
          return http.Response(
            jsonEncode(
              req.url.path.contains('/address/$_firstReceive/txs') &&
                      !req.url.path.contains('/chain/')
                  ? [
                    {
                      'txid': 'f00d' * 16,
                      'status': {'confirmed': true, 'block_time': blockTime},
                      'vin': const [],
                      'vout': [
                        {'scriptpubkey_address': _firstReceive, 'value': 50000},
                      ],
                    },
                  ]
                  : const [],
            ),
            200,
          );
        }),
      );
      final result = await counting.syncWallet(
        wallet: await walletFor(xpub),
        btcPriceService: _Prices(db, 80000),
      );

      expect(result.imported, 1);
      expect(firstReceiveFetches, 1);
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('adding the xpub again finds the wallet it was stored as', () async {
      final wallet = await walletFor(_zpub);
      final found = await WalletService(db).findByXpub(xpub);
      expect(found?.id, wallet.id);
      // A zpub and a ypub of one key are still different wallets.
      expect(
        await WalletService(
          db,
        ).findByXpub(XpubService.withFormat(xpub, XpubFormat.p2shP2wpkh)),
        isNull,
      );
    });

    test('a key another wallet already tracks is not stored twice', () async {
      await walletFor(_zpub, label: 'First');
      final second = await walletFor(xpub, label: 'Second');

      await expectLater(
        chain().syncWallet(wallet: second, btcPriceService: _Prices(db, 80000)),
        throwsA(isA<XpubSyncException>()),
      );
      expect(await storedKey(second.id), xpub);
    }, timeout: const Timeout(Duration(minutes: 1)));
  });

  test('a testnet key is refused before any request is made', () async {
    final vpub = _reversioned(0x045f1cf6);
    var requests = 0;
    final service = XpubService(
      db,
      client: MockClient((_) async {
        requests++;
        return http.Response('[]', 200);
      }),
    );
    expect(service.detectNetwork(vpub), XpubNetwork.testnet);
    final id = await db
        .into(db.wallets)
        .insert(
          WalletsCompanion.insert(
            label: 'Test',
            type: 'xpub',
            xpub: Value(vpub),
            color: '#F7931A',
          ),
        );
    final wallet =
        await (db.select(db.wallets)
          ..where((w) => w.id.equals(id))).getSingle();

    await expectLater(
      service.syncWallet(wallet: wallet, btcPriceService: _Prices(db, 1)),
      throwsA(isA<XpubSyncException>()),
    );
    expect(requests, 0);
  });

  test('a row with no price is priced on a later sync', () async {
    final id = await db
        .into(db.wallets)
        .insert(
          WalletsCompanion.insert(
            label: 'Cold',
            type: 'xpub',
            xpub: const Value(_zpub),
            color: '#F7931A',
          ),
        );
    final wallet =
        await (db.select(db.wallets)
          ..where((w) => w.id.equals(id))).getSingle();
    final prices = _Prices(db, null);

    final first = await chain().syncWallet(
      wallet: wallet,
      btcPriceService: prices,
    );
    expect(first.imported, 1);
    expect(first.unpriced, 1);
    expect(first.unpricedNote, contains('1 transaction has no fiat value'));
    expect((await db.select(db.transactions).getSingle()).amountFiat, 0);

    prices.price = 80000;
    final second = await chain().syncWallet(
      wallet: wallet,
      btcPriceService: prices,
    );
    expect(second.unpriced, 0);
    expect(second.unpricedNote, isNull);
    final row = await db.select(db.transactions).getSingle();
    expect(row.amountFiat, closeTo(40, 1e-9)); // 50,000 sats at $80k
  });
}
