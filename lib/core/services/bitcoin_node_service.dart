import 'dart:convert';

import 'package:http/http.dart' as http;

import '../database/database.dart';
import '../../shared/constants/app_constants.dart';
import 'secure_key_store.dart';

/// Bitcoin Core / Knots JSON-RPC client.
///
/// Credentials (URL, user) are persisted in the app settings database. The
/// password goes to the keychain through [SecureKeyStore], which is the one
/// place that knows the per-platform options — notably that macOS has to use
/// the file-based keychain, because a write to the data-protection one fails
/// with errSecMissingEntitlement on this ad-hoc-signed target.
///
/// NOTE: Bitcoin Core is NOT optimised for address history scanning.
/// This service is for connection testing and future transaction broadcasting
/// only. Use [ElectrumService] for xpub wallet scanning.
class BitcoinNodeService {
  BitcoinNodeService(this._db);

  final AppDatabase _db;
  static const _keys = SecureKeyStore();

  String _rpcUrl = AppConstants.defaultBitcoinRpcUrl;
  String _rpcUser = '';

  String get rpcUrl => _rpcUrl;
  String get rpcUser => _rpcUser;

  bool get isConfigured => _rpcUser.isNotEmpty;

  // ── Settings ──────────────────────────────────────────────────────────────

  Future<void> loadSettings() async {
    final urlRows = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(AppConstants.settingBitcoinRpcUrl)))
        .get();
    if (urlRows.isNotEmpty && urlRows.first.value.isNotEmpty) {
      _rpcUrl = urlRows.first.value;
    }

    final userRows = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(AppConstants.settingBitcoinRpcUser)))
        .get();
    if (userRows.isNotEmpty) _rpcUser = userRows.first.value;
  }

  Future<String> loadPassword() =>
      _keys.readEntry(AppConstants.settingBitcoinRpcPassword);

  Future<void> saveSettings({
    required String url,
    required String user,
    required String password,
  }) async {
    _rpcUrl = url.trim().isNotEmpty ? url.trim() : AppConstants.defaultBitcoinRpcUrl;
    _rpcUser = user.trim();

    for (final e in {
      AppConstants.settingBitcoinRpcUrl: _rpcUrl,
      AppConstants.settingBitcoinRpcUser: _rpcUser,
    }.entries) {
      await _db.into(_db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: e.key, value: e.value),
      );
    }

    await _keys.writeEntry(
      AppConstants.settingBitcoinRpcPassword,
      password.trim(),
    );
  }

  // ── RPC ───────────────────────────────────────────────────────────────────

  /// Executes a Bitcoin Core JSON-RPC call.
  Future<dynamic> rpcCall(String method, List<dynamic> params) async {
    final password = await loadPassword();
    final credentials = base64Encode(utf8.encode('$_rpcUser:$password'));

    final response = await http
        .post(
          Uri.parse(_rpcUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Basic $credentials',
          },
          body: jsonEncode({
            'jsonrpc': '1.0',
            'id': 'satsstack',
            'method': method,
            'params': params,
          }),
        )
        .timeout(const Duration(seconds: 15));

    // Status first. Bitcoin Core answers a bad cookie or credential with 401
    // and a non-JSON body, so decoding first turned "wrong password" into
    // `FormatException: Unexpected character` — and a 403 from rpcallowip into
    // the same thing.
    switch (response.statusCode) {
      case 200:
        break;
      case 401:
      case 403:
        throw Exception(
          'The node rejected these credentials. Check the RPC user and '
          'password, and that this device is allowed by rpcallowip.',
        );
      case 404:
        throw Exception(
          'No JSON-RPC endpoint at $_rpcUrl — check the URL and port.',
        );
      default:
        throw Exception('The node returned HTTP ${response.statusCode}.');
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw Exception('$_rpcUrl did not return JSON — is this a Bitcoin node?');
    }
    final error = body['error'];
    if (error != null) {
      throw Exception(
          error is Map<String, dynamic> ? error['message'] ?? error : error);
    }
    return body['result'];
  }

  /// Returns blockchain info from the node, or throws on failure.
  Future<Map<String, dynamic>> getBlockchainInfo() async {
    return await rpcCall('getblockchaininfo', []) as Map<String, dynamic>;
  }

  /// Tests the connection and returns a status string.
  Future<String> testConnection() async {
    final info = await getBlockchainInfo();
    final blocks = info['blocks'] as int? ?? 0;
    final chain = info['chain'] as String? ?? 'unknown';
    final progress = ((info['verificationprogress'] as double? ?? 0) * 100)
        .toStringAsFixed(1);
    final formatted = blocks
        .toString()
        .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return 'Connected · $chain · block $formatted · ${progress}% synced';
  }
}
