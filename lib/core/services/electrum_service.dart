import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../database/database.dart';
import '../../shared/constants/app_constants.dart';

/// Lightweight Electrum JSON-RPC client (electrs / Fulcrum).
///
/// Uses a persistent TCP (or SSL) connection per session. Each [openSession]
/// call creates a new socket connection and performs the version handshake.
/// Call [ElectrumSession.close] when done.
class ElectrumService {
  ElectrumService(this._db);

  final AppDatabase _db;

  String _host = '';
  int _port = AppConstants.defaultElectrumPort;
  bool _ssl = false;

  String get host => _host;
  int get port => _port;
  bool get ssl => _ssl;

  /// True when a host has been configured by the user.
  bool get isConfigured => _host.isNotEmpty;

  // ── Settings ──────────────────────────────────────────────────────────────

  Future<void> loadSettings() async {
    final hostRows = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(AppConstants.settingElectrumHost)))
        .get();
    if (hostRows.isNotEmpty) _host = hostRows.first.value;

    final portRows = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(AppConstants.settingElectrumPort)))
        .get();
    if (portRows.isNotEmpty) {
      _port = int.tryParse(portRows.first.value) ?? AppConstants.defaultElectrumPort;
    }

    final sslRows = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(AppConstants.settingElectrumSsl)))
        .get();
    if (sslRows.isNotEmpty) _ssl = sslRows.first.value == 'true';

    final pinRows = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(AppConstants.settingElectrumCertPin)))
        .get();
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
      await _db.into(_db.appSettings).insertOnConflictUpdate(
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
    final session = ElectrumSession._(socket);
    // Handshake — negotiate protocol version
    await session.call('server.version', ['SatsStack/1.0', '1.4']);
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
    final result =
        await session.call('blockchain.scripthash.get_history', [scripthash]);
    if (result == null) return [];
    return (result as List<dynamic>)
        .where((item) {
          final h = item['height'];
          return h is int && h > 0;
        })
        .map((item) => (
              txid: item['tx_hash'] as String,
              height: item['height'] as int,
            ))
        .toList();
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
      final result =
          await session.call('blockchain.transaction.get', [txid, true]);
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
      final result =
          await session.call('blockchain.block.header', [height]);
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
        .listen(
          _handleLine,
          onError: _handleError,
          onDone: _handleDone,
        );
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
        throw TimeoutException('$method timed out', const Duration(seconds: 30));
      },
    );
  }

  /// Closes the socket connection.
  void close() {
    _subscription?.cancel();
    _socket.destroy();
  }
}
