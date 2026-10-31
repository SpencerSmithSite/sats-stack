/// Going back through onboarding from Settings keeps the AI provider in use
/// (audit U-1).
///
/// About cleared the onboarding flag and then navigated, and the onboarding
/// screen read that same flag to tell a revisit from a first run — so it
/// always saw a first run, and the provider check replaced the user's choice
/// (Claude, a remote Ollama) with a suggestion that Get Started then saved.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/ai_provider.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';
import 'package:sats_stack/core/services/xpub_service.dart';
import 'package:sats_stack/features/onboarding/onboarding_screen.dart';
import 'package:sats_stack/features/onboarding/pages/ai_provider_page.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/theme/app_theme.dart';

class _NoKeys extends SecureKeyStore {
  const _NoKeys();
  @override
  Future<String> read(String providerId) async => '';
  @override
  Future<bool> write(String providerId, String value) async => true;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<AiProvider> providerOnAiPage(
    WidgetTester tester, {
    required bool revisit,
  }) async {
    await tester.runAsync(() async {
      app.db = AppDatabase.forTesting(NativeDatabase.memory());
      app.ollamaService = OllamaService(app.db, keyStore: const _NoKeys());
      await app.ollamaService.loadSettings();
      await app.ollamaService.setActiveProvider(AiProvider.claude);
      app.xpubService = XpubService(app.db);
      app.btcPriceService = BtcPriceService(app.db);
      app.currencyNotifier = ValueNotifier('USD');
      app.themeModeNotifier = ValueNotifier(ThemeMode.dark);
      // As About leaves it: cleared before the screen opens.
      app.onboardingCompleteNotifier = ValueNotifier(false);
    });
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: OnboardingScreen(revisit: revisit),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }
    // Through to the AI provider page.
    while (find.byType(AiProviderPage).evaluate().isEmpty) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    final selected =
        tester.widget<AiProviderPage>(find.byType(AiProviderPage)).selected;

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => app.db.close());
    return selected;
  }

  testWidgets('a revisit keeps the provider in use', (tester) async {
    expect(await providerOnAiPage(tester, revisit: true), AiProvider.claude);
  });

  testWidgets('a first run still starts from a suggestion', (tester) async {
    expect(
      await providerOnAiPage(tester, revisit: false),
      isNot(AiProvider.claude),
    );
  });
}
