/// One rule for whether the AI tab is visible.
///
/// It lived in three places — Settings, onboarding, and the startup seed in
/// main.dart — and they disagreed: Settings omitted the hosted-provider term
/// onboarding had, so a mobile user with a saved Anthropic key lost the tab by
/// switching provider and back, and main.dart seeded it from a readiness probe
/// `loadSettings` only kicks off, so on-device providers lost the tab after
/// every restart. CLAUDE.md claimed these paths could not drift.
///
/// `isUsableWithoutDesktop` is the part of the rule that is not about the
/// host platform, so it can be tested on a desktop test runner.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/ai_provider.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';

/// Keeps the platform keychain out of the test. [stored] is what the keychain
/// would hand back for every provider.
class _FakeKeyStore extends SecureKeyStore {
  const _FakeKeyStore(this.stored);
  final String stored;
  @override
  Future<String> read(String providerId) async => stored;
  @override
  Future<bool> write(String providerId, String value) async => true;
  @override
  Future<void> delete(String providerId) async {}
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<OllamaService> serviceWith({String key = ''}) async {
    final s = OllamaService(db, keyStore: _FakeKeyStore(key));
    await s.loadSettings();
    return s;
  }

  group('on a device that is not a desktop', () {
    test('an on-device backend needs no server and no probe', () async {
      final ollama = await serviceWith();
      for (final p in AiProvider.values.where((p) => p.isOnDevice)) {
        expect(ollama.isUsableWithoutDesktop(p), isTrue, reason: p.key);
      }
    });

    test('a hosted provider is usable once a key is saved', () async {
      final withKey = await serviceWith(key: 'sk-test-123');
      final withoutKey = await serviceWith();

      for (final p in AiProvider.values.where((p) => p.needsApiKey)) {
        expect(withKey.isUsableWithoutDesktop(p), isTrue, reason: p.key);
        expect(withoutKey.isUsableWithoutDesktop(p), isFalse, reason: p.key);
      }
    });

    test('a server-backed provider needs a host that answered', () async {
      final ollama = await serviceWith();
      for (final p in [
        AiProvider.ollama,
        AiProvider.lmStudio,
        AiProvider.maple,
      ]) {
        expect(ollama.isUsableWithoutDesktop(p), isFalse, reason: p.key);
      }

      await ollama.setActiveProvider(AiProvider.ollama);
      await ollama.setConnected(true);
      expect(ollama.isUsableWithoutDesktop(AiProvider.ollama), isTrue);
      // Still nothing has been verified for the others.
      expect(ollama.isUsableWithoutDesktop(AiProvider.lmStudio), isFalse);
    });

    test('every provider is covered — no silent fall-through', () async {
      final ollama = await serviceWith(key: 'sk-test-123');
      for (final p in AiProvider.values) {
        expect(
          () => ollama.isUsableWithoutDesktop(p),
          returnsNormally,
          reason: p.key,
        );
      }
    });
  });

  test(
    'switching provider and back does not lose a saved hosted key',
    () async {
      // The exact reported failure: pick Claude with a key, switch away, switch
      // back. Settings recomputed the flag without the hosted term, so the tab
      // disappeared and did not return.
      final ollama = await serviceWith(key: 'sk-test-123');

      await ollama.setActiveProvider(AiProvider.claude);
      expect(ollama.isUsableWithoutDesktop(ollama.activeProvider), isTrue);

      await ollama.setActiveProvider(AiProvider.ollama);
      expect(ollama.isUsableWithoutDesktop(ollama.activeProvider), isFalse);

      await ollama.setActiveProvider(AiProvider.claude);
      expect(ollama.isUsableWithoutDesktop(ollama.activeProvider), isTrue);
    },
  );

  test('the startup seed agrees with the live rule', () async {
    // main.dart used to seed from `isDesktop || isConnected`, where an
    // on-device provider's isConnected is a probe loadSettings only starts.
    final ollama = await serviceWith();
    await ollama.setActiveProvider(AiProvider.appleIntelligence);

    final reloaded = OllamaService(db, keyStore: const _FakeKeyStore(''));
    await reloaded.loadSettings();

    expect(reloaded.activeProvider, AiProvider.appleIntelligence);
    // The phone half of the rule. `aiEnabled` is true on any desktop, which is
    // what these tests run on, so asserting it could never fail here.
    expect(reloaded.isUsableWithoutDesktop(reloaded.activeProvider), isTrue);
  });

  test(
    'the startup seed does not invent a server that never answered',
    () async {
      final ollama = await serviceWith();
      await ollama.setActiveProvider(AiProvider.ollama);

      final reloaded = OllamaService(db, keyStore: const _FakeKeyStore(''));
      await reloaded.loadSettings();

      expect(reloaded.activeProvider, AiProvider.ollama);
      expect(reloaded.isUsableWithoutDesktop(reloaded.activeProvider), isFalse);
    },
  );
}
