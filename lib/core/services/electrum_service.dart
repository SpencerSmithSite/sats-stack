import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../shared/constants/app_constants.dart';
import '../../shared/utils/bitcoin_script.dart';
import '../database/database.dart';

/// Lightweight Electrum JSON-RPC client (electrs / Fulcrum).
///
/// Uses a persistent TCP (or SSL) connection per session. Each [openSession]
/// call creates a new socket connection and performs the version handshake.
/// Call [ElectrumSession.close] when done.
class ElectrumService {
  ElectrumService(this._db);

  final AppDatabase _db;

  String _host = '';
  int _port = AppConstants.defaultElectrumTlsPort;

  /// TLS unless the user turns it off. It defaulted to plain TCP, over which
  /// anyone on the path reads every address the scan asks about — and can
  /// answer with forged or empty history (audit B-2).
  bool _ssl = true;

  String get host => _host;
  int get port => _port;
  bool get ssl => _ssl;

  /// True when a host has been configured by the user.
  bool get isConfigured => _host.isNotEmpty;

  // ── Settings ──────────────────────────────────────────────────────────────

  Future<void> loadSettings() async {
    final hostRows =
        await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(AppConstants.settingElectrumHost))).get();
    if (hostRows.isNotEmpty) _host = hostRows.first.value;

    final portRows =
        await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(AppConstants.settingElectrumPort))).get();
    final storedPort =
        portRows.isEmpty ? null : int.tryParse(portRows.first.value);

    final sslRows =
        await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(AppConstants.settingElectrumSsl))).get();
    if (sslRows.isNotEmpty) _ssl = sslRows.first.value == 'true';
    _port =
        storedPort ??
        (_ssl
            ? AppConstants.defaultElectrumTlsPort
            : AppConstants.defaultElectrumPort);

    final pinRows =
        await (_db.select(_db.appSettings)..where(
          (t) => t.key.equals(AppConstants.settingElectrumCertPin),
        )).get();
    if (pinRows.isNotEmpty) _pinnedFingerprint = pinRows.first.value;
  }

  /// [certificateFingerprint] is the self-signed certificate the user agreed
  /// to trust, from [fetchCertificateFingerprint]. Empty clears the pin, so
  /// only a CA-verified certificate is accepted.
  Future<void> saveSettings({
    required String host,
    required int port,
    required bool ssl,
    String certificateFingerprint = '',
  }) async {
    _host = host.trim();
    _port = port;
    _ssl = ssl;
    _pinnedFingerprint = certificateFingerprint;

    final entries = {
      AppConstants.settingElectrumHost: _host,
      AppConstants.settingElectrumPort: port.toString(),
      AppConstants.settingElectrumSsl: ssl.toString(),
      AppConstants.settingElectrumCertPin: _pinnedFingerprint,
    };
    for (final e in entries.entries) {
      await _db
          .into(_db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(key: e.key, value: e.value),
          );
    }
  }

  /// SHA-256 of the certificate the user chose to trust, or empty.
  String _pinnedFingerprint = '';

  String get pinnedFingerprint => _pinnedFingerprint;

  /// The fingerprint of whatever certificate [host]:[port] presents, for the
  /// "trust this server?" prompt. Null when the host verifies normally or
  /// cannot be reached.
  Future<String?> fetchCertificateFingerprint() async {
    X509Certificate? seen;
    try {
      final probe = await SecureSocket.connect(
        _host,
        _port,
        onBadCertificate: (certificate) {
          seen = certificate;
          return false; // never actually proceed on an unverified probe
        },
        timeout: const Duration(seconds: 10),
      );
      probe.destroy();
      return null; // verified by a real CA — nothing to pin
    } catch (_) {
      final certificate = seen;
      return certificate == null ? null : _fingerprintOf(certificate);
    }
  }

  bool _isPinned(X509Certificate certificate) =>
      _pinnedFingerprint.isNotEmpty &&
      _fingerprintOf(certificate) == _pinnedFingerprint;

  static String _fingerprintOf(X509Certificate certificate) =>
      sha256.convert(certificate.der).toString();

  // ── Session factory ───────────────────────────────────────────────────────

  /// Opens a new TCP/SSL connection and performs the Electrum version handshake.
  Future<ElectrumSession> openSession() async {
    // Closed by the session it is handed to, which the lint cannot follow.
    // ignore: close_sinks
    final Socket socket;
    if (_ssl) {
      socket = await SecureSocket.connect(
        _host,
        _port,
        // Certificates are verified. Accepting any of them — which this did,
        // for the convenience of self-signed servers — means anyone on the
        // network can sit in the middle of the connection and collect the
        // user's entire derived address set, which deanonymises their whole
        // wallet, while returning empty history so nothing looks wrong.
        //
        // A self-signed server is still usable: the user pins its fingerprint
        // once, and only that certificate is accepted afterwards.
        onBadCertificate: (certificate) => _isPinned(certificate),
        timeout: const Duration(seconds: 10),
      );
    } else {
      socket = await Socket.connect(
        _host,
        _port,
        timeout: const Duration(seconds: 10),
      );
    }
    // The session owns the socket from here, and closes it in
    // [ElectrumSession.close] — which a failed handshake used to skip, leaking
    // the socket and its listener on every server that refused the version.
    final session = ElectrumSession._(socket);
    try {
      // Handshake — negotiate protocol version
      await session.call('server.version', ['SatsStack/1.0', '1.4']);
    } catch (_) {
      session.close();
      rethrow;
    }
    return session;
  }

  // ── High-level helpers ────────────────────────────────────────────────────

  /// Returns a human-readable status string if the server is reachable,
  /// or throws on any failure.
  Future<String> testConnection() async {
    final session = await openSession();
    try {
      final banner = await session.call('server.banner', []);
      final peers = await session.call('server.peers.subscribe', []);
      final peerCount = (peers as List?)?.length ?? 0;
      return 'Connected to $_host:$_port'
          '${banner != null ? ' · ${(banner as String).split('\n').first.trim()}' : ''}'
          '${peerCount > 0 ? ' · $peerCount peers' : ''}';
    } finally {
      session.close();
    }
  }

  /// Fetches confirmed transaction history for a scripthash.
  ///
  /// Returns `({txid, height})` pairs. Only confirmed entries (height > 0) are
  /// included; height 0 = unconfirmed mempool, height -1 = unconfirmed child.
  Future<List<({String txid, int height})>> getHistory(
    ElectrumSession session,
    String scripthash,
  ) async {
    final result = await session.call('blockchain.scripthash.get_history', [
      scripthash,
    ]);
    if (result is! List) return [];
    return [
      for (final item in result)
        if (item case {
          'tx_hash': final String txid,
          'height': final int height,
        } when height > 0)
          (txid: txid, height: height),
    ];
  }

  /// Fetches a decoded (verbose) transaction by txid.
  ///
  /// Returns null if the server does not support verbose transactions or if the
  /// txid is not found. Never throws.
  Future<Map<String, dynamic>?> getTransaction(
    ElectrumSession session,
    String txid,
  ) async {
    try {
      final result = await session.call('blockchain.transaction.get', [
        txid,
        true,
      ]);
      return result as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Returns the UNIX timestamp of a block by height using its 80-byte header.
  ///
  /// Timestamp is a LE uint32 at bytes 68–71 of the block header.
  /// Returns null on any failure. Never throws.
  Future<int?> getBlockTimestamp(ElectrumSession session, int height) async {
    try {
      final result = await session.call('blockchain.block.header', [height]);
      if (result is! String || result.length < 160) return null;
      final bytes = _hexDecode(result);
      if (bytes.length < 72) return null;
      return bytes[68] |
          (bytes[69] << 8) |
          (bytes[70] << 16) |
          (bytes[71] << 24);
    } catch (_) {
      return null;
    }
  }
}

/// Address history read from an Electrum server, in the shape Esplora returns
/// it — `txid`, `status.confirmed`/`block_time`, `vout[].scriptpubkey_address`
/// and `value`, `vin[].prevout` — so the xpub scan nets, dedupes and prices it
/// with the same code whichever server it came from.
///
/// One per scan, over one session. Electrum answers in raw transactions, so
/// each is parsed here, and each input's spent output is read from its parent
/// transaction: a wallet's change can be paid to an address the scan has not
/// reached yet, so the spent output cannot be looked up among the wallet's own
/// history as it arrives. Transactions and block times are cached for the
/// scan, so a parent shared by several inputs is fetched once.
///
/// Requests are pipelined on the one connection — what Esplora needed one HTTP
/// request and a rate-limit pause for, an Electrum server answers in a batch
/// (TODO item 12) — with at most [maxInFlight] outstanding.
class ElectrumHistory {
  ElectrumHistory(this._electrum, this._session, {this.maxInFlight = 16});

  final ElectrumService _electrum;
  final ElectrumSession _session;
  final int maxInFlight;

  final _txs = <String, Future<RawTransaction>>{};
  final _blockTimes = <int, Future<int>>{};
  var _inFlight = 0;
  final _waiting = <Completer<void>>[];

  Future<T> _limited<T>(Future<T> Function() request) async {
    if (_inFlight >= maxInFlight) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _inFlight++;
    try {
      return await request();
    } finally {
      _inFlight--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }

  Future<dynamic> _call(String method, List<dynamic> params) =>
      _limited(() => _session.call(method, params));

  /// Every transaction each of [addresses] appears in, in order. Unconfirmed
  /// ones are included as unconfirmed — they mark an address as used — but
  /// carry nothing else, as Esplora's would be skipped by the scan anyway.
  ///
  /// Throws if any of it cannot be read: an address that could not be checked
  /// must not be reported as unused.
  Future<List<List<Map<String, dynamic>>>> fetchWindow(
    List<String> addresses,
  ) async {
    final histories = await Future.wait([
      for (final a in addresses)
        _call('blockchain.scripthash.get_history', [
          BitcoinScript.electrumScripthash(a),
        ]),
    ]);
    return Future.wait([
      for (final history in histories)
        Future.wait([
          for (final item in (history as List<dynamic>? ?? const []))
            _esploraShaped(item as Map<String, dynamic>),
        ]),
    ]);
  }

  Future<Map<String, dynamic>> _esploraShaped(Map<String, dynamic> item) async {
    final txid = item['tx_hash'] as String;
    final height = item['height'] as int;
    // 0 is in the mempool, -1 in the mempool with an unconfirmed parent.
    if (height <= 0) {
      return {
        'txid': txid,
        'status': {'confirmed': false},
      };
    }
    final (tx, time) = await (_tx(txid), _blockTime(height)).wait;
    final vin = await Future.wait([
      for (final input in tx.inputs) _prevout(input),
    ]);
    return {
      'txid': txid,
      'status': {'confirmed': true, 'block_time': time},
      'vin': [
        for (final prevout in vin) {'prevout': prevout},
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

  Future<Map<String, dynamic>> _prevout(({String txid, int vout}) input) async {
    final parent = await _tx(input.txid);
    if (input.vout >= parent.outputs.length) {
      throw FormatException('${input.txid} has no output ${input.vout}');
    }
    final spent = parent.outputs[input.vout];
    return {
      'scriptpubkey_address': BitcoinScript.addressFor(spent.script),
      'value': spent.value,
    };
  }

  Future<RawTransaction> _tx(String txid) =>
      _txs[txid] ??= _call('blockchain.transaction.get', [txid]).then(
        (hex) =>
            hex is String
                ? RawTransaction.parse(hex)
                : throw FormatException('No transaction $txid'),
      );

  Future<int> _blockTime(int height) =>
      _blockTimes[height] ??= _limited(
        () => _electrum.getBlockTimestamp(_session, height),
      ).then(
        (t) => t ?? (throw FormatException('No header for block $height')),
      );
}

List<int> _hexDecode(String hex) {
  final out = <int>[];
  for (var i = 0; i < hex.length - 1; i += 2) {
    out.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return out;
}

// ── Session ───────────────────────────────────────────────────────────────────

/// An active Electrum TCP session. Dispose by calling [close].
class ElectrumSession {
  ElectrumSession._(this._socket) {
    _subscription = _socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine, onError: _handleError, onDone: _handleDone);
  }

  final Socket _socket;
  final _pending = <int, Completer<dynamic>>{};
  int _nextId = 1;
  StreamSubscription<String>? _subscription;

  void _handleLine(String line) {
    if (line.trim().isEmpty) return;
    try {
      final msg = jsonDecode(line) as Map<String, dynamic>;
      final id = msg['id'];
      if (id is int) {
        final c = _pending.remove(id);
        if (c != null && !c.isCompleted) {
          final error = msg['error'];
          if (error != null) {
            c.completeError(Exception(error.toString()));
          } else {
            c.complete(msg['result']);
          }
        }
      }
    } catch (_) {
      // Malformed line — ignore
    }
  }

  void _handleError(dynamic e) {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(e);
    }
    _pending.clear();
  }

  void _handleDone() {
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(const SocketException('Connection closed'));
      }
    }
    _pending.clear();
  }

  /// Sends a JSON-RPC request and waits for the response.
  Future<dynamic> call(String method, List<dynamic> params) {
    final id = _nextId++;
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    _socket.writeln(jsonEncode({'id': id, 'method': method, 'params': params}));
    // The timeout has to remove the entry itself: applying it to the returned
    // future left the completer in `_pending` for the life of the socket, so a
    // long scan against a slow server accumulated one per timed-out request.
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException(
          '$method timed out',
          const Duration(seconds: 30),
        );
      },
    );
  }

  /// Closes the socket connection.
  void close() {
    _subscription?.cancel();
    _socket.destroy();
  }
}
