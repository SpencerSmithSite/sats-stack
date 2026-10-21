import 'dart:convert';

import 'package:bech32/bech32.dart';
import 'package:bs58check/bs58check.dart' as bs58check;
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';

import '../../shared/constants/app_constants.dart';
import '../../shared/utils/hash_utils.dart';
import '../../shared/utils/url_utils.dart';
import '../database/database.dart';
import '../services/btc_price_service.dart';

// ── Public types ─────────────────────────────────────────────────────────────

enum XpubFormat {
  /// BIP44 — P2PKH (Legacy), starts with xpub
  p2pkh,

  /// BIP49 — P2SH-P2WPKH (Nested SegWit), starts with ypub
  p2shP2wpkh,

  /// BIP84 — P2WPKH (Native SegWit), starts with zpub
  p2wpkh,
}

/// Which chain an extended key belongs to.
///
/// Tracked separately from [XpubFormat] because it decides the address prefix
/// rather than the script type. Deriving a mainnet `bc1…` address from a
/// testnet key is a funds-loss hazard: the address looks valid, the scan comes
/// back empty, and anything paid to it is gone.
enum XpubNetwork { mainnet, testnet }

class XpubSyncResult {
  XpubSyncResult({
    required this.imported,
    required this.skipped,
    required this.addressesScanned,
    this.removed = 0,
  });

  final int imported;
  final int skipped;
  final int addressesScanned;

  /// Rows deleted because the chain no longer backs them — see [XpubService].
  final int removed;
}

/// A sync that could not finish.
///
/// Thrown rather than returning an empty result: "the server refused us" and
/// "this wallet has no history" must never look the same to the user. Both
/// call sites ([AddWalletSheet], [ManageWalletsSheet]) already catch and
/// display it.
class XpubSyncException implements Exception {
  const XpubSyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Uint8List _intTo4BytesBE(int n) {
  return Uint8List(4)
    ..[0] = (n >> 24) & 0xFF
    ..[1] = (n >> 16) & 0xFF
    ..[2] = (n >> 8) & 0xFF
    ..[3] = n & 0xFF;
}

/// The 4-byte version prefixes of every extended *public* key the app accepts.
///
/// Switching on these bytes rather than on the `xpub`/`zpub` text is what makes
/// testnet safe — the prefix string is only a consequence of them — and it
/// rejects anything else (an extended *private* key, a multisig `Zpub`, another
/// coin) instead of quietly treating it as mainnet legacy.
const _extKeyVersions = <int, ({XpubFormat format, XpubNetwork network})>{
  0x0488b21e: (format: XpubFormat.p2pkh, network: XpubNetwork.mainnet), // xpub
  0x049d7cb2: (
    format: XpubFormat.p2shP2wpkh,
    network: XpubNetwork.mainnet,
  ), // ypub
  0x04b24746: (format: XpubFormat.p2wpkh, network: XpubNetwork.mainnet), // zpub
  0x043587cf: (format: XpubFormat.p2pkh, network: XpubNetwork.testnet), // tpub
  0x044a5262: (
    format: XpubFormat.p2shP2wpkh,
    network: XpubNetwork.testnet,
  ), // upub
  0x045f1cf6: (format: XpubFormat.p2wpkh, network: XpubNetwork.testnet), // vpub
};

typedef _ExtKey =
    ({
      Uint8List pubkey,
      Uint8List chaincode,
      XpubFormat format,
      XpubNetwork network,
    });

// ── Isolate entry ─────────────────────────────────────────────────────────────

/// Derives a window of addresses. Runs in a background isolate via [compute].
///
/// Each address costs an EC scalar multiplication plus a point addition in
/// pure Dart, and a scan walks dozens of them. On the UI isolate that is
/// visible jank in the middle of a wallet import, which is exactly when the
/// progress line is supposed to be animating.
///
/// The message is a plain list because that is unambiguously sendable: the
/// extended key, the chain (0 = receive, 1 = change), the first index and how
/// many to derive. The derivation itself is static and holds no state, so the
/// isolate needs nothing from the service but the curve, which it rebuilds.
List<String> deriveAddressWindow(List<Object> message) {
  final extKey = message[0] as String;
  final chain = message[1] as int;
  final start = message[2] as int;
  final count = message[3] as int;

  // A fresh service: it holds no state beyond the curve, which is static and
  // so is rebuilt once per isolate.
  return XpubService.deriveWindowSync(extKey, chain, start, count);
}

// ── Service ───────────────────────────────────────────────────────────────────

class XpubService {
  /// [client] is for tests, which answer from memory instead of the network.
  XpubService(this._db, {http.Client? client})
    : _client = client ?? http.Client();

  final AppDatabase _db;

  /// One client for the whole app rather than one per request: a scan makes
  /// dozens of calls to the same host and `http.get` would open a fresh
  /// connection for each. Never closed — the service lives as long as the app.
  final http.Client _client;

  String _esploraBaseUrl = AppConstants.mempoolBaseUrl;

  String get esploraBaseUrl => _esploraBaseUrl;

  /// Pause between address requests. mempool.space rate-limits the public API,
  /// and a 429 now aborts the scan with an error rather than looking like an
  /// empty wallet, so the spacing matters.
  static const _requestSpacing = Duration(milliseconds: 120);
  static const _requestTimeout = Duration(seconds: 20);
  static const _maxAttempts = 3;

  /// Esplora returns 25 confirmed transactions per page. The cap is a
  /// stop-loss against a server that keeps returning full pages.
  static const _pageSize = 25;
  static const _maxPagesPerAddress = 40;

  // ── Settings ────────────────────────────────────────────────────────────────

  Future<void> loadSettings() async {
    final rows =
        await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(AppConstants.settingElectrumUrl))).get();
    if (rows.isNotEmpty) {
      _esploraBaseUrl =
          normalizeBaseUrl(rows.first.value) ?? AppConstants.mempoolBaseUrl;
    }
  }

  /// Saves the Esplora/Mempool base URL. Returns the URL now in effect, or
  /// null when the field was blank or unusable and the built-in default is
  /// being used instead — the caller can then tell the user rather than
  /// leaving them thinking a typo was accepted.
  ///
  /// The stored row keeps `''` for "use the default" so the default can move
  /// between releases, but the *live* value is never `''`: setting it empty
  /// used to leave every request pointed at a relative URL until the next
  /// launch, which surfaced as "0 transactions imported" for a perfectly good
  /// wallet.
  Future<String?> saveSettings({required String url}) async {
    final normalized = normalizeBaseUrl(url);
    _esploraBaseUrl = normalized ?? AppConstants.mempoolBaseUrl;
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppConstants.settingElectrumUrl,
            value: normalized ?? '',
          ),
        );
    return normalized;
  }

  /// Cleans up a user-typed server URL, or returns null if it cannot be used.
  /// A bare host is assumed to be https — see [normalizeServerUrl].
  static String? normalizeBaseUrl(String raw) => normalizeServerUrl(raw);

  // ECCurve_secp256k1 extends ECDomainParametersImpl — it IS the domain params.
  static final _curve = ECCurve_secp256k1();
  static const _gapLimit = 20;

  /// The chains BIP44/49/84 define: 0 = receive, 1 = change.
  ///
  /// Both must be scanned. Scanning only chain 0 makes every change output
  /// invisible, so a wallet that has ever spent shows the whole input as leaving
  /// and the change never coming back.
  static const _chains = [0, 1];

  // ── Format detection ────────────────────────────────────────────────────────

  XpubFormat detectFormat(String extKey) => _parseExtKey(extKey).format;

  XpubNetwork detectNetwork(String extKey) => _parseExtKey(extKey).network;

  // ── Key parsing ─────────────────────────────────────────────────────────────

  /// Decodes an extended public key. Throws [ArgumentError] if it is not one
  /// this app can use.
  static _ExtKey _parseExtKey(String extKey) {
    final payload = bs58check.decode(extKey.trim());
    if (payload.length != 78) {
      throw ArgumentError('Invalid extended key length');
    }
    // version(4) depth(1) fingerprint(4) childIndex(4) chaincode(32) pubkey(33)
    final version =
        (payload[0] << 24) |
        (payload[1] << 16) |
        (payload[2] << 8) |
        payload[3];
    final meta = _extKeyVersions[version];
    if (meta == null) {
      throw ArgumentError(
        'Unsupported extended key — expected xpub, ypub, zpub, tpub, upub or '
        'vpub',
      );
    }
    final chaincode = payload.sublist(13, 45);
    final pubkey = payload.sublist(45, 78);
    // A public key starts 0x02/0x03; 0x00 means an extended *private* key was
    // pasted, which must never be accepted or stored.
    if (pubkey[0] != 0x02 && pubkey[0] != 0x03) {
      throw ArgumentError('Not an extended public key');
    }
    return (
      pubkey: pubkey,
      chaincode: chaincode,
      format: meta.format,
      network: meta.network,
    );
  }

  // ── BIP32 child key derivation ───────────────────────────────────────────────

  /// Non-hardened child derivation: CKDpub((Kpar, cpar), i) for i < 0x80000000.
  static ({Uint8List pubkey, Uint8List chaincode}) _deriveChild(
    Uint8List parentPubkey,
    Uint8List parentChaincode,
    int index,
  ) {
    assert(
      index < 0x80000000,
      'Hardened derivation not supported for public keys',
    );
    final data =
        Uint8List(37)
          ..setAll(0, parentPubkey)
          ..setAll(33, _intTo4BytesBE(index));

    final hmac = Hmac(sha512, parentChaincode);
    // I, IL and IR are BIP32's own names for the HMAC output and its halves.
    // Keeping them makes this checkable line-by-line against the spec, which
    // is worth more here than the naming lint.
    // ignore: non_constant_identifier_names
    final I = Uint8List.fromList(hmac.convert(data).bytes);
    // ignore: non_constant_identifier_names
    final IL = I.sublist(0, 32);
    // ignore: non_constant_identifier_names
    final IR = I.sublist(32, 64);

    final ilInt = BigInt.parse(
      IL.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    );

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

  static Uint8List _sha256(Uint8List data) =>
      Uint8List.fromList(sha256.convert(data).bytes);

  static Uint8List _ripemd160(Uint8List data) {
    final digest = RIPEMD160Digest();
    digest.update(data, 0, data.length);
    final out = Uint8List(digest.digestSize);
    digest.doFinal(out, 0);
    return out;
  }

  static Uint8List _hash160(Uint8List data) => _ripemd160(_sha256(data));

  // ── Address generation ───────────────────────────────────────────────────────

  static String _pubkeyToAddress(
    Uint8List pubkey,
    XpubFormat format,
    XpubNetwork network,
  ) {
    final mainnet = network == XpubNetwork.mainnet;
    final h160 = _hash160(pubkey);
    switch (format) {
      case XpubFormat.p2pkh:
        // P2PKH: Base58Check(version || hash160)
        final version = mainnet ? 0x00 : 0x6F;
        return bs58check.encode(Uint8List.fromList([version, ...h160]));

      case XpubFormat.p2shP2wpkh:
        // P2SH-P2WPKH: Base58Check(version || hash160(OP_0 OP_20 <hash160>))
        final version = mainnet ? 0x05 : 0xC4;
        final redeemScript = Uint8List.fromList([0x00, 0x14, ...h160]);
        return bs58check.encode(
          Uint8List.fromList([version, ..._hash160(redeemScript)]),
        );

      case XpubFormat.p2wpkh:
        // P2WPKH: bech32(hrp, 0, hash160)
        final hrp = mainnet ? 'bc' : 'tb';
        final converted = _convertBits(h160, 8, 5, pad: true);
        return bech32.encode(Bech32(hrp, [0, ...converted]));
    }
  }

  // bech32 convertbits
  static List<int> _convertBits(
    Uint8List data,
    int from,
    int to, {
    required bool pad,
  }) {
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

  // ── Derive addresses ─────────────────────────────────────────────────────────

  /// Derives [count] addresses from [chain] (0 = receive, 1 = change),
  /// starting at [startIndex].
  ///
  /// Also the cheapest validity check there is — it throws for anything that is
  /// not a usable extended public key, which is what the Add Wallet form uses
  /// it for.
  List<String> deriveAddresses(
    String extKey,
    int startIndex,
    int count, {
    XpubFormat? format,
    int chain = 0,
  }) {
    final key = _parseExtKey(extKey);
    final fmt = format ?? key.format;
    final chainKey = _deriveChild(key.pubkey, key.chaincode, chain);

    return [
      for (int i = startIndex; i < startIndex + count; i++)
        _pubkeyToAddress(
          _deriveChild(chainKey.pubkey, chainKey.chaincode, i).pubkey,
          fmt,
          key.network,
        ),
    ];
  }

  /// Derives addresses without needing a database — what the isolate calls.
  static List<String> deriveWindowSync(
    String extKey,
    int chain,
    int start,
    int count,
  ) {
    final key = _parseExtKey(extKey);
    final chainKey = _deriveChild(key.pubkey, key.chaincode, chain);
    return [
      for (var i = start; i < start + count; i++)
        _pubkeyToAddress(
          _deriveChild(chainKey.pubkey, chainKey.chaincode, i).pubkey,
          key.format,
          key.network,
        ),
    ];
  }

  /// Derives a window off the UI isolate.
  ///
  /// Falls back to deriving in place if the isolate cannot be spawned — some
  /// test and desktop environments cannot — because a slightly janky import
  /// beats one that fails.
  Future<List<String>> _deriveWindow(
    String extKey,
    int chain,
    int start,
    int count,
  ) async {
    try {
      return await compute(deriveAddressWindow, <Object>[
        extKey,
        chain,
        start,
        count,
      ]);
    } catch (_) {
      return deriveWindowSync(extKey, chain, start, count);
    }
  }

  // ── Esplora API ──────────────────────────────────────────────────────────────

  /// GETs [url] and decodes the JSON body.
  ///
  /// Throws [XpubSyncException] on anything that is not a 200 with JSON, after
  /// retrying 429s and 5xxs with backoff. The old version returned `[]` for
  /// every failure, which the scan loop read as "this address is unused" — so a
  /// rate limit, an offline device or a wrong URL all reported a healthy scan of
  /// an empty wallet.
  Future<dynamic> _getJson(String url) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      http.Response response;
      try {
        response = await _client.get(Uri.parse(url)).timeout(_requestTimeout);
      } catch (e) {
        lastError = e;
        if (attempt == _maxAttempts) break;
        await Future.delayed(_backoff(attempt));
        continue;
      }

      if (response.statusCode == 200) {
        try {
          return jsonDecode(response.body);
        } on FormatException {
          throw XpubSyncException(
            '${Uri.parse(url).host} did not return JSON — is it an Esplora '
            'server?',
          );
        }
      }

      final retryable =
          response.statusCode == 429 || response.statusCode >= 500;
      if (retryable && attempt < _maxAttempts) {
        await Future.delayed(_retryAfter(response) ?? _backoff(attempt));
        continue;
      }

      throw XpubSyncException(
        response.statusCode == 429
            ? 'Rate limited by ${Uri.parse(url).host}. Wait a minute and try '
                'again, or point Settings → Bitcoin server at your own node.'
            : '${Uri.parse(url).host} returned HTTP ${response.statusCode}',
      );
    }
    throw XpubSyncException(
      'Could not reach ${Uri.parse(url).host}: $lastError',
    );
  }

  static Duration _backoff(int attempt) =>
      Duration(milliseconds: 500 * (1 << (attempt - 1)));

  static Duration? _retryAfter(http.Response response) {
    final header = response.headers['retry-after'];
    if (header == null) return null;
    final seconds = int.tryParse(header.trim());
    if (seconds == null || seconds < 0) return null;
    // Cap it: a server asking us to wait ten minutes should surface as an
    // error, not as a frozen progress line.
    return seconds <= 30 ? Duration(seconds: seconds) : null;
  }

  /// How many address requests may be in flight at once.
  ///
  /// Deliberately small. The point is to overlap latency, not to raise the
  /// request rate — mempool.space rate-limits the public API, and a 429 now
  /// (correctly) aborts the whole scan rather than looking like an empty
  /// wallet. Combined with [_requestSpacing] between launches this lands at a
  /// similar rate to the old serial walk, with a fraction of the wall-clock.
  static const _maxConcurrentRequests = 3;

  /// Fetches a window of addresses, at most [_maxConcurrentRequests] at a
  /// time, returning results in the order the addresses were given.
  Future<List<List<Map<String, dynamic>>>> _fetchWindow(
    List<String> addresses,
  ) async {
    final results = List<List<Map<String, dynamic>>>.filled(
      addresses.length,
      const [],
    );
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= addresses.length) return;
        results[i] = await _fetchAddressTxs(addresses[i]);
        await Future.delayed(_requestSpacing);
      }
    }

    // Any failure propagates: a scan that could not read an address must not
    // report that address as unused.
    await Future.wait([
      for (var w = 0; w < _maxConcurrentRequests; w++) worker(),
    ]);
    return results;
  }

  /// Every transaction Esplora knows for [address], following pagination.
  ///
  /// A single `/txs` call returns only the newest 25 confirmed transactions, so
  /// a wallet with a longer history on one address used to lose everything
  /// older with no warning.
  Future<List<Map<String, dynamic>>> _fetchAddressTxs(String address) async {
    final out = <Map<String, dynamic>>[];
    String? lastSeen;

    for (var page = 0; page < _maxPagesPerAddress; page++) {
      final url =
          lastSeen == null
              ? '$_esploraBaseUrl/address/$address/txs'
              : '$_esploraBaseUrl/address/$address/txs/chain/$lastSeen';
      final body = await _getJson(url);
      if (body is! List) {
        throw XpubSyncException(
          'Unexpected response for $address — expected a list of transactions',
        );
      }

      final txs = body.whereType<Map<String, dynamic>>().toList();
      out.addAll(txs);

      // Only confirmed transactions paginate; the first page also carries
      // mempool entries, which is why the page is measured by its confirmed
      // count rather than its length.
      final confirmed = txs.where(_isConfirmed).toList();
      if (confirmed.length < _pageSize) break;
      final next = confirmed.last['txid'];
      if (next is! String) break;
      lastSeen = next;
      await Future.delayed(_requestSpacing);
    }

    return out;
  }

  static bool _isConfirmed(Map<String, dynamic> tx) {
    final status = tx['status'];
    return status is Map<String, dynamic> && status['confirmed'] == true;
  }

  // ── Sync ─────────────────────────────────────────────────────────────────────

  /// Brings [wallet]'s transactions in line with the chain.
  ///
  /// The rows this writes are a projection of on-chain history, not user data:
  /// one row per transaction (not per address), keyed on the txid. Rows from an
  /// earlier sync of this wallet that the chain no longer backs are deleted, so
  /// a wallet imported before the one-row-per-address bug heals itself on the
  /// next rescan. A row the user has edited keeps those edits as long as its
  /// txid is still on chain, because matching rows are left untouched.
  ///
  /// Throws [XpubSyncException] if the server cannot be reached — never reports
  /// an empty wallet it did not actually verify.
  Future<XpubSyncResult> syncWallet({
    required Wallet wallet,
    required BtcPriceService btcPriceService,
    void Function(String status)? onProgress,
  }) async {
    final extKey = wallet.xpub;
    if (extKey == null) {
      return XpubSyncResult(imported: 0, skipped: 0, addressesScanned: 0);
    }

    // Validates the key before any network work happens — an unusable xpub
    // should fail immediately, not after twenty requests. The derivation
    // itself now happens inside the isolate, which parses it again there.
    _parseExtKey(extKey);

    final currency = btcPriceService.currency;

    // Only the hashes are needed, not every column of every row — and only
    // this wallet's. Checking every wallet's made a second wallet on the same
    // xpub sync to zero rows while reporting them all as skipped.
    final hashRows =
        await (_db.selectOnly(_db.transactions)
              ..addColumns([_db.transactions.dedupHash])
              ..where(_db.transactions.walletId.equals(wallet.id)))
            .get();
    final existingHashes =
        hashRows
            .map((r) => r.read(_db.transactions.dedupHash))
            .whereType<String>()
            .toSet();

    // ── Pass 1: scan both chains ────────────────────────────────────────────
    //
    // Transactions are collected whole and keyed by txid; the net effect is
    // worked out afterwards, once every owned address is known. Computing it
    // per address as they arrive would miss outputs paid to an address the scan
    // has not reached yet — change, typically.
    final owned = <String>{};
    final txById = <String, Map<String, dynamic>>{};
    var addressesScanned = 0;

    for (final chainIndex in _chains) {
      final chainName = chainIndex == 0 ? 'receive' : 'change';
      var gapCount = 0;
      var index = 0;

      // A window at a time rather than one address at a time. The derivation
      // happens in an isolate, and the requests within a window overlap, which
      // turns a serial walk into something closer to one round-trip per window
      // — the scan was previously 40+ strictly sequential requests with a
      // sleep between each.
      //
      // The window is the gap limit, so no address is fetched that a serial
      // walk would not also have fetched, except at most one window at the
      // very end.
      while (gapCount < _gapLimit) {
        final addresses = await _deriveWindow(
          extKey,
          chainIndex,
          index,
          _gapLimit,
        );
        owned.addAll(addresses);

        onProgress?.call(
          'Scanning $chainName addresses ${index + 1}–${index + _gapLimit}…',
        );

        final results = await _fetchWindow(addresses);

        // Applied in order, so the gap limit means exactly what it meant
        // before: N consecutive unused addresses ends the chain.
        for (var i = 0; i < results.length; i++) {
          addressesScanned++;
          final txs = results[i];
          if (txs.isEmpty) {
            gapCount++;
            if (gapCount >= _gapLimit) break;
          } else {
            gapCount = 0;
            for (final tx in txs) {
              final txid = tx['txid'];
              if (txid is String) txById[txid] = tx;
            }
          }
        }

        index += _gapLimit;
      }
    }

    // ── Pass 2: one row per transaction ─────────────────────────────────────
    final rows = <_RawTx>[];
    for (final tx in txById.values) {
      if (!_isConfirmed(tx)) continue;
      final blockTime = (tx['status'] as Map<String, dynamic>)['block_time'];
      if (blockTime is! int) continue;
      final txid = tx['txid'] as String;
      final date = DateTime.fromMillisecondsSinceEpoch(blockTime * 1000);

      var netSats = 0;
      for (final vout in (tx['vout'] as List<dynamic>? ?? const [])) {
        if (vout is! Map<String, dynamic>) continue;
        if (owned.contains(vout['scriptpubkey_address'])) {
          netSats += (vout['value'] as int? ?? 0);
        }
      }
      for (final vin in (tx['vin'] as List<dynamic>? ?? const [])) {
        if (vin is! Map<String, dynamic>) continue;
        final prevout = vin['prevout'];
        if (prevout is Map<String, dynamic> &&
            owned.contains(prevout['scriptpubkey_address'])) {
          netSats -= (prevout['value'] as int? ?? 0);
        }
      }

      // Nothing moved in or out of this wallet — the transaction only touched
      // it as a third party. (A self-send nets the fee, so it is kept.)
      if (netSats == 0) continue;

      final shortId = txid.substring(0, txid.length >= 8 ? 8 : txid.length);
      final description = 'BTC $shortId';
      // Salted with the txid: one on-chain transaction is one row, however many
      // of the wallet's addresses it touched. Then scoped to the wallet, so the
      // same transaction in a second wallet is its own row rather than a
      // collision on the unique index — see `AppDatabase.migrateToV8`.
      final hash = HashUtils.scopedToWallet(
        HashUtils.transactionDedupHash(
          date: date,
          amount: netSats.toDouble(),
          description: description,
          salt: 'xpub_$txid',
        ),
        wallet.id,
      );

      rows.add(
        _RawTx(
          date: date,
          netSats: netSats,
          description: description,
          dedupHash: hash,
        ),
      );
    }

    final newRows =
        rows.where((r) => !existingHashes.contains(r.dedupHash)).toList();

    // ── Pass 3: historical prices, once per date ────────────────────────────
    final datesToPrice = <String, DateTime>{
      for (final r in newRows) _dayKey(r.date): r.date,
    };
    final priceByDay = <String, double?>{};
    var fetched = 0;
    for (final entry in datesToPrice.entries) {
      fetched++;
      onProgress?.call(
        'Fetching historical price $fetched/${datesToPrice.length}…',
      );
      priceByDay[entry.key] = await btcPriceService.getHistoricalPrice(
        entry.value,
        currency,
      );
    }

    // ── Pass 4: write ───────────────────────────────────────────────────────
    //
    // One transaction, so the dashboard, budgets and notification listeners see
    // a single change rather than one per row.
    final wanted = {for (final r in rows) r.dedupHash};
    var imported = 0;
    final skipped = rows.length - newRows.length;
    var removed = 0;

    await _db.transaction(() async {
      // Two where clauses rather than `&`: that operator comes from a drift
      // extension this file does not import, and drift ANDs them anyway.
      final previous =
          await (_db.select(_db.transactions)
                ..where((t) => t.walletId.equals(wallet.id))
                ..where((t) => t.source.equals('xpub')))
              .get();
      for (final row in previous) {
        if (!wanted.contains(row.dedupHash)) {
          await (_db.delete(_db.transactions)
            ..where((t) => t.id.equals(row.id))).go();
          removed++;
        }
      }

      for (final raw in newRows) {
        final price = priceByDay[_dayKey(raw.date)];
        final amountFiat =
            (price != null && price > 0)
                ? raw.netSats / 100000000 * price
                : 0.0;

        await _db
            .into(_db.transactions)
            .insert(
              TransactionsCompanion.insert(
                walletId: wallet.id,
                date: raw.date,
                description: raw.description,
                amountSats: raw.netSats,
                amountFiat: amountFiat,
                fiatCurrency: currency,
                category: Value(raw.netSats > 0 ? 'Bitcoin' : 'Other'),
                source: 'xpub',
                isBitcoin: const Value(true),
                dedupHash: raw.dedupHash,
              ),
              mode: InsertMode.insertOrIgnore,
            );
        imported++;
      }
    });

    return XpubSyncResult(
      imported: imported,
      skipped: skipped,
      addressesScanned: addressesScanned,
      removed: removed,
    );
  }

  static String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
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
