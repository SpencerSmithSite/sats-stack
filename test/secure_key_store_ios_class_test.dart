/// Keys stored under the old iOS keychain class are still found after
/// `flutter_secure_storage` 10 (audit P-4).
///
/// Keys moved from `first_unlock` to `first_unlock_this_device`, relying on
/// the 9.x iOS plugin's reads ignoring the class. From 10.0 the class is in
/// every query, so a key not yet moved read as absent, and writing it again
/// collided with the old item, which the keychain matches on account alone.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';

/// The iOS keychain as the plugin sees it: reads and adds name a class,
/// delete matches whatever the class, and an add collides on account.
class _Keychain {
  final items = <String, ({String value, String accessibility})>{};
  var failNextAdd = false;

  Future<Object?> handle(MethodCall call) async {
    final args = Map<String, Object?>.from(call.arguments as Map);
    final key = args['key'] as String?;
    final options = Map<String, Object?>.from(args['options'] as Map);
    final accessibility = options['accessibility'] as String;
    final match = items[key];
    final matches = match != null && match.accessibility == accessibility;
    switch (call.method) {
      case 'read':
        return matches ? match.value : null;
      case 'containsKey':
        return matches;
      case 'delete':
        items.remove(key);
        return null;
      case 'write':
        final value = args['value'] as String;
        if (matches) {
          items[key!] = (value: value, accessibility: accessibility);
          return null;
        }
        if (failNextAdd) {
          failNextAdd = false;
          throw PlatformException(code: '-34018', message: 'add failed');
        }
        if (match != null) {
          throw PlatformException(code: '-25299', message: 'duplicate item');
        }
        items[key!] = (value: value, accessibility: accessibility);
        return null;
    }
    throw UnimplementedError(call.method);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const store = SecureKeyStore();
  final entry = SecureKeyStore.entryName('anthropic');

  late _Keychain keychain;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    keychain = _Keychain();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, keychain.handle);
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a key under the old class is read, and moved to this device', () async {
    keychain.items[entry] = (value: 'sk-old', accessibility: 'first_unlock');
    expect(await store.read('anthropic'), 'sk-old');
    expect(keychain.items[entry], (
      value: 'sk-old',
      accessibility: 'first_unlock_this_device',
    ));
    // And found directly from then on.
    expect(await store.read('anthropic'), 'sk-old');
  });

  test('a key under the old class can be written over', () async {
    keychain.items[entry] = (value: 'sk-old', accessibility: 'first_unlock');
    expect(await store.write('anthropic', 'sk-new'), isTrue);
    expect(keychain.items[entry], (
      value: 'sk-new',
      accessibility: 'first_unlock_this_device',
    ));
  });

  test('a failed move puts the old key back', () async {
    keychain.items[entry] = (value: 'sk-old', accessibility: 'first_unlock');
    keychain.failNextAdd = true;
    expect(await store.read('anthropic'), 'sk-old');
    expect(keychain.items[entry], (
      value: 'sk-old',
      accessibility: 'first_unlock',
    ));
  });

  test('other entries are moved the same way', () async {
    keychain.items['bitcoin_rpc_password'] = (
      value: 'hunter2',
      accessibility: 'first_unlock',
    );
    expect(await store.readEntry('bitcoin_rpc_password'), 'hunter2');
    expect(
      keychain.items['bitcoin_rpc_password']!.accessibility,
      'first_unlock_this_device',
    );
  });
}
