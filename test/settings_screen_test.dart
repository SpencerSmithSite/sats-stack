/// What the Settings screen does, section by section — written before it was
/// split into one widget per section (TODO item 14), so the split can be shown
/// to change nothing. No test covered the screen before.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/ai_provider.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/category_service.dart';
import 'package:sats_stack/core/services/import_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';
import 'package:sats_stack/core/services/xpub_service.dart';
import 'package:sats_stack/features/settings/settings_screen.dart';
import 'package:sats_stack/features/settings/widgets/categories_sheet.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/constants/app_constants.dart';
import 'package:sats_stack/shared/theme/app_theme.dart';
import 'package:sats_stack/shared/widgets/ai_privacy_disclosure.dart';

class _MemoryKeyStore extends SecureKeyStore {
  _MemoryKeyStore();
  final keys = <String, String>{};
  @override
  Future<String> read(String providerId) async => keys[providerId] ?? '';
  @override
  Future<bool> write(String providerId, String value) async {
    keys[providerId] = value;
    return true;
  }

  @override
  Future<void> delete(String providerId) async => keys.remove(providerId);

  @override
  Future<String> readEntry(String entry) async => keys[entry] ?? '';

  @override
  Future<bool> writeEntry(String entry, String value) => write(entry, value);

  @override
  Future<void> deleteEntry(String entry) => delete(entry);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late _MemoryKeyStore keys;

  Future<void> services() async {
    app.db = AppDatabase.forTesting(NativeDatabase.memory());
    keys = _MemoryKeyStore();
    app.categoryService = CategoryService(app.db);
    app.btcPriceService = BtcPriceService(app.db);
    app.xpubService = XpubService(app.db);
    app.ollamaService = OllamaService(app.db, keyStore: keys);
    await app.ollamaService.loadSettings();
    app.importService = ImportService(app.db, app.ollamaService);
    app.themeModeNotifier = ValueNotifier(ThemeMode.dark);
    app.currencyNotifier = ValueNotifier('USD');
    app.showBtcPriceNotifier = ValueNotifier(true);
    app.inflationRateNotifier = ValueNotifier(3.5);
    app.aiEnabledNotifier = ValueNotifier(false);
    app.onboardingCompleteNotifier = ValueNotifier(true);
  }

  Future<String?> setting(WidgetTester tester, String key) async =>
      (await tester.runAsync(
        () =>
            (app.db.select(app.db.appSettings)
              ..where((s) => s.key.equals(key))).getSingleOrNull(),
      ))?.value;

  /// Lets real I/O — drift, the probe of a local AI server — finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> open(WidgetTester tester, String section) async {
    await tester.runAsync(services);
    tester.view.physicalSize = const Size(430, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        GoRoute(
          path: '/onboarding',
          builder:
              (_, state) => Text(
                'ONBOARD ${state.uri.queryParameters['revisit'] ?? 'first'}',
              ),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    );
    await settle(tester);
    await tester.tap(find.text(section));
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => app.db.close());
  }

  group('General', () {
    testWidgets('theme, currency and the price chip are kept', (tester) async {
      await open(tester, 'General');

      await tester.tap(find.text('Light'));
      await settle(tester);
      expect(app.themeModeNotifier.value, ThemeMode.light);
      expect(await setting(tester, AppConstants.settingThemeMode), 'light');

      await tester.tap(find.widgetWithText(ChoiceChip, 'GBP'));
      await settle(tester);
      expect(app.currencyNotifier.value, 'GBP');
      expect(await setting(tester, AppConstants.settingCurrency), 'GBP');
      expect(find.text('£ GBP'), findsOneWidget);

      await tester.tap(find.text('Show BTC price'));
      await settle(tester);
      expect(app.showBtcPriceNotifier.value, isFalse);
      expect(await setting(tester, AppConstants.settingShowBtcPrice), 'false');
      await close(tester);
    });

    testWidgets('the inflation rate is checked, then saved', (tester) async {
      await open(tester, 'General');
      final field = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.suffixText == '%',
      );

      await tester.enterText(field, '150');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);
      expect(find.text('Please enter a value between 0 and 100'), findsOne);
      expect(app.inflationRateNotifier.value, 3.5);

      await tester.enterText(field, '4.2');
      await tester.pump();
      expect(find.text('Please enter a value between 0 and 100'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);
      expect(app.inflationRateNotifier.value, 4.2);
      expect(await setting(tester, AppConstants.settingInflationRate), '4.2');
      expect(find.text('Inflation rate saved'), findsOneWidget);
      await close(tester);
    });

    testWidgets('Categories opens the categories sheet', (tester) async {
      await open(tester, 'General');
      await tester.tap(find.text('Categories'));
      await settle(tester);
      expect(find.byType(CategoriesSheet), findsOneWidget);
      await close(tester);
    });
  });

  group('Servers', () {
    testWidgets('an Ollama URL is saved as it will be used', (tester) async {
      await open(tester, 'Servers');
      expect(find.text('Ollama base URL'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Ollama base URL'),
        '192.168.1.5:11434',
      );
      await tester.pump();
      expect(
        find.text(
          'Sent over your local network to 192.168.1.5, and no further.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save').first);
      await settle(tester);
      expect(app.ollamaService.baseUrl, 'http://192.168.1.5:11434');
      expect(find.text('http://192.168.1.5:11434'), findsOneWidget);
      expect(find.text('Ollama settings saved'), findsOneWidget);
      // Its own network: no off-device disclosure.
      expect(find.byType(AiPrivacyDisclosure), findsNothing);
      await close(tester);
    });

    testWidgets('a hosted provider: chosen, disclosed, its key saved', (
      tester,
    ) async {
      await open(tester, 'Servers');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Claude'));
      await settle(tester);

      expect(app.ollamaService.activeProvider, AiProvider.claude);
      expect(find.text('Ollama base URL'), findsNothing);
      expect(find.byType(AiPrivacyDisclosure), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Claude API key'),
        'sk-ant-test',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save').first);
      await settle(tester);
      expect(keys.keys['anthropic'], 'sk-ant-test');
      expect(find.text('Claude settings saved'), findsOneWidget);
      await close(tester);
    });

    testWidgets('a Mempool server is saved, and the banner follows', (
      tester,
    ) async {
      await open(tester, 'Servers');
      expect(find.text('Using public servers'), findsOneWidget);
      final field = find.widgetWithText(TextField, 'Mempool / Esplora server');

      await tester.enterText(field, 'myserver.lan:3006/api');
      await tester.pump();
      // The banner tells what is in use, not what is typed (audit U-2).
      expect(find.text('Using public servers'), findsOneWidget);
      expect(find.textContaining('Not saved yet'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await settle(tester);
      expect(app.xpubService.esploraBaseUrl, 'https://myserver.lan:3006/api');
      expect(find.text('Bitcoin server settings saved'), findsOneWidget);
      expect(find.text('All data routed through your server'), findsOneWidget);
      expect(find.textContaining('Not saved yet'), findsNothing);
      // Snackbars queue: let this one go before looking for the next.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tester.enterText(field, 'ftp://nope');
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await settle(tester);
      expect(find.textContaining("isn't a usable server URL"), findsOneWidget);
      expect(app.xpubService.esploraBaseUrl, AppConstants.mempoolBaseUrl);
      await close(tester);
    });

    testWidgets('the wallet history choice is there', (tester) async {
      await open(tester, 'Servers');
      expect(find.text('Wallet history from'), findsOneWidget);
      await close(tester);
    });
  });

  // The screen used to hold every field's controller itself, so collapsing a
  // section and opening it again kept what was typed and what a test said.
  testWidgets('a section keeps what was typed when collapsed', (tester) async {
    await open(tester, 'Servers');
    final field = find.widgetWithText(TextField, 'Mempool / Esplora server');
    await tester.enterText(field, 'half-typed.lan');
    await tester.tap(find.text('Servers'));
    await settle(tester);
    await tester.tap(find.text('Servers'));
    await settle(tester);
    expect(find.text('half-typed.lan'), findsOneWidget);
    await close(tester);
  });

  testWidgets('Data offers export and import', (tester) async {
    await open(tester, 'Data');
    expect(find.text('Export database'), findsOneWidget);
    expect(find.text('Import database'), findsOneWidget);
    await close(tester);
  });

  group('About', () {
    testWidgets('names the app and lists the licences', (tester) async {
      await open(tester, 'About');
      expect(find.textContaining('Local-first Bitcoin budgeting'), findsOne);
      expect(find.text('Licences'), findsOneWidget);
      await close(tester);
    });

    testWidgets('Show onboarding goes back to it', (tester) async {
      await open(tester, 'About');
      await tester.tap(find.text('Show onboarding'));
      await settle(tester);
      expect(app.onboardingCompleteNotifier.value, isFalse);
      // As a revisit, so the setup in force is kept (audit U-1).
      expect(find.text('ONBOARD 1'), findsOneWidget);
      await close(tester);
    });
  });

  group('Danger Zone', () {
    Future<void> addRow(WidgetTester tester) => tester.runAsync(() async {
      final wallet = (await app.db.select(app.db.wallets).get()).first.id;
      await app.db
          .into(app.db.transactions)
          .insert(
            TransactionsCompanion.insert(
              walletId: wallet,
              date: DateTime(2026, 3, 1),
              description: 'Rent',
              amountSats: 0,
              amountFiat: -1200,
              fiatCurrency: 'USD',
              source: 'manual',
              dedupHash: 'rent',
            ),
          );
    });

    Future<int> rows(WidgetTester tester) async =>
        (await tester.runAsync(
          () => app.db.select(app.db.transactions).get(),
        ))!.length;

    testWidgets('cancelling a reset keeps everything', (tester) async {
      await open(tester, 'Danger Zone');
      await addRow(tester);
      await tester.tap(find.text('Reset all data'));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(await rows(tester), 1);
      expect(app.onboardingCompleteNotifier.value, isTrue);
      await close(tester);
    });

    testWidgets('a reset empties the data and restores the defaults', (
      tester,
    ) async {
      await open(tester, 'Danger Zone');
      await addRow(tester);
      app.currencyNotifier.value = 'GBP';
      app.themeModeNotifier.value = ThemeMode.light;
      app.showBtcPriceNotifier.value = false;
      await keys.write('anthropic', 'sk-ant-test');

      await tester.tap(find.text('Reset all data'));
      await settle(tester);
      await tester.tap(find.text('Delete Everything'));
      await settle(tester);

      expect(await rows(tester), 0);
      expect(app.currencyNotifier.value, 'USD');
      expect(app.themeModeNotifier.value, ThemeMode.dark);
      expect(app.showBtcPriceNotifier.value, isTrue);
      expect(app.onboardingCompleteNotifier.value, isFalse);
      expect(keys.keys['anthropic'] ?? '', isEmpty);
      // A genuine first run: everything was deleted.
      expect(find.text('ONBOARD first'), findsOneWidget);
      await close(tester);
    });
  });
}
