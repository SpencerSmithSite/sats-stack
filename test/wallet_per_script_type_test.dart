/// A key and an address type together are one wallet (audit B-7).
///
/// Detection stopped at the first type with history and a key could be added
/// only once, so funds under a second type of the same key were never
/// tracked. Now the same key can be added again as another type, never twice
/// as the same one; Automatic picks the first type with history that no
/// wallet tracks, and does not look at the rest; and a type the user chose
/// stands.
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

// BIP84 test vector, account m/84'/0'/0', and the same key as a plain xpub.
const _zpub =
    'zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1ADqtf'
    'SdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs';

String get _xpub {
  final payload = Uint8List.fromList(bs58check.decode(_zpub));
  payload.setRange(0, 4, const [0x04, 0x88, 0xb2, 0x1e]);
  return bs58check.encode(payload);
}

class _Prices extends BtcPriceService {
  _Prices(super.db);
  @override
  Future<double?> getHistoricalPrice(DateTime date, String currency) async =>
      80000;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  /// Every address the chain was asked about.
  final asked = <String>{};

  late AppDatabase db;
  late WalletService wallets;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    wallets = WalletService(db);
    asked.clear();
  });
  tearDown(() => db.close());

  final blockTime = DateTime.utc(2025, 3, 4, 12).millisecondsSinceEpoch ~/ 1000;

  /// The key's first receive address as [format].
  String firstReceive(XpubFormat format) =>
      XpubService(db).deriveAddresses(_xpub, 0, 1, format: format).single;

  /// A chain where each of [paid] received one payment.
  XpubService chain(Set<String> paid) => XpubService(
    db,
    client: MockClient((req) async {
      final path = RegExp(r'/address/(\w+)/').firstMatch(req.url.path);
      if (path != null) asked.add(path.group(1)!);
      final address = paid.where(
        (a) =>
            req.url.path.contains('/address/$a/txs') &&
            !req.url.path.contains('/chain/'),
      );
      return http.Response(
        jsonEncode([
          for (final a in address)
            {
              'txid': a.hashCode.toRadixString(16).padLeft(64, '0'),
              'status': {'confirmed': true, 'block_time': blockTime},
              'vin': const [],
              'vout': [
                {'scriptpubkey_address': a, 'value': 50000},
              ],
            },
        ]),
        200,
      );
    }),
  );

  Future<Wallet> stored(int id) =>
      (db.select(db.wallets)..where((w) => w.id.equals(id))).getSingle();

  group('adding', () {
    test('the same key as the same type is refused', () async {
      await wallets.addXpubWallet(label: 'A', xpub: _zpub, color: '#F7931A');
      await expectLater(
        wallets.addXpubWallet(label: 'B', xpub: _zpub, color: '#F7931A'),
        throwsA(isA<DuplicateWalletException>()),
      );
    });

    test('the same key as another type is a wallet of its own', () async {
      await wallets.addXpubWallet(label: 'A', xpub: _zpub, color: '#F7931A');
      final nested = XpubService.withFormat(_zpub, XpubFormat.p2shP2wpkh);
      final b = await wallets.addXpubWallet(
        label: 'B',
        xpub: nested,
        color: '#F7931A',
        scriptTypeChosen: true,
      );
      expect(b.xpub, nested);
      expect(b.scriptTypeChosen, isTrue);
    });
  });

  group('Automatic, for a plain xpub', () {
    test('picks native SegWit and looks no further', () async {
      final service = chain({
        firstReceive(XpubFormat.p2wpkh),
        firstReceive(XpubFormat.p2shP2wpkh),
      });
      final wallet = await wallets.addXpubWallet(
        label: 'Ledger',
        xpub: _xpub,
        color: '#F7931A',
      );
      final result = await service.syncWallet(
        wallet: wallet,
        btcPriceService: _Prices(db),
      );
      expect((await stored(wallet.id)).xpub, _zpub);
      expect(result.imported, 1);
      expect(asked, isNot(contains(firstReceive(XpubFormat.p2shP2wpkh))));
      expect(asked, isNot(contains(firstReceive(XpubFormat.p2pkh))));
    });

    test('skips a type another wallet already tracks', () async {
      final service = chain({
        firstReceive(XpubFormat.p2wpkh),
        firstReceive(XpubFormat.p2shP2wpkh),
      });
      await wallets.addXpubWallet(
        label: 'Native',
        xpub: _zpub,
        color: '#F7931A',
      );
      final second = await wallets.addXpubWallet(
        label: 'Second',
        xpub: _xpub,
        color: '#F7931A',
      );
      final result = await service.syncWallet(
        wallet: second,
        btcPriceService: _Prices(db),
      );
      expect(
        (await stored(second.id)).xpub,
        XpubService.withFormat(_xpub, XpubFormat.p2shP2wpkh),
      );
      expect(result.imported, 1);
      // The tracked type is not fetched again.
      expect(asked, isNot(contains(firstReceive(XpubFormat.p2wpkh))));
    });

    test('refuses when no untracked type has history', () async {
      final service = chain({
        firstReceive(XpubFormat.p2wpkh),
        firstReceive(XpubFormat.p2shP2wpkh),
      });
      await wallets.addXpubWallet(
        label: 'Native',
        xpub: _zpub,
        color: '#F7931A',
      );
      await wallets.addXpubWallet(
        label: 'Nested',
        xpub: XpubService.withFormat(_xpub, XpubFormat.p2shP2wpkh),
        color: '#F7931A',
      );
      final third = await wallets.addXpubWallet(
        label: 'Third',
        xpub: _xpub,
        color: '#F7931A',
      );
      await expectLater(
        service.syncWallet(wallet: third, btcPriceService: _Prices(db)),
        throwsA(
          isA<XpubSyncException>().having(
            (e) => e.message,
            'message',
            allOf(contains('"Native"'), contains('"Nested"')),
          ),
        ),
      );
    });
  });

  test('a type the user chose stands, though another has history', () async {
    // Legacy, chosen, for a key whose history is all native SegWit.
    final service = chain({firstReceive(XpubFormat.p2wpkh)});
    final wallet = await wallets.addXpubWallet(
      label: 'Old wallet',
      xpub: _xpub,
      color: '#F7931A',
      scriptTypeChosen: true,
    );
    final result = await service.syncWallet(
      wallet: wallet,
      btcPriceService: _Prices(db),
    );
    expect((await stored(wallet.id)).xpub, _xpub);
    expect(result.imported, 0);
    expect(asked, isNot(contains(firstReceive(XpubFormat.p2wpkh))));
  });
}
