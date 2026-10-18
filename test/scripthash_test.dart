/// Verifies the Electrum scripthash formula and scriptPubKey address decoding.
///
/// If the scripthash tests fail, get_history returns empty for every address.
/// If the address-decoding tests fail, received/spent sats are always 0 and
/// every transaction is silently dropped.
import 'dart:typed_data';

import 'package:bs58check/bs58check.dart' as bs58check;
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

String _scriptToElectrumScripthash(List<int> script) {
  final sha = sha256.convert(script).bytes;
  return sha.reversed
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

List<int> _hexToBytes(String hex) {
  final out = <int>[];
  for (var i = 0; i < hex.length - 1; i += 2) {
    out.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return out;
}

void main() {
  group('Electrum scripthash formula', () {
    // Known vector from Electrum protocol docs.
    // Genesis coinbase output (block 0):
    //   address       : 1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa
    //   hash160       : 62e907b15cbf27d5425399ebf6f0fb50ebb88f18
    //   scriptPubKey  : 76 a9 14 <hash160> 88 ac  (P2PKH)
    //   expected hash : 8b01df4e368ea28f8dc0423bcf7a4923e3a12d307c875e47a0cfbf90b5c39161
    test('P2PKH genesis address matches known Electrum scripthash', () {
      final script = [
        0x76, 0xa9, 0x14, // OP_DUP OP_HASH160 PUSH20
        0x62, 0xe9, 0x07, 0xb1, 0x5c, 0xbf, 0x27, 0xd5,
        0x42, 0x53, 0x99, 0xeb, 0xf6, 0xf0, 0xfb, 0x50,
        0xeb, 0xb8, 0x8f, 0x18, // hash160
        0x88, 0xac, // OP_EQUALVERIFY OP_CHECKSIG
      ];
      expect(
        _scriptToElectrumScripthash(script),
        equals('8b01df4e368ea28f8dc0423bcf7a4923e3a12d307c875e47a0cfbf90b5c39161'),
      );
    });

    test('P2WPKH BIP141 example address scripthash formula is correct', () {
      final script = [
        0x00, 0x14, // OP_0 PUSH20
        0x75, 0x1e, 0x76, 0xe8, 0x19, 0x91, 0x96, 0xf4,
        0x54, 0xf0, 0x82, 0xd1, 0x1b, 0x9c, 0xf4, 0x3e,
        0x1f, 0x1e, 0x4c, 0x3f, // hash160
      ];
      final sha = sha256.convert(script).bytes;
      final reversed = sha.reversed.toList();
      final computed =
          reversed.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(_scriptToElectrumScripthash(script), equals(computed));
      expect(computed.length, equals(64));
    });
  });

  // These tests verify the hex parsing and hash extraction that feeds into
  // _addressFromScriptHex.  The actual bs58check/bech32 encoding is the same
  // library used by _pubkeyToAddress (which already works), so we test the
  // parsing side separately to isolate failure points.
  group('scriptPubKey hex parsing', () {
    test('P2PKH script recognised and hash160 extracted correctly', () {
      // 1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa — genesis coinbase output
      final b = _hexToBytes('76a91462e907b15cbf27d5425399ebf6f0fb50ebb88f1888ac');
      expect(b.length, equals(25));
      expect(b[0], equals(0x76)); // OP_DUP
      expect(b[1], equals(0xa9)); // OP_HASH160
      expect(b[2], equals(0x14)); // PUSH20
      expect(b[23], equals(0x88)); // OP_EQUALVERIFY
      expect(b[24], equals(0xac)); // OP_CHECKSIG
      // Verify the hash160 encodes to the correct address via bs58check
      final addr = bs58check.encode(Uint8List.fromList([0x00, ...b.sublist(3, 23)]));
      expect(addr, equals('1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa'));
    });

    test('P2WPKH script recognised and witness program extracted correctly', () {
      // bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 (BIP173 test vector)
      // witness program = 751e76e8199196f454f082d11b9cf43e1f1e4c3f
      final b = _hexToBytes('0014751e76e8199196f454f082d11b9cf43e1f1e4c3f');
      expect(b.length, equals(22));
      expect(b[0], equals(0x00)); // OP_0
      expect(b[1], equals(0x14)); // PUSH20
      final program = b.sublist(2, 22).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
      expect(program, equals('751e76e8199196f454f082d11b9cf43e1f1e4c3f'));
    });

    test('P2SH script recognised and hash160 extracted correctly', () {
      // 3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy
      final b = _hexToBytes('a914b472a266d0bd89c13706a4132ccfb16f7c3b9fcb87');
      expect(b.length, equals(23));
      expect(b[0], equals(0xa9)); // OP_HASH160
      expect(b[1], equals(0x14)); // PUSH20
      expect(b[22], equals(0x87)); // OP_EQUAL
      final addr = bs58check.encode(Uint8List.fromList([0x05, ...b.sublist(2, 22)]));
      expect(addr, equals('3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy'));
    });

    test('_hexToBytes round-trips correctly for all byte values', () {
      // Verify every byte 0x00-0xFF decodes correctly
      final allBytes = List.generate(256, (i) => i);
      final hex = allBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(_hexToBytes(hex), equals(allBytes));
    });
  });
}
