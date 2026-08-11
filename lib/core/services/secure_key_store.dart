import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the user's AI provider API keys in the platform's secure store.
///
/// Keys are the user's own credentials for services they pay for, and they do
/// not belong in `AppSettings`. That table is ordinary SQLite inside the app's
/// documents directory: Settings → Data exports the whole file on request, the
/// backup plan copies it, and `docs/AGENT_ACCESS_PLAN.md` proposes handing it
/// to an MCP server. A key written there leaks through all three without anyone
/// intending it.
///
/// Everything else about a provider — which one is selected, which model, the
/// server URL — stays in `AppSettings`. It is configuration, not a secret, and
/// putting it in the keychain would only make it harder to export and restore.
class SecureKeyStore {
  const SecureKeyStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    // Without this Android falls back to plain SharedPreferences on older API
    // levels, which would defeat the point of moving the keys at all.
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    // `first_unlock` rather than the default `unlocked`: the monthly insight
    // can be generated from a background refresh while the device is locked,
    // and the stricter class would make the key unreadable exactly then.
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock,
      // The file-based keychain rather than the data-protection one.
      //
      // The data-protection keychain requires a `keychain-access-groups`
      // entitlement, which in turn requires the macOS bundle id to be
      // registered with Apple and signed against a real provisioning profile.
      // Sats Stack's macOS target is ad-hoc signed, so every write there fails
      // at runtime with errSecMissingEntitlement (-34018) — it compiles, links
      // and launches, and only the write fails. See
      // integration_test/secure_key_store_test.dart, which is what caught it.
      //
      // The file-based keychain is still encrypted at rest and still gated on
      // the app's code signature; it is what Mac apps used before the
      // data-protection keychain existed. If the macOS build is ever properly
      // provisioned, flip this back and add the entitlement.
      useDataProtectionKeyChain: false,
    ),
  );

  /// Entry name for a provider's key. Derived from the provider id, so renaming
  /// an id orphans the stored key rather than exposing it.
  static String entryName(String providerId) => 'ai_api_key_$providerId';

  /// The saved key, or an empty string.
  ///
  /// Never throws. The secure store can genuinely be unavailable — a locked
  /// device, a Linux box with no keyring daemon, a corrupted keychain entry
  /// after a restore — and none of those should stop the app launching. The
  /// caller sees "no key", which routes to the same "add one in Settings"
  /// message as a user who has not entered one yet.
  Future<String> read(String providerId) async {
    try {
      return await _storage.read(key: entryName(providerId)) ?? '';
    } catch (e) {
      debugPrint('SecureKeyStore: could not read $providerId key: $e');
      return '';
    }
  }

  /// Save a key, or delete the entry when [value] is blank.
  ///
  /// Returns false if the secure store rejected the write. Callers should tell
  /// the user rather than carrying on: silently keeping a key in memory that
  /// vanishes at next launch is worse than an error, because the backend works
  /// until it does not.
  ///
  /// Deliberately no plaintext fallback. If the keychain will not hold the key
  /// then the app cannot store it safely, and writing it somewhere else would
  /// break the promise this class exists to keep.
  Future<bool> write(String providerId, String value) async {
    final trimmed = value.trim();
    try {
      if (trimmed.isEmpty) {
        await _storage.delete(key: entryName(providerId));
      } else {
        await _storage.write(key: entryName(providerId), value: trimmed);
      }
      return true;
    } catch (e) {
      debugPrint('SecureKeyStore: could not write $providerId key: $e');
      return false;
    }
  }

  /// Remove a provider's key. Used by Settings → Danger Zone → Reset all data,
  /// where leaving credentials behind after a reset would be surprising.
  Future<void> delete(String providerId) async {
    try {
      await _storage.delete(key: entryName(providerId));
    } catch (e) {
      debugPrint('SecureKeyStore: could not delete $providerId key: $e');
    }
  }
}
