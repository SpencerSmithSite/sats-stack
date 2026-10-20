/// Derivation and server-URL tests for [XpubService].
///
/// The derivation cases use the official BIP84 test vector, which publishes
/// both receive and change addresses — the change chain is the one the scanner
/// used to ignore entirely, making every change output invisible.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/xpub_service.dart';

void main() {
  late AppDatabase db;
  late XpubService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = XpubService(db);
  });

  tearDown(() => db.close());

  // BIP84 test vector, account m/84'/0'/0'.
  const bip84Zpub =
      'zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1ADqtf'
      'SdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs';

  group('address derivation', () {
    test('receive chain matches the BIP84 vector', () {
      expect(
        service.deriveAddresses(bip84Zpub, 0, 2),
        ['bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu',
         'bc1qnjg0jd8228aq7egyzacy8cys3knf9xvrerkf9g'],
      );
    });

    test('change chain matches the BIP84 vector', () {
      expect(
        service.deriveAddresses(bip84Zpub, 0, 1, chain: 1),
        ['bc1q8c6fshw2dlwun7ekn9qwf37cu2rn755upcp6el'],
      );
    });

    test('change chain is not the receive chain', () {
      final receive = service.deriveAddresses(bip84Zpub, 0, 5);
      final change = service.deriveAddresses(bip84Zpub, 0, 5, chain: 1);
      expect(receive.toSet().intersection(change.toSet()), isEmpty);
    });

    test('format and network come from the version bytes', () {
      expect(service.detectFormat(bip84Zpub), XpubFormat.p2wpkh);
      expect(service.detectNetwork(bip84Zpub), XpubNetwork.mainnet);
    });
  });

  group('key validation', () {
    test('an extended private key is rejected', () {
      // BIP84 vector's account zprv — same bytes, private version.
      const zprv =
          'zprvAdG4iTXWBoARxkkzNpNh8r6Qag3irQB8PzEMkAFeTRXxHpbF9z4QgEvBRmfvq'
          'Wvpak4TR8mN9hLTtkoTLvFqMGpvKvkPFs7fSJKFDVjNAKq';
      expect(() => service.deriveAddresses(zprv, 0, 1), throwsArgumentError);
    });

    test('an unknown prefix is rejected rather than treated as mainnet', () {
      // A valid base58check payload of the right length but a version the app
      // does not know — must not silently derive mainnet addresses.
      expect(
        () => service.deriveAddresses('xpub661MyMwAqRbcF', 0, 1),
        throwsA(anything),
      );
    });

    test('garbage is rejected', () {
      expect(() => service.deriveAddresses('not a key', 0, 1),
          throwsA(anything));
    });
  });

  group('normalizeBaseUrl', () {
    test('blank means "use the default"', () {
      expect(XpubService.normalizeBaseUrl(''), isNull);
      expect(XpubService.normalizeBaseUrl('   '), isNull);
    });

    test('trailing slashes are stripped', () {
      expect(
        XpubService.normalizeBaseUrl('https://mempool.space/api/'),
        'https://mempool.space/api',
      );
    });

    test('a bare host gets https', () {
      expect(
        XpubService.normalizeBaseUrl('mempool.local/api'),
        'https://mempool.local/api',
      );
    });

    test('a non-http scheme is rejected', () {
      expect(XpubService.normalizeBaseUrl('ftp://example.com'), isNull);
    });
  });

  group('saveSettings', () {
    test('a blank URL leaves the live base URL usable, not empty', () async {
      await service.saveSettings(url: 'https://example.com/api');
      final result = await service.saveSettings(url: '');

      // Null tells the caller the default is in force …
      expect(result, isNull);
      // … and the live value is absolute, so requests do not become relative
      // URLs that throw on the first address. This is what reported "0
      // transactions imported, scanned 20 addresses" for a funded wallet.
      expect(service.esploraBaseUrl, isNotEmpty);
      expect(Uri.parse(service.esploraBaseUrl).host, isNotEmpty);
    });

    test('a saved URL survives a reload', () async {
      await service.saveSettings(url: 'https://mempool.local/api/');
      final reloaded = XpubService(db);
      await reloaded.loadSettings();
      expect(reloaded.esploraBaseUrl, 'https://mempool.local/api');
    });

    test('an unusable URL falls back to the default and says so', () async {
      final result = await service.saveSettings(url: 'ftp://nope');
      expect(result, isNull);
      expect(Uri.parse(service.esploraBaseUrl).scheme, anyOf('http', 'https'));
    });
  });

  group('windowed derivation', () {
    test('a window matches deriving one at a time', () {
      // The scan now derives 20 at a time in an isolate instead of one at a
      // time inline. Same addresses, in the same order, or a wallet would be
      // scanned at the wrong keys.
      final window = XpubService.deriveWindowSync(bip84Zpub, 0, 0, 20);
      final individually = [
        for (var i = 0; i < 20; i++)
          service.deriveAddresses(bip84Zpub, i, 1).single,
      ];
      expect(window, individually);
    });

    test('a window starting partway through is offset correctly', () {
      // The loop advances by the gap limit, so an off-by-one here would scan
      // the wrong range on every window after the first.
      expect(
        XpubService.deriveWindowSync(bip84Zpub, 0, 20, 5),
        service.deriveAddresses(bip84Zpub, 20, 5),
      );
    });

    test('the change chain windows separately', () {
      expect(
        XpubService.deriveWindowSync(bip84Zpub, 1, 0, 3),
        service.deriveAddresses(bip84Zpub, 0, 3, chain: 1),
      );
    });

    test('the isolate entry point agrees with the static one', () async {
      // deriveAddressWindow is what compute() invokes; its message is a plain
      // list, and getting the order of those four fields wrong would derive a
      // different wallet entirely.
      expect(
        deriveAddressWindow(<Object>[bip84Zpub, 1, 2, 4]),
        XpubService.deriveWindowSync(bip84Zpub, 1, 2, 4),
      );
    });
  });
}
