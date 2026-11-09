/// What a hostile Bitcoin server can send is bounded (audit B-8).
///
/// Lines and HTTP bodies had no size cap, so a server — over plain TCP, anyone
/// on the path — could run the app out of memory; an 8-byte varint past 2^63
/// read as a negative length and threw a RangeError; and an output value with
/// its top bit set read as negative.
library;

import 'dart:async';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/electrum_service.dart';
import 'package:sats_stack/core/services/xpub_service.dart';
import 'package:sats_stack/shared/utils/bitcoin_script.dart';

const _zpub =
    'zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1ADqtf'
    'SdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('transaction parsing', () {
    // version 1, one input spending nothing in particular.
    final head =
        '01000000'
        '01'
        '${'00' * 32}'
        '00000000';

    test('a length past 2^63 is malformed, not a RangeError', () {
      // The scriptSig length as an 8-byte varint of all ones: -1 as an int.
      expect(
        () => RawTransaction.parse('${head}ff${'ff' * 8}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('an output paying more than exists is refused', () {
      const tail =
          '00' // empty scriptSig
          'ffffffff' // sequence
          '01'; // one output
      for (final value in ['ffffffffffffffff', '0140075af0750700']) {
        // The first is negative as an int; the second is one sat over 21M BTC.
        expect(
          () => RawTransaction.parse(
            '$head$tail${value}00'
            '00000000',
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'Output value out of range',
            ),
          ),
          reason: value,
        );
      }
      // 21 million exactly is allowed.
      final ok = RawTransaction.parse(
        '$head${tail}0040075af0750700'
        '00'
        '00000000',
      );
      expect(ok.outputs.single.value, 2100000000000000);
    });
  });

  group('Electrum lines', () {
    Future<List<String>> lines(List<String> chunks, int max) =>
        Stream.fromIterable(chunks).transform(boundedLines(max)).toList();

    test('ordinary replies pass through', () async {
      expect(await lines(['{"id":1}\n{"i', 'd":2}\n'], 10), [
        '{"id":1}\n{"i',
        'd":2}\n',
      ]);
    });

    test('a reply that never ends is cut off', () async {
      await expectLater(
        lines(['{"result":"', 'aaaaaaaa', 'aaaaaaaa'], 16),
        throwsA(isA<FormatException>()),
      );
    });

    test('the limit is per line, not per connection', () async {
      // 24 characters in all, none of the lines more than 10.
      expect(
        await lines(['12345678\n', '12345678\n', '1234\n'], 10),
        hasLength(3),
      );
    });
  });

  test('an Esplora body past the cap fails the sync', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    // Megabytes sent on each request: the sync makes several at once.
    final sent = <int>[];
    final xpub = XpubService(
      db,
      client: MockClient.streaming((req, _) async {
        // Endless: 1 MB at a time until the reader stops asking.
        final request = sent.length;
        sent.add(0);
        final body = Stream<List<int>>.periodic(Duration.zero, (_) {
          sent[request]++;
          return List.filled(1024 * 1024, 0x20);
        });
        return http.StreamedResponse(body, 200);
      }),
    );
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

    await expectLater(
      xpub.syncWallet(wallet: wallet, btcPriceService: BtcPriceService(db)),
      throwsA(
        isA<XpubSyncException>().having(
          (e) => e.message,
          'message',
          contains('over 16 MB'),
        ),
      ),
    );
    // Each stopped just past the cap.
    expect(sent, isNotEmpty);
    expect(
      sent,
      everyElement(
        lessThanOrEqualTo(XpubService.maxResponseBytes ~/ (1024 * 1024) + 2),
      ),
    );
  });
}
