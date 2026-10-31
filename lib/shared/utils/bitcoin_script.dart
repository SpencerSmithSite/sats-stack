import 'dart:typed_data';

import 'package:bech32/bech32.dart';
import 'package:bs58check/bs58check.dart' as bs58check;
import 'package:crypto/crypto.dart';

/// Addresses ↔ output scripts, and the scripthash an Electrum server indexes
/// history by.
///
/// Covers what the app derives — P2PKH, P2SH and P2WPKH — and P2WSH. Taproot
/// is not: `package:bech32` has no bech32m, and the app never derives a
/// taproot address, so a taproot output is never the wallet's. Mainnet only,
/// like the xpub sync.
abstract final class BitcoinScript {
  static const _p2pkhVersion = 0x00;
  static const _p2shVersion = 0x05;

  /// The output script that pays [address]. Throws [FormatException] for an
  /// address this cannot read.
  static Uint8List scriptPubKeyFor(String address) {
    final a = address.trim();
    if (a.toLowerCase().startsWith('bc1')) {
      final Segwit s;
      try {
        s = segwit.decode(a);
      } catch (_) {
        throw FormatException('Not a SegWit v0 address', a);
      }
      if (s.version != 0) {
        throw FormatException('Only SegWit v0 addresses are supported', a);
      }
      return Uint8List.fromList([0x00, s.program.length, ...s.program]);
    }
    final List<int> payload;
    try {
      payload = bs58check.decode(a);
    } catch (_) {
      throw FormatException('Not a Bitcoin address', a);
    }
    if (payload.length != 21) throw FormatException('Not a Bitcoin address', a);
    final hash = payload.sublist(1);
    return switch (payload[0]) {
      // OP_DUP OP_HASH160 <20> OP_EQUALVERIFY OP_CHECKSIG
      _p2pkhVersion => Uint8List.fromList([
        0x76,
        0xa9,
        0x14,
        ...hash,
        0x88,
        0xac,
      ]),
      // OP_HASH160 <20> OP_EQUAL
      _p2shVersion => Uint8List.fromList([0xa9, 0x14, ...hash, 0x87]),
      _ => throw FormatException('Not a mainnet address', a),
    };
  }

  /// The address [script] pays, or null for a script with no address this
  /// can write (taproot, bare multisig, OP_RETURN…).
  static String? addressFor(List<int> script) {
    final s = script;
    if (s.length == 25 &&
        s[0] == 0x76 &&
        s[1] == 0xa9 &&
        s[2] == 0x14 &&
        s[23] == 0x88 &&
        s[24] == 0xac) {
      return _base58(_p2pkhVersion, s.sublist(3, 23));
    }
    if (s.length == 23 && s[0] == 0xa9 && s[1] == 0x14 && s[22] == 0x87) {
      return _base58(_p2shVersion, s.sublist(2, 22));
    }
    if ((s.length == 22 || s.length == 34) &&
        s[0] == 0x00 &&
        s[1] == s.length - 2) {
      return segwit.encode(Segwit('bc', 0, s.sublist(2)));
    }
    return null;
  }

  /// What Electrum indexes [address]'s history by: the SHA-256 of its output
  /// script, byte-reversed, in hex.
  static String electrumScripthash(String address) {
    final digest = sha256.convert(scriptPubKeyFor(address)).bytes;
    return digest.reversed
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static String _base58(int version, List<int> hash) =>
      bs58check.encode(Uint8List.fromList([version, ...hash]));
}

/// The parts of a raw transaction a wallet scan needs: what each input spends
/// and what each output pays. Witness data is skipped.
class RawTransaction {
  const RawTransaction({required this.inputs, required this.outputs});

  final List<({String txid, int vout})> inputs;
  final List<({int value, Uint8List script})> outputs;

  static const _coinbase =
      '0000000000000000000000000000000000000000000000000000000000000000';

  /// Parses the hex of a serialised transaction, legacy or SegWit. Throws
  /// [FormatException] on anything malformed. Coinbase inputs are left out:
  /// they spend nothing.
  factory RawTransaction.parse(String hex) {
    final b = _hexBytes(hex);
    var i = 0;
    Uint8List take(int n) {
      if (i + n > b.length) {
        throw const FormatException('Truncated transaction');
      }
      final out = Uint8List.sublistView(b, i, i + n);
      i += n;
      return out;
    }

    int varint() {
      final first = take(1)[0];
      final width = switch (first) {
        0xfd => 2,
        0xfe => 4,
        0xff => 8,
        _ => 0,
      };
      if (width == 0) return first;
      final bytes = take(width);
      var v = 0;
      for (var k = width - 1; k >= 0; k--) {
        v = (v << 8) | bytes[k];
      }
      return v;
    }

    int le(Uint8List bytes) {
      var v = 0;
      for (var k = bytes.length - 1; k >= 0; k--) {
        v = (v << 8) | bytes[k];
      }
      return v;
    }

    take(4); // version
    // SegWit marker and flag: an input count of zero cannot otherwise occur.
    if (b.length > i + 1 && b[i] == 0x00 && b[i + 1] == 0x01) take(2);

    final inputs = <({String txid, int vout})>[];
    for (var n = varint(); n > 0; n--) {
      final txid =
          take(
            32,
          ).reversed.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
      final vout = le(take(4));
      take(varint()); // scriptSig
      take(4); // sequence
      if (txid != _coinbase) inputs.add((txid: txid, vout: vout));
    }

    final outputs = <({int value, Uint8List script})>[];
    for (var n = varint(); n > 0; n--) {
      final value = le(take(8));
      outputs.add((value: value, script: Uint8List.fromList(take(varint()))));
    }
    return RawTransaction(inputs: inputs, outputs: outputs);
  }

  static Uint8List _hexBytes(String hex) {
    final h = hex.trim();
    if (h.length.isOdd) throw const FormatException('Odd-length hex');
    final out = Uint8List(h.length ~/ 2);
    for (var k = 0; k < out.length; k++) {
      final byte = int.tryParse(h.substring(k * 2, k * 2 + 2), radix: 16);
      if (byte == null) throw const FormatException('Not hex');
      out[k] = byte;
    }
    return out;
  }
}
