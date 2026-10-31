/// Wallet history from the user's own Electrum server (TODO item 11).
///
/// The scan used to read only Esplora's HTTP API. An Electrum server answers
/// in scripthashes and raw transactions instead, so it is translated into
/// Esplora's shape and the same netting, dedup and pricing code runs on
/// either — the end-to-end case below checks they agree.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingTerm, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/bitcoin_data_source.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/xpub_service.dart';
import 'package:sats_stack/shared/utils/bitcoin_script.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _le(int value, int width) => [
  for (var k = 0; k < width; k++) (value >> (8 * k)) & 0xff,
];

List<int> _varint(int n) => n < 0xfd ? [n] : [0xfd, ..._le(n, 2)];

List<int> _unhex(String hex) => [
  for (var k = 0; k < hex.length; k += 2)
    int.parse(hex.substring(k, k + 2), radix: 16),
];

/// A serialised transaction. [segwit] adds the marker, flag and one empty
/// witness per input, which the parser must step over.
String _rawTx({
  required List<(String txid, int vout)> inputs,
  required List<(int value, List<int> script)> outputs,
  bool segwit = false,
}) => _hex([
  ..._le(2, 4),
  if (segwit) ...[0x00, 0x01],
  ..._varint(inputs.length),
  for (final (txid, vout) in inputs) ...[
    ..._unhex(txid).reversed,
    ..._le(vout, 4),
    0x00, // empty scriptSig
    ..._le(0xffffffff, 4),
  ],
  ..._varint(outputs.length),
  for (final (value, script) in outputs) ...[
    ..._le(value, 8),
    ..._varint(script.length),
    ...script,
  ],
  if (segwit)
    for (var k = 0; k < inputs.length; k++) 0x00,
  ..._le(0, 4),
]);

void main() {
  group('scripts and scripthashes', () {
    test('the genesis address has the published scripthash', () {
      expect(
        BitcoinScript.electrumScripthash('1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa'),
        '8b01df4e368ea28f8dc0423bcf7a4923e3a12d307c875e47a0cfbf90b5c39161',
      );
    });

    test('each kind of address round-trips through its script', () {
      for (final address in const [
        '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa', // P2PKH
        '3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy', // P2SH
        'bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu', // P2WPKH
        'bc1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qccfmv3',
      ]) {
        final script = BitcoinScript.scriptPubKeyFor(address);
        expect(BitcoinScript.addressFor(script), address, reason: address);
      }
    });

    test('a script with no address this can write gives null', () {
      // OP_RETURN, and a taproot output.
      expect(BitcoinScript.addressFor(const [0x6a, 0x01, 0x00]), isNull);
      expect(
        BitcoinScript.addressFor([0x51, 0x20, ...List.filled(32, 1)]),
        isNull,
      );
    });

    test('a testnet or garbled address is refused', () {
      expect(
        () => BitcoinScript.scriptPubKeyFor(
          'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
        ),
        throwsFormatException,
      );
      expect(
        () => BitcoinScript.scriptPubKeyFor('not an address'),
        throwsFormatException,
      );
    });
  });

  group('raw transactions', () {
    final script = BitcoinScript.scriptPubKeyFor(
      'bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu',
    );
    for (final segwit in [false, true]) {
      test(segwit ? 'SegWit serialisation' : 'legacy serialisation', () {
        final tx = RawTransaction.parse(
          _rawTx(
            inputs: [('ab' * 32, 3)],
            outputs: [
              (50000, script),
              (1, const [0x6a]),
            ],
            segwit: segwit,
          ),
        );
        expect(tx.inputs.single.txid, 'ab' * 32);
        expect(tx.inputs.single.vout, 3);
        expect(tx.outputs.map((o) => o.value), [50000, 1]);
        expect(tx.outputs.first.script, script);
      });
    }

    test('a coinbase input spends nothing', () {
      final tx = RawTransaction.parse(
        _rawTx(inputs: [('00' * 32, 0xffffffff)], outputs: [(1, script)]),
      );
      expect(tx.inputs, isEmpty);
    });

    test('a truncated transaction is refused', () {
      final hex = _rawTx(inputs: [('ab' * 32, 0)], outputs: [(1, script)]);
      expect(
        () => RawTransaction.parse(hex.substring(0, hex.length - 20)),
        throwsFormatException,
      );
    });
  });

  group('syncing from Electrum', () {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    // BIP84 test vector, account m/84'/0'/0'.
    const zpub =
        'zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1ADqtf'
        'SdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs';
    const receive0 = 'bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu';
    const receive1 = 'bc1qnjg0jd8228aq7egyzacy8cys3knf9xvrerkf9g';
    const change0 = 'bc1q8c6fshw2dlwun7ekn9qwf37cu2rn755upcp6el';
    const stranger = '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa';

    final t1 = DateTime.utc(2025, 3, 4, 12);
    final t2 = DateTime.utc(2025, 5, 6, 12);
    int secs(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

    // P pays a stranger; A spends it to the wallet; B spends A, paying a
    // stranger and returning change to the wallet's change chain — an
    // address the receive scan has not reached when it reads B.
    final p = 'aa' * 32, a = 'bb' * 32, b = 'cc' * 32, pending = 'dd' * 32;
    List<int> s(String addr) => BitcoinScript.scriptPubKeyFor(addr);
    final raw = {
      p: _rawTx(inputs: [('00' * 32, 0)], outputs: [(60000, s(stranger))]),
      a: _rawTx(
        inputs: [(p, 0)],
        outputs: [(50000, s(receive0)), (9000, s(stranger))],
        segwit: true,
      ),
      b: _rawTx(
        inputs: [(a, 0)],
        outputs: [(20000, s(stranger)), (29000, s(change0))],
        segwit: true,
      ),
    };
    final heights = {100: t1, 200: t2};
    final histories = {
      receive0: [
        {'tx_hash': a, 'height': 100},
        {'tx_hash': b, 'height': 200},
      ],
      // Only an unconfirmed payment: used, but nothing to book yet.
      receive1: [
        {'tx_hash': pending, 'height': 0},
      ],
      change0: [
        {'tx_hash': b, 'height': 200},
      ],
    };
    final byScripthash = {
      for (final e in histories.entries)
        BitcoinScript.electrumScripthash(e.key): e.value,
    };

    String header(DateTime t) =>
        _hex([...List.filled(68, 0), ..._le(secs(t), 4), ...List.filled(8, 0)]);

    late AppDatabase db;
    late ServerSocket server;
    final methods = <String>[];

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      methods.clear();
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((conn) {
        conn
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              final req = jsonDecode(line) as Map<String, dynamic>;
              final method = req['method'] as String;
              final params = req['params'] as List<dynamic>;
              methods.add(method);
              final Object? result = switch (method) {
                'server.version' => ['Fake', '1.4'],
                'blockchain.scripthash.get_history' =>
                  byScripthash[params.first] ?? const [],
                'blockchain.transaction.get' => raw[params.first],
                'blockchain.block.header' => header(heights[params.first]!),
                _ => null,
              };
              conn.writeln(jsonEncode({'id': req['id'], 'result': result}));
            });
      });
    });

    tearDown(() async {
      await server.close();
      await db.close();
    });

    Future<BtcPriceService> prices() async {
      final service = BtcPriceService(db);
      for (final t in [t1, t2]) {
        final local = t.toLocal();
        await db
            .into(db.btcPriceHistory)
            .insert(
              BtcPriceHistoryCompanion.insert(
                date:
                    '${local.year}-${local.month.toString().padLeft(2, '0')}-'
                    '${local.day.toString().padLeft(2, '0')}',
                currency: service.currency,
                price: 100000,
              ),
            );
      }
      return service;
    }

    Future<Wallet> wallet() async {
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
      return (db.select(db.wallets)..where((w) => w.id.equals(id))).getSingle();
    }

    Future<List<(DateTime, int)>> rows() async => [
      for (final t
          in await (db.select(db.transactions)
                ..where((t) => t.source.equals('xpub'))
                ..orderBy([(t) => OrderingTerm.asc(t.date)]))
              .get())
        (t.date.toUtc(), t.amountSats),
    ];

    test('nets receipts, spends and change, and closes the session', () async {
      final xpub = XpubService(db);
      await xpub.electrum.saveSettings(
        host: '127.0.0.1',
        port: server.port,
        ssl: false,
      );
      await xpub.saveDataSource(BitcoinDataSource.electrum);

      final result = await xpub.syncWallet(
        wallet: await wallet(),
        btcPriceService: await prices(),
      );

      expect(result.imported, 2);
      expect(result.unpriced, 0);
      expect(await rows(), [(t1, 50000), (t2, -21000)]);
      // The stranger's parent P was read to price A's input, once.
      expect(methods.where((m) => m == 'blockchain.transaction.get').length, 3);
    });

    test('gives the same rows Esplora does for the same chain', () async {
      Map<String, dynamic> esplora(String txid, DateTime t) {
        final tx = RawTransaction.parse(raw[txid]!);
        return {
          'txid': txid,
          'status': {'confirmed': true, 'block_time': secs(t)},
          'vin': [
            for (final i in tx.inputs)
              {
                'prevout': {
                  'scriptpubkey_address': BitcoinScript.addressFor(
                    RawTransaction.parse(raw[i.txid]!).outputs[i.vout].script,
                  ),
                  'value':
                      RawTransaction.parse(raw[i.txid]!).outputs[i.vout].value,
                },
              },
          ],
          'vout': [
            for (final o in tx.outputs)
              {
                'scriptpubkey_address': BitcoinScript.addressFor(o.script),
                'value': o.value,
              },
          ],
        };
      }

      final esploraXpub = XpubService(
        db,
        client: MockClient((req) async {
          final path = req.url.path;
          if (path.contains('/chain/')) return http.Response('[]', 200);
          final List<Object> body = switch (path) {
            _ when path.contains(receive0) => [esplora(a, t1), esplora(b, t2)],
            _ when path.contains(change0) => [esplora(b, t2)],
            _ when path.contains(receive1) => [
              {
                'txid': pending,
                'status': {'confirmed': false},
              },
            ],
            _ => [],
          };
          return http.Response(jsonEncode(body), 200);
        }),
      );
      await esploraXpub.syncWallet(
        wallet: await wallet(),
        btcPriceService: await prices(),
      );
      expect(await rows(), [(t1, 50000), (t2, -21000)]);
    });

    test(
      'an unreachable server fails the sync rather than emptying it',
      () async {
        final xpub = XpubService(db);
        final port = server.port;
        await server.close();
        await xpub.electrum.saveSettings(
          host: '127.0.0.1',
          port: port,
          ssl: false,
        );
        await xpub.saveDataSource(BitcoinDataSource.electrum);
        await expectLater(
          xpub.syncWallet(
            wallet: await wallet(),
            btcPriceService: await prices(),
          ),
          throwsA(
            isA<XpubSyncException>().having(
              (e) => e.message,
              'message',
              contains('Could not reach your Electrum server'),
            ),
          ),
        );
        // Rebound for tearDown.
        server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      },
    );

    test('choosing Electrum with no server set up says so', () async {
      final xpub = XpubService(db);
      await xpub.saveDataSource(BitcoinDataSource.electrum);
      await expectLater(
        xpub.syncWallet(
          wallet: await wallet(),
          btcPriceService: await prices(),
        ),
        throwsA(
          isA<XpubSyncException>().having(
            (e) => e.message,
            'message',
            contains('no server is set up'),
          ),
        ),
      );
    });

    test('the choice survives a restart', () async {
      await XpubService(db).saveDataSource(BitcoinDataSource.electrum);
      final reloaded = XpubService(db);
      await reloaded.loadSettings();
      expect(reloaded.dataSource, BitcoinDataSource.electrum);
    });
  });

  // Never zero bytes: an empty list would let a broken builder pass.
  test('the test builder writes something', () {
    expect(
      Uint8List.fromList(_unhex(_rawTx(inputs: [], outputs: []))),
      isNotEmpty,
    );
  });
}
