/// What the app says about where wallet data goes matches what it does
/// (audit B-6, B-9, U-3; U-2 is in `settings_screen_test`).
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/bitcoin_data_source.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';
import 'package:sats_stack/core/services/xpub_service.dart';
import 'package:sats_stack/features/onboarding/onboarding_screen.dart';
import 'package:sats_stack/features/onboarding/pages/bitcoin_server_page.dart';
import 'package:sats_stack/features/transactions/widgets/add_wallet_sheet.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/theme/app_theme.dart';
import 'package:sats_stack/shared/utils/url_utils.dart';

class _NoKeys extends SecureKeyStore {
  const _NoKeys();
  @override
  Future<String> read(String providerId) async => '';
  @override
  Future<bool> write(String providerId, String value) async => true;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('one test for the default server', () {
    test('blank, unusable and mempool.space addresses are the default', () {
      for (final url in [
        null,
        '',
        '   ',
        'ftp://nope',
        'mempool.space',
        'https://mempool.space/api',
        'https://MEMPOOL.space/api/',
        'https://eu.mempool.space/api',
      ]) {
        expect(isDefaultMempoolServer(url), isTrue, reason: url);
      }
    });

    test('anything else is the user own choice', () {
      for (final url in [
        'https://mempool.emzy.de/api',
        'myserver.lan:3006/api',
        'http://192.168.1.5:3006/api',
        'https://fakemempool.space',
        'https://mempool.space.example.com',
      ]) {
        expect(isDefaultMempoolServer(url), isFalse, reason: url);
      }
    });
  });

  group('the Add Wallet notice', () {
    late AppDatabase db;
    late XpubService xpub;
    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      xpub = XpubService(db);
    });
    tearDown(() => db.close());

    test('with mempool.space, it says the addresses go there', () {
      final n = walletPrivacyNotice(xpub);
      expect(n.addressesStayHome, isFalse);
      expect(n.text, contains('looked up on mempool.space'));
      expect(n.text, contains('belong together'));
      expect(n.text, contains('xpub itself stays on this device'));
    });

    test('with another server, it names that server, not "your own"', () async {
      await xpub.saveSettings(url: 'https://mempool.emzy.de/api');
      final n = walletPrivacyNotice(xpub);
      expect(n.text, contains('the server you set (mempool.emzy.de)'));
      expect(n.text, isNot(contains('No data is sent to public servers')));
    });

    test(
      'with Electrum, it names the Electrum server and the price source',
      () async {
        await xpub.electrum.saveSettings(
          host: 'node.lan',
          port: 50002,
          ssl: true,
        );
        await xpub.saveDataSource(BitcoinDataSource.electrum);
        final n = walletPrivacyNotice(xpub);
        expect(n.addressesStayHome, isTrue);
        expect(n.text, contains('Electrum server (node.lan)'));
        expect(
          n.text,
          contains('Prices for their dates come from mempool.space'),
        );
      },
    );
  });

  group('onboarding', () {
    testWidgets('an unusable server address stops at its page', (tester) async {
      await tester.runAsync(() async {
        app.db = AppDatabase.forTesting(NativeDatabase.memory());
        app.ollamaService = OllamaService(app.db, keyStore: const _NoKeys());
        await app.ollamaService.loadSettings();
        app.xpubService = XpubService(app.db);
        app.btcPriceService = BtcPriceService(app.db);
        app.currencyNotifier = ValueNotifier('USD');
        app.themeModeNotifier = ValueNotifier(ThemeMode.dark);
        app.onboardingCompleteNotifier = ValueNotifier(false);
      });
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark(), home: const OnboardingScreen()),
      );
      await tester.pumpAndSettle();
      while (find.byType(BitcoinServerPage).evaluate().isEmpty) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }

      await tester.enterText(find.byType(TextField), 'ftp://my-node');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.textContaining("isn't a usable server address"), findsOne);
      expect(find.byType(BitcoinServerPage), findsOneWidget);

      // Corrected, it moves on.
      await tester.enterText(find.byType(TextField), 'my-node.lan:3006/api');
      // The error fades out rather than vanishing.
      await tester.pumpAndSettle();
      expect(
        find.textContaining("isn't a usable server address"),
        findsNothing,
      );
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.byType(BitcoinServerPage), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() => app.db.close());
    });
  });
}
