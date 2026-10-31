/// What the app says about where AI requests go, and what it keeps.
///
/// A server on the local network was described as "nothing leaves", and a
/// remote server over plain http got no warning. Every chat question and answer
/// was written to `ai_conversations` and never read back. API keys were kept
/// under a keychain class that lets them move to another device in a backup.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/ai_provider.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';
import 'package:sats_stack/shared/constants/app_constants.dart';

/// Holds one Claude key and records what is written.
class _RecordingKeyStore extends SecureKeyStore {
  _RecordingKeyStore();
  final writes = <String>[];
  @override
  Future<String> read(String providerId) async =>
      providerId == 'anthropic' ? 'sk-ant-test' : '';
  @override
  Future<bool> write(String providerId, String value) async {
    writes.add(providerId);
    return true;
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('transport notes', () {
    String? note(AiProvider p, String url) =>
        OllamaService.transportNoteFor(p, url);

    test('this device: nothing to say', () {
      expect(note(AiProvider.ollama, 'http://localhost:11434'), isNull);
      expect(note(AiProvider.ollama, 'http://127.0.0.1:11434'), isNull);
      expect(note(AiProvider.ollama, ''), isNull);
    });

    test('the local network is named as a network hop', () {
      expect(
        note(AiProvider.ollama, 'http://192.168.1.5:11434'),
        contains('local network to 192.168.1.5'),
      );
      expect(
        note(AiProvider.lmStudio, 'mac-mini.local:1234/v1'),
        contains('mac-mini.local'),
      );
    });

    // Decided 2026-10-31: someone running their own AI server knows where it
    // is. A server on their network gets no consent prompt and no off-device
    // banner — no recipient — and its note states the fact without a warning.
    test('the local network is treated as the user own hardware', () {
      for (final p in [AiProvider.ollama, AiProvider.lmStudio]) {
        expect(
          OllamaService.recipientFor(p, 'http://192.168.1.5:11434'),
          isNull,
        );
        expect(
          OllamaService.recipientFor(p, 'https://llm.example.com'),
          isNotNull,
        );
      }
      expect(
        note(AiProvider.ollama, 'http://192.168.1.5:11434'),
        'Sent over your local network to 192.168.1.5, and no further.',
      );
    });

    test('plain http to a remote server is called unencrypted', () {
      expect(
        note(AiProvider.ollama, 'http://ollama.example.com:11434'),
        contains('unencrypted'),
      );
      expect(note(AiProvider.ollama, 'https://ollama.example.com'), isNull);
    });

    test('hosted providers have no such note', () {
      expect(note(AiProvider.claude, 'http://example.com'), isNull);
      expect(note(AiProvider.appleIntelligence, ''), isNull);
    });

    test('loopback is narrower than local', () {
      expect(OllamaService.isLoopbackEndpoint('http://192.168.1.5'), isFalse);
      expect(OllamaService.isLocalEndpoint('http://192.168.1.5'), isTrue);
      expect(OllamaService.isLoopbackEndpoint('http://localhost:1'), isTrue);
    });
  });

  group('storage', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('stored transcripts are cleared', () async {
      await db
          .into(db.aiConversations)
          .insert(
            AiConversationsCompanion.insert(
              prompt: 'How much did I spend?',
              response: '£1,240',
              model: 'm',
            ),
          );
      await OllamaService(db).clearStoredTranscripts();
      expect(await db.select(db.aiConversations).get(), isEmpty);
    });

    test('keys are rewritten under the new keychain class once', () async {
      final keys = _RecordingKeyStore();
      await OllamaService(db, keyStore: keys).loadSettings();
      expect(keys.writes, ['anthropic']);

      final flag =
          await (db.select(db.appSettings)..where(
            (s) => s.key.equals(AppConstants.settingKeysDeviceOnly),
          )).getSingle();
      expect(flag.value, 'true');

      keys.writes.clear();
      await OllamaService(db, keyStore: keys).loadSettings();
      expect(keys.writes, isEmpty);
    });
  });
}
