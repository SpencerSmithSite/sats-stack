/// Tests for the one claim in the app that must never be wrong.
///
/// `isPrivate` is no longer only a label on a settings page: it decides whether
/// the monthly insight generates on its own, and whether a statement is
/// uploaded to a third party before anything local is tried. If these fail, the
/// app is sending financial data somewhere it told the user it would not.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/ai_provider.dart';
import 'package:sats_stack/core/services/import_service.dart';
import 'package:sats_stack/core/services/inference/cloud_backend.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';

/// Keeps the platform keychain out of the test — reads return nothing, which is
/// the same path a user who has not entered a key takes.
class _NoKeyStore extends SecureKeyStore {
  const _NoKeyStore();
  @override
  Future<String> read(String providerId) async => '';
  @override
  Future<bool> write(String providerId, String value) async => true;
}

void main() {
  group('isLocalEndpoint', () {
    test('this device and the user own network count as local', () {
      for (final url in const [
        'http://localhost:11434',
        'http://127.0.0.1:1234/v1',
        'http://0.0.0.0:11434',
        'http://192.168.1.50:11434',
        'http://10.0.0.7:11434',
        'http://172.16.4.2:11434',
        'http://172.31.255.254:11434',
        'http://169.254.10.1:11434',
        'http://studio.local:1234/v1',
        '', // unset — a localhost default is in force
      ]) {
        expect(OllamaService.isLocalEndpoint(url), isTrue, reason: url);
      }
    });

    test('anything across the internet does not', () {
      for (final url in const [
        'https://llm.example.com/v1',
        'http://8.8.8.8:11434',
        'http://172.32.0.1:11434', // just outside the private range
        'http://203.0.113.9:1234/v1',
      ]) {
        expect(OllamaService.isLocalEndpoint(url), isFalse, reason: url);
      }
    });

    test('a URL with no readable host fails closed', () {
      // `Uri` reads `ollama.example.com` here as the *scheme*, leaving no
      // host, and the old check called a hostless URL local.
      expect(
        OllamaService.isLocalEndpoint('ollama.example.com:11434'),
        isFalse,
      );
      expect(OllamaService.isLocalEndpoint('not a url at all'), isFalse);
    });
  });

  group('the enum invariant still holds', () {
    test('isPrivate matches the absence of a named recipient', () {
      for (final provider in AiProvider.values) {
        expect(
          provider.isPrivate,
          provider.dataRecipient == null,
          reason: provider.key,
        );
      }
    });
  });

  group('error messages do not echo secrets', () {
    test('a 401 body is never passed through', () {
      // Verbatim shape of OpenAI's 401: it contains a partial copy of the key.
      const body =
          '{"error":{"message":"Incorrect API key provided: sk-proj-ab12****WXYZ. '
          'You can find your API key at https://platform.openai.com/account/api-keys.",'
          '"type":"invalid_request_error"}}';
      final message = CloudBackend.describeError(
        CloudProvider.openai,
        'gpt-5.6-terra',
        401,
        body,
      );

      expect(message, isNot(contains('sk-proj')));
      expect(message, isNot(contains('****')));
      expect(message, contains('Settings'));
    });

    test('other statuses still use the provider own message', () {
      const body = '{"error":{"message":"model is overloaded"}}';
      final message = CloudBackend.describeError(
        CloudProvider.openai,
        'gpt-5.6-terra',
        503,
        body,
      );
      expect(message, contains('overloaded'));
    });
  });

  group('off-device import consent', () {
    late AppDatabase db;
    late OllamaService ollama;
    late ImportService importService;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      ollama = OllamaService(db, keyStore: const _NoKeyStore());
      importService = ImportService(db, ollama);
    });

    tearDown(() => db.close());

    test('a private backend needs no consent', () async {
      await ollama.setActiveProvider(AiProvider.ollama);
      expect(ollama.sendsDataOffDevice, isFalse);
      expect(ollama.activeDataRecipient, isNull);
      expect(await importService.offDeviceImportAllowed(), isTrue);
    });

    test('a hosted backend is not allowed until the user agrees', () async {
      await ollama.setActiveProvider(AiProvider.claude);
      expect(ollama.sendsDataOffDevice, isTrue);
      expect(ollama.activeDataRecipient, contains('Anthropic'));

      // The default must be "no". An import that cannot ask must not send.
      expect(await importService.offDeviceImportAllowed(), isFalse);

      await importService.setOffDeviceImportAllowed(true);
      expect(await importService.offDeviceImportAllowed(), isTrue);
    });

    test('consent for one provider is not consent for another', () async {
      await ollama.setActiveProvider(AiProvider.claude);
      await importService.setOffDeviceImportAllowed(true);

      await ollama.setActiveProvider(AiProvider.chatGpt);
      expect(
        await importService.offDeviceImportAllowed(),
        isFalse,
        reason: 'agreeing to Anthropic is not agreeing to OpenAI',
      );

      await ollama.setActiveProvider(AiProvider.claude);
      expect(await importService.offDeviceImportAllowed(), isTrue);
    });

    test(
      'a bare host:port is normalised on save, not taken as local',
      () async {
        await ollama.setActiveProvider(AiProvider.ollama);
        await ollama.saveSettings(url: 'ollama.example.com:11434');
        expect(ollama.baseUrl, 'http://ollama.example.com:11434');
        expect(ollama.sendsDataOffDevice, isTrue);
        expect(ollama.activeDataRecipient, contains('ollama.example.com'));

        await ollama.saveSettings(url: '192.168.1.5:11434/');
        expect(ollama.baseUrl, 'http://192.168.1.5:11434');
        expect(ollama.sendsDataOffDevice, isFalse);

        // Blank is "use the default", which is this machine.
        await ollama.saveSettings(url: '');
        expect(ollama.sendsDataOffDevice, isFalse);
      },
    );

    test('a remote self-hosted server is disclosed by host', () async {
      await ollama.setActiveProvider(AiProvider.lmStudio);
      await ollama.saveLmStudioSettings(url: 'https://llm.example.com/v1');

      // The user's own box, but it is still across the internet, so the app
      // must not keep claiming nothing leaves the device.
      expect(ollama.sendsDataOffDevice, isTrue);
      expect(ollama.activeDataRecipient, contains('llm.example.com'));
      expect(await importService.offDeviceImportAllowed(), isFalse);

      await ollama.saveLmStudioSettings(url: 'http://192.168.1.20:1234/v1');
      expect(ollama.sendsDataOffDevice, isFalse);
      expect(ollama.activeDataRecipient, isNull);
      expect(await importService.offDeviceImportAllowed(), isTrue);
    });
  });
}
