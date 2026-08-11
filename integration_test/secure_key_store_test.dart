import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';

/// Proves the keychain actually accepts a write on this platform.
///
/// This cannot be tested under `flutter test`: `flutter_secure_storage` is a
/// platform channel, and with no engine every call returns null — which is
/// indistinguishable from "no key saved", the exact failure this is meant to
/// catch. Run with:
///
///   flutter test integration_test/secure_key_store_test.dart -d macos
///
/// The sandbox is the real risk. A sandboxed macOS app reaches its own keychain
/// access group by default, but a missing entitlement would fail here rather
/// than at compile time, and the symptom in the app would be a key that saves
/// fine and is gone at next launch.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const store = SecureKeyStore();
  const testId = '__integration_test__';

  tearDown(() => store.delete(testId));

  testWidgets('a key survives a write and read', (_) async {
    final ok = await store.write(testId, 'sk-ant-not-a-real-key');
    expect(ok, isTrue, reason: 'the keychain refused the write');
    expect(await store.read(testId), 'sk-ant-not-a-real-key');
  });

  testWidgets('an overwritten key returns the new value', (_) async {
    await store.write(testId, 'first');
    await store.write(testId, 'second');
    expect(await store.read(testId), 'second');
  });

  testWidgets('a blank value deletes the entry', (_) async {
    // How the settings screen clears a key: the user empties the field and
    // saves. Leaving the old credential behind would be a real leak.
    await store.write(testId, 'something');
    expect(await store.write(testId, '  '), isTrue);
    expect(await store.read(testId), '');
  });

  testWidgets('reading an absent key returns empty, not an error', (_) async {
    await store.delete(testId);
    expect(await store.read(testId), '');
  });

  testWidgets('entries are namespaced per provider', (_) async {
    // Four providers share one store; a collision would hand one provider's
    // key to another and produce a baffling 401.
    expect(SecureKeyStore.entryName('anthropic'),
        isNot(SecureKeyStore.entryName('openai')));
  });
}
