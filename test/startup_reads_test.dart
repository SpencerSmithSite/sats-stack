/// Launch reads the keychain once per provider, all at once (audit D-10).
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/inference/cloud_backend.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';

/// A different key for every provider, so a key landing on the wrong one
/// shows.
class _KeyPerProvider extends SecureKeyStore {
  final reads = <String>[];
  @override
  Future<String> read(String providerId) async {
    reads.add(providerId);
    return 'key-$providerId';
  }

  @override
  Future<bool> write(String providerId, String value) async => true;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('each stored key is loaded for its own provider', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final keys = _KeyPerProvider();
    final service = OllamaService(db, keyStore: keys);
    await service.loadSettings();

    for (final p in CloudProvider.values) {
      expect(service.cloudApiKey(p), 'key-${p.id}', reason: p.name);
    }
    expect(service.mapleApiKey, startsWith('key-'));
    expect(
      service.mapleApiKey,
      isNot(anyOf([for (final p in CloudProvider.values) 'key-${p.id}'])),
    );
    // Each read once.
    expect(keys.reads.toSet(), hasLength(keys.reads.length));
    expect(keys.reads, hasLength(CloudProvider.values.length + 1));
  });
}
