import 'dart:convert';
import 'dart:typed_data';

import 'package:bech32/bech32.dart';
import 'package:bs58check/bs58check.dart' as bs58check;
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';

import '../database/database.dart';
import '../services/btc_price_service.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/utils/hash_utils.dart';

// ── Public types ─────────────────────────────────────────────────────────────

enum XpubFormat {
  /// BIP44 — P2PKH (Legacy), starts with xpub
  p2pkh,

  /// BIP49 — P2SH-P2WPKH (Nested SegWit), starts with ypub
  p2shP2wpkh,

  /// BIP84 — P2WPKH (Native SegWit), starts with zpub
  p2wpkh,
}

class XpubSyncResult {
  XpubSyncResult({
    required this.imported,
    required this.skipped,
    required this.addressesScanned,
  });

  final int imported;
  final int skipped;
  final int addressesScanned;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Uint8List _intTo4BytesBE(int n) {
  return Uint8List(4)
    ..[0] = (n >> 24) & 0xFF
    ..[1] = (n >> 16) & 0xFF
    ..[2] = (n >> 8) & 0xFF
    ..[3] = n & 0xFF;
}

// ── Service ───────────────────────────────────────────────────────────────────

class XpubService {
  XpubService(this._db);

  final AppDatabase _db;

  String _esploraBaseUrl = AppConstants.mempoolBaseUrl;

  String get esploraBaseUrl => _esploraBaseUrl;

  Future<void> loadSettings() async {
    final rows = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(AppConstants.settingElectrumUrl)))
        .get();
    if (rows.isNotEmpty) {
      final stored = rows.first.value;
      _esploraBaseUrl =
          stored.isNotEmpty ? stored : AppConstants.mempoolBaseUrl;
    }
  }

  Future<void> saveSettings({required String url}) async {
    final trimmed = url.trim();
    // Store empty string when user clears the field — means "use default".
    _esploraBaseUrl = trimmed.isNotEmpty ? trimmed : '';
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppConstants.settingElectrumUrl,
            value: _esploraBaseUrl,
          ),
        );
  }

  // ECCurve_secp256k1 extends ECDomainParametersImpl — it IS the domain params.
  static final _curve = ECCurve_secp256k1();
  static const _gapLimit = 20;

  // ── Format detection ────────────────────────────────────────────────────────

  XpubFormat detectFormat(String extKey) {
    if (extKey.startsWith('ypub') || extKey.startsWith('upub')) {
      return XpubFormat.p2shP2wpkh;
    }
    if (extKey.startsWith('zpub') || extKey.startsWith('vpub')) {
      return XpubFormat.p2wpkh;
    }
    return XpubFormat.p2pkh;
  }

  // ── Key parsing ─────────────────────────────────────────────────────────────

  /// Decodes an extended public key and returns (pubkey 33B, chaincode 32B).
  /// Throws if the key is invalid.
  ({Uint8List pubkey, Uint8List chaincode}) _parseExtKey(String extKey) {
    final payload = bs58check.decode(extKey);
    if (payload.length != 78) throw ArgumentError('Invalid extended key length');
    // version(4) depth(1) fingerprint(4) childIndex(4) chaincode(32) pubkey(33)
    final chaincode = payload.sublist(13, 45);
    final pubkey = payload.sublist(45, 78);
    return (pubkey: pubkey, chaincode: chaincode);
  }

  // ── BIP32 child key derivation ───────────────────────────────────────────────

  /// Non-hardened child derivation: CKDpub((Kpar, cpar), i) for i < 0x80000000.
  ({Uint8List pubkey, Uint8List chaincode}) _deriveChild(
    Uint8List parentPubkey,
    Uint8List parentChaincode,
    int index,
  ) {
    assert(index < 0x80000000, 'Hardened derivation not supported for public keys');
    final data = Uint8List(37)
      ..setAll(0, parentPubkey)
      ..setAll(33, _intTo4BytesBE(index));

    final hmac = Hmac(sha512, parentChaincode);
    final I = Uint8List.fromList(hmac.convert(data).bytes);
    final IL = I.sublist(0, 32);
    final IR = I.sublist(32, 64);

    final ilInt = BigInt.parse(
        IL.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        radix: 16);

    // IL must be less than the curve order
    if (ilInt >= _curve.n) throw StateError('Derived key is invalid (IL >= n)');

    final parentPoint = _curve.curve.decodePoint(parentPubkey)!;
    final childPoint = (_curve.G * ilInt)! + parentPoint;
    if (childPoint == null || childPoint.isInfinity) {
      throw StateError('Derived key is invalid (point at infinity)');
    }

    return (
      pubkey: Uint8List.fromList(childPoint.getEncoded(true)),
      chaincode: IR,
    );
  }

  // ── Hashing ──────────────────────────────────────────────────────────────────

  Uint8List _sha256(Uint8List data) =>
      Uint8List.fromList(sha256.convert(data).bytes);

  Uint8List _ripemd160(Uint8List data) {
    final digest = RIPEMD160Digest();
    digest.update(data, 0, data.length);
    final out = Uint8List(digest.digestSize);
    digest.doFinal(out, 0);
    return out;
  }

  Uint8List _hash160(Uint8List data) => _ripemd160(_sha256(data));

  // ── Address generation ───────────────────────────────────────────────────────

  String _pubkeyToAddress(Uint8List pubkey, XpubFormat format) {
    final h160 = _hash160(pubkey);
    switch (format) {
      case XpubFormat.p2pkh:
        // P2PKH: Base58Check(0x00 || hash160)
        return bs58check.encode(Uint8List.fromList([0x00, ...h160]));

      case XpubFormat.p2shP2wpkh:
        // P2SH-P2WPKH: Base58Check(0x05 || hash160(OP_0 OP_20 <hash160(pubkey)>))
        final redeemScript = Uint8List.fromList([0x00, 0x14, ...h160]);
        return bs58check.encode(Uint8List.fromList([0x05, ..._hash160(redeemScript)]));

      case XpubFormat.p2wpkh:
        // P2WPKH: bech32("bc", 0, hash160)
        final converted = _convertBits(h160, 8, 5, pad: true);
        return bech32.encode(Bech32('bc', [0, ...converted]));
    }
  }

  // bech32 convertbits
  List<int> _convertBits(Uint8List data, int from, int to, {required bool pad}) {
    int acc = 0, bits = 0;
    final out = <int>[];
    final maxv = (1 << to) - 1;
    for (final value in data) {
      acc = ((acc << from) | value) & 0xFFFFFF;
      bits += from;
      while (bits >= to) {
        bits -= to;
        out.add((acc >> bits) & maxv);
      }
    }
    if (pad && bits > 0) {
      out.add((acc << (to - bits)) & maxv);
    }
    return out;
  }

  // ── Derive addresses for external chain ──────────────────────────────────────

  /// Derives [count] addresses from the external chain (m/0/startIndex …).
  List<String> deriveAddresses(
    String extKey,
    int startIndex,
    int count, {
    XpubFormat? format,
  }) {
    final fmt = format ?? detectFormat(extKey);
    final root = _parseExtKey(extKey);

    // Derive external chain key (m/0)
    final chain = _deriveChild(root.pubkey, root.chaincode, 0);

    return [
      for (int i = startIndex; i < startIndex + count; i++)
        _pubkeyToAddress(
          _deriveChild(chain.pubkey, chain.chaincode, i).pubkey,
          fmt,
        ),
    ];
  }

  // ── Mempool.space API ────────────────────────────────────────────────────────

  Future<List<dynamic>> _fetchAddressTxs(String address) async {
    final url = '$_esploraBaseUrl/address/$address/txs';
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  // ── Sync ─────────────────────────────────────────────────────────────────────

  Future<XpubSyncResult> syncWallet({
    required Wallet wallet,
    required BtcPriceService btcPriceService,
    void Function(String status)? onProgress,
  }) async {
    if (wallet.xpub == null) {
      return XpubSyncResult(imported: 0, skipped: 0, addressesScanned: 0);
    }

    final extKey = wallet.xpub!;
    final format = detectFormat(extKey);
    final root = _parseExtKey(extKey);
    final chain = _deriveChild(root.pubkey, root.chaincode, 0);
    final currency = btcPriceService.currency;

    // Collect existing dedup hashes to avoid re-inserting.
    final existing = await _db.select(_db.transactions).get();
    final existingHashes = {for (final t in existing) t.dedupHash};

    // ── Pass 1: scan addresses, collect raw transaction data ─────────────────
    final rawTxns = <_RawTx>[];
    int gapCount = 0;
    int index = 0;

    while (gapCount < _gapLimit) {
      final addrPubkey =
          _deriveChild(chain.pubkey, chain.chaincode, index).pubkey;
      final address = _pubkeyToAddress(addrPubkey, format);

      onProgress?.call('Scanning address ${index + 1} ($address)…');

      final txs = await _fetchAddressTxs(address);

      if (txs.isEmpty) {
        gapCount++;
      } else {
        gapCount = 0;

        for (final tx in txs) {
          final status = tx['status'] as Map<String, dynamic>?;
          if (status == null || status['confirmed'] != true) continue;

          final blockTime = status['block_time'] as int?;
          if (blockTime == null) continue;
          final txDate =
              DateTime.fromMillisecondsSinceEpoch(blockTime * 1000);

          final txid = tx['txid'] as String? ?? '';

          int netSats = 0;
          final vouts = (tx['vout'] as List<dynamic>?) ?? [];
          for (final vout in vouts) {
            if ((vout['scriptpubkey_address'] as String?) == address) {
              netSats += (vout['value'] as int? ?? 0);
            }
          }
          final vins = (tx['vin'] as List<dynamic>?) ?? [];
          for (final vin in vins) {
            final prevout = vin['prevout'] as Map<String, dynamic>?;
            if ((prevout?['scriptpubkey_address'] as String?) == address) {
              netSats -= (prevout?['value'] as int? ?? 0);
            }
          }

          if (netSats == 0) continue;

          final description =
              'BTC ${txid.substring(0, txid.length >= 8 ? 8 : txid.length)}';
          final hash = HashUtils.transactionDedupHash(
            date: txDate,
            amount: netSats.toDouble(),
            description: description,
            salt: address,
          );

          if (!existingHashes.contains(hash)) {
            rawTxns.add(_RawTx(
              date: txDate,
              netSats: netSats,
              description: description,
              dedupHash: hash,
            ));
          }
        }
      }

      index++;
      await Future.delayed(const Duration(milliseconds: 120));
    }

    // ── Pass 2: fetch historical prices for unique dates ──────────────────────
    final uniqueDates = {
      for (final t in rawTxns)
        '${t.date.year}-${t.date.month}-${t.date.day}': t.date,
    }.values.toList();

    for (int i = 0; i < uniqueDates.length; i++) {
      onProgress?.call(
          'Fetching historical price ${i + 1}/${uniqueDates.length}…');
      await btcPriceService.getHistoricalPrice(uniqueDates[i], currency);
    }

    // ── Pass 3: insert transactions with historically-accurate fiat values ────
    int imported = 0;
    int skipped = 0;

    for (final raw in rawTxns) {
      if (existingHashes.contains(raw.dedupHash)) {
        skipped++;
        continue;
      }

      final historicalPrice =
          await btcPriceService.getHistoricalPrice(raw.date, currency);
      final amountFiat = (historicalPrice != null && historicalPrice > 0)
          ? raw.netSats / 100000000 * historicalPrice
          : 0.0;

      try {
        await _db.into(_db.transactions).insert(
          TransactionsCompanion.insert(
            walletId: wallet.id,
            date: raw.date,
            description: raw.description,
            amountSats: raw.netSats,
            amountFiat: amountFiat,
            fiatCurrency: currency,
            category: Value(raw.netSats > 0 ? 'Bitcoin' : 'Other'),
            source: 'xpub',
            isBitcoin: Value(true),
            dedupHash: raw.dedupHash,
          ),
        );
        existingHashes.add(raw.dedupHash);
        imported++;
      } catch (_) {
        skipped++;
      }
    }

    return XpubSyncResult(
      imported: imported,
      skipped: skipped,
      addressesScanned: index,
    );
  }
}

/// Raw transaction data collected during address scanning (before DB insert).
class _RawTx {
  const _RawTx({
    required this.date,
    required this.netSats,
    required this.description,
    required this.dedupHash,
  });

  final DateTime date;
  final int netSats;
  final String description;
  final String dedupHash;
}
