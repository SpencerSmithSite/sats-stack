/// An extended key exported at the wrong level is flagged (audit B-11).
///
/// A master or chain-level key was derived as `/chain/index` without
/// complaint, which gives addresses nothing was sent to: the wallet showed as
/// empty, with no reason given.
library;

import 'dart:typed_data';

import 'package:bs58check/bs58check.dart' as bs58check;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/xpub_service.dart';

/// The BIP84 test vector's account key: depth 3.
const _account =
    'zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1ADqtf'
    'SdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs';

/// [_account] with its depth byte set to [depth].
String _atDepth(int depth) {
  final payload = Uint8List.fromList(bs58check.decode(_account));
  payload[4] = depth;
  return bs58check.encode(payload);
}

void main() {
  late AppDatabase db;
  late XpubService xpub;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    xpub = XpubService(db);
  });
  tearDown(() => db.close());

  test('an account key passes', () {
    expect(xpub.depthWarning(_account), isNull);
  });

  test('a chain key says it is one', () {
    expect(xpub.depthWarning(_atDepth(4)), contains('chain key'));
  });

  test('a master or Electrum-style key is flagged, not refused', () {
    for (final depth in [0, 1, 2]) {
      final key = _atDepth(depth);
      expect(xpub.depthWarning(key), contains('depth $depth'));
      // Still readable: Electrum's own wallets export these.
      expect(xpub.detectFormat(key), xpub.detectFormat(_account));
    }
  });
}
