/// The downloadable-model backend was removed (flutter_gemma is discontinued).
/// These pin what happens to someone who had used it: their choice moves to an
/// on-device model rather than vanishing, and the gigabytes of weights it left
/// behind are deleted — and nothing else is.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/ai_provider.dart';
import 'package:sats_stack/core/services/inference/gemini_nano_backend.dart';
import 'package:sats_stack/core/services/inference/platform_llm_backend.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/removed_model_cleanup.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';
import 'package:sats_stack/shared/constants/app_constants.dart';

class _NoKeyStore extends SecureKeyStore {
  const _NoKeyStore();
  @override
  Future<String> read(String providerId) async => '';
  @override
  Future<bool> write(String providerId, String value) async => true;
}

void main() {
  group('a stored choice of the removed backend', () {
    test('moves to the platform model, never to anything hosted', () {
      expect(
        OllamaService.replacementForRemovedLocalModel(
          appleBridged: true,
          androidBridged: false,
        ),
        AiProvider.appleIntelligence,
      );
      expect(
        OllamaService.replacementForRemovedLocalModel(
          appleBridged: false,
          androidBridged: true,
        ),
        AiProvider.geminiNano,
      );
      // Nowhere with a built-in model: the self-hosted default, which is
      // private, rather than a provider that would send data away.
      final none = OllamaService.replacementForRemovedLocalModel(
        appleBridged: false,
        androidBridged: false,
      );
      expect(none, AiProvider.ollama);
      expect(none.isPrivate, isTrue);
    });

    test('is rewritten on load, and its model setting deleted', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      for (final (key, value) in [
        (AppConstants.settingAiProvider, AiProvider.removedLocalModelKey),
        (AppConstants.settingRemovedLocalModelId, 'qwen3-1.7b'),
      ]) {
        await db
            .into(db.appSettings)
            .insert(AppSettingsCompanion.insert(key: key, value: value));
      }

      final ollama = OllamaService(db, keyStore: const _NoKeyStore());
      await ollama.loadSettings();

      final expected = OllamaService.replacementForRemovedLocalModel(
        appleBridged: PlatformLlmBackend.bridgedHere,
        androidBridged: GeminiNanoBackend.bridgedHere,
      );
      expect(ollama.activeProvider, expected);
      final rows = {
        for (final r in await db.select(db.appSettings).get()) r.key: r.value,
      };
      expect(rows[AppConstants.settingAiProvider], expected.key);
      expect(
        rows.containsKey(AppConstants.settingRemovedLocalModelId),
        isFalse,
      );
    });
  });

  group('the downloaded weights', () {
    late Directory documents;
    late Directory support;

    setUp(() async {
      final root = await Directory.systemTemp.createTemp('model_cleanup');
      documents = await Directory('${root.path}/Documents').create();
      support = await Directory('${root.path}/Support').create();
    });

    File touch(Directory dir, String name, [int bytes = 10]) =>
        File('${dir.path}/$name')..writeAsBytesSync(List.filled(bytes, 0));

    test('are deleted, with partial downloads, from both locations', () async {
      touch(documents, 'Qwen3_1.7B.litertlm', 100);
      touch(documents, 'qwen3_8b_mixed_int4.litertlm.part', 50);
      final macDir = await Directory('${support.path}/flutter_gemma').create();
      touch(macDir, 'qwen3_0_6b_mixed_int4.litertlm', 30);

      final freed = await RemovedModelCleanup.run(
        documents: documents,
        support: support,
      );

      expect(freed, 180);
      expect(documents.listSync(), isEmpty);
      expect(macDir.existsSync(), isFalse);
    });

    test('and nothing else is, the database above all', () async {
      // The database lives in the same Documents folder.
      final db = touch(documents, 'sats_stack.sqlite');
      final backup = touch(documents, 'sats_stack.sqlite.bak');
      final someoneElses = touch(documents, 'notes.litertlm');
      final keep = touch(support, 'other_settings.json');

      await RemovedModelCleanup.run(documents: documents, support: support);

      for (final f in [db, backup, someoneElses, keep]) {
        expect(f.existsSync(), isTrue, reason: f.path);
      }
    });

    test('a device that never had the backend is left alone', () async {
      expect(
        await RemovedModelCleanup.run(documents: documents, support: support),
        0,
      );
    });
  });
}
