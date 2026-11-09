/// A server login in an address is used, but kept in the keychain and never
/// shown (audit A-17).
///
/// `https://user:pass@host` is how a server behind Basic auth is reached, so
/// it has to keep working. It used to be stored as typed in `AppSettings` —
/// plain SQLite that Settings → Data exports whole — and shown verbatim in
/// Settings, the chat and every "could not reach" message.
library;

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/inference/inference_backend.dart';
import 'package:sats_stack/core/services/inference/remote_backends.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';
import 'package:sats_stack/shared/constants/app_constants.dart';
import 'package:sats_stack/shared/utils/url_utils.dart';

class _Keychain extends SecureKeyStore {
  _Keychain({this.refuses = false});
  final bool refuses;
  final entries = <String, String>{};

  @override
  Future<String> read(String providerId) async => entries[providerId] ?? '';
  @override
  Future<bool> write(String providerId, String value) async {
    if (refuses) return false;
    if (value.isEmpty) {
      entries.remove(providerId);
    } else {
      entries[providerId] = value;
    }
    return true;
  }

  @override
  Future<void> delete(String providerId) async => entries.remove(providerId);
  @override
  Future<String> readEntry(String entry) => read(entry);
  @override
  Future<bool> writeEntry(String entry, String value) => write(entry, value);
  @override
  Future<void> deleteEntry(String entry) => delete(entry);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('addresses', () {
    const url = 'https://alice:s3cret@ollama.example.com:8443';

    test('split, put back and masked', () {
      final split = splitUserInfo(url);
      expect(split.url, 'https://ollama.example.com:8443');
      expect(split.userInfo, 'alice:s3cret');
      expect(withUserInfo(split.url, split.userInfo), url);
      expect(maskPassword(url), 'https://alice:••••••@ollama.example.com:8443');
      expect(maskPassword('http://bob@host:11434'), 'http://bob@host:11434');
      expect(maskPassword('http://host:11434'), 'http://host:11434');
    });

    test('the mask typed back keeps the saved password', () {
      final masked = splitUserInfo(maskPassword(url)).userInfo;
      expect(resolveTypedUserInfo(masked, 'alice:s3cret'), 'alice:s3cret');
      expect(resolveTypedUserInfo('alice:new', 'alice:s3cret'), 'alice:new');
      expect(resolveTypedUserInfo(null, 'alice:s3cret'), isNull);
      // Another user does not inherit alice's password.
      final bobMasked =
          splitUserInfo(
            maskPassword('https://bob:x@ollama.example.com'),
          ).userInfo;
      expect(resolveTypedUserInfo(bobMasked, 'alice:s3cret'), 'bob');
    });
  });

  group('OllamaService', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<String?> stored(String key) async =>
        (await (db.select(db.appSettings)
              ..where((t) => t.key.equals(key))).getSingleOrNull())
            ?.value;

    String sentTo(OllamaService s) => (s.backend as OllamaBackend).baseUrl;

    test('a login goes to the keychain, not the table', () async {
      final keys = _Keychain();
      final s = OllamaService(db, keyStore: keys);
      await s.saveSettings(url: 'https://alice:s3cret@ollama.example.com');

      expect(
        await stored(AppConstants.settingOllamaUrl),
        'https://ollama.example.com',
      );
      expect(keys.entries.values.join(), contains('s3cret'));
      expect(sentTo(s), 'https://alice:s3cret@ollama.example.com');
      expect(s.baseUrl, 'https://alice:••••••@ollama.example.com');
      expect(s.credentialsOutsideKeychain, isEmpty);

      // The Settings field shows the masked address; saved unchanged, it
      // keeps the password.
      await s.saveSettings(url: s.baseUrl);
      expect(sentTo(s), 'https://alice:s3cret@ollama.example.com');

      // And it is back after a restart.
      final next = OllamaService(db, keyStore: keys);
      await next.loadSettings();
      expect(sentTo(next), 'https://alice:s3cret@ollama.example.com');

      // Taking the login out of the field removes it.
      await next.saveSettings(url: 'https://ollama.example.com');
      expect(sentTo(next), 'https://ollama.example.com');
      expect(keys.entries.values.join(), isNot(contains('s3cret')));
    });

    test('an address saved by an earlier build is moved', () async {
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: AppConstants.settingLmStudioUrl,
              value: 'https://bob:hunter2@lm.example.com',
            ),
          );
      final keys = _Keychain();
      final s = OllamaService(db, keyStore: keys);
      await s.loadSettings();

      expect(
        await stored(AppConstants.settingLmStudioUrl),
        'https://lm.example.com',
      );
      expect(s.lmStudioBaseUrl, 'https://bob:••••••@lm.example.com');
      expect(keys.entries.values.join(), contains('hunter2'));
    });

    test('a login is not sent to another server', () async {
      // Saved for one server; then a backup restored that names another.
      final keys = _Keychain();
      await OllamaService(
        db,
        keyStore: keys,
      ).saveSettings(url: 'https://alice:s3cret@ollama.example.com');
      await (db.update(db.appSettings)..where(
        (t) => t.key.equals(AppConstants.settingOllamaUrl),
      )).write(const AppSettingsCompanion(value: Value('https://other.net')));

      final s = OllamaService(db, keyStore: keys);
      await s.loadSettings();
      expect(sentTo(s), 'https://other.net');
    });

    test(
      'when the keychain refuses, the server works and it says so',
      () async {
        await db
            .into(db.appSettings)
            .insert(
              AppSettingsCompanion.insert(
                key: AppConstants.settingMapleApiKey,
                value: 'mk-legacy',
              ),
            );
        final s = OllamaService(db, keyStore: _Keychain(refuses: true));
        await s.loadSettings();
        await s.saveSettings(url: 'https://alice:s3cret@ollama.example.com');

        expect(sentTo(s), 'https://alice:s3cret@ollama.example.com');
        expect(s.credentialsOutsideKeychain, [
          'your Maple API key',
          'your Ollama server login',
        ]);
      },
    );
  });

  test('a failed request does not print the password', () async {
    final backend = OllamaBackend(
      baseUrl: 'https://alice:s3cret@ollama.example.com',
      model: 'llama3',
      isPrivate: false,
    );
    final client = MockClient(
      (req) async => throw http.ClientException('Connection refused', req.url),
    );
    await expectLater(
      backend.chat([
        {'role': 'user', 'content': 'hi'},
      ], client: client).toList(),
      throwsA(
        isA<InferenceException>()
            .having((e) => e.message, 'message', contains('alice:••••••@'))
            .having((e) => e.message, 'message', isNot(contains('s3cret'))),
      ),
    );
  });
}
