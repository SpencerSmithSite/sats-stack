import '../../shared/utils/url_utils.dart';
import 'secure_key_store.dart';

/// Logins in server addresses, kept in the keychain rather than in
/// `AppSettings` (audit A-17).
///
/// A `user:password@` part is how a server behind Basic auth is reached — the
/// HTTP client sends it as the Authorization header — so it is used, but
/// `AppSettings` is plain SQLite that Settings → Data exports whole. The table
/// keeps the address without it; the keychain holds the whole address the
/// login was saved with. Shared by the AI servers and the Mempool/Esplora
/// server.
class ServerLogins {
  ServerLogins(this._keys, this._writeSetting);

  final SecureKeyStore _keys;
  final Future<void> Function(String key, String value) _writeSetting;

  /// Settings whose login the keychain refused, so it is still in the table.
  final outsideKeychain = <String>{};

  /// The keychain entry holding the login for the server in [settingKey].
  static String entry(String settingKey) => 'server_login_$settingKey';

  /// [saved] — the address stored under [settingKey], normalised — with its
  /// login put back.
  ///
  /// The login is used only while the saved address still goes to the same
  /// place: a restored backup that names another server must not be sent it.
  /// An address still carrying a login in the table — saved by an earlier
  /// build, or when the keychain refused — is moved into the keychain now.
  Future<String> load(String settingKey, String saved) async {
    final split = splitUserInfo(saved);
    if (split.userInfo != null) {
      if (await _keys.writeEntry(entry(settingKey), saved)) {
        await _writeSetting(settingKey, split.url);
        outsideKeychain.remove(settingKey);
      } else {
        outsideKeychain.add(settingKey);
      }
      return saved;
    }
    final withLogin = await _keys.readEntry(entry(settingKey));
    if (withLogin.isEmpty || serverOrigin(withLogin) != serverOrigin(saved)) {
      return saved;
    }
    return withUserInfo(saved, splitUserInfo(withLogin).userInfo);
  }

  /// Saves [typed] — normalised — under [settingKey] and returns the address
  /// to use, login included. [current] is the address in use, whose login a
  /// field shown as [passwordMask] keeps. If the keychain refuses, the whole
  /// address is stored as before, so the server still works, and
  /// [outsideKeychain] names it.
  Future<String> save(
    String settingKey,
    String typed, {
    required String current,
  }) async {
    final split = splitUserInfo(typed);
    final login = resolveTypedUserInfo(
      split.userInfo,
      splitUserInfo(current).userInfo,
    );
    final full = withUserInfo(split.url, login);
    final stored = await _keys.writeEntry(
      entry(settingKey),
      login == null ? '' : full,
    );
    await _writeSetting(settingKey, stored ? split.url : full);
    if (!stored && login != null) {
      outsideKeychain.add(settingKey);
    } else {
      outsideKeychain.remove(settingKey);
    }
    return full;
  }

  /// Drops [settingKey]'s login: the server is no longer one with a login.
  Future<void> forget(String settingKey) async {
    await _keys.deleteEntry(entry(settingKey));
    outsideKeychain.remove(settingKey);
  }
}
