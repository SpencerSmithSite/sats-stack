/// The Dashboard's insight card names who a tap would send the month to — and
/// keeps naming the right one when the AI provider changes in Settings.
///
/// The Dashboard tab lives for the whole session, and the recipient was
/// worked out once, when it was first built. Switching from a local Ollama to
/// Claude left the card saying nothing about where the figures would go, while
/// a tap sent them to Anthropic.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/ai_provider.dart';
import 'package:sats_stack/core/models/fx_rates.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/category_service.dart';
import 'package:sats_stack/core/services/dashboard_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';
import 'package:sats_stack/features/dashboard/dashboard_screen.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/theme/app_theme.dart';

class _NoKeyStore extends SecureKeyStore {
  const _NoKeyStore();
  @override
  Future<String> read(String providerId) async => '';
  @override
  Future<bool> write(String providerId, String value) async => true;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('switching to a hosted provider updates the recipient line', (
    tester,
  ) async {
    await tester.runAsync(() async {
      app.db = AppDatabase.forTesting(NativeDatabase.memory());
      app.categoryService = CategoryService(app.db);
      app.btcPriceService = BtcPriceService(app.db);
      app.currencyNotifier = ValueNotifier('USD');
      app.inflationRateNotifier = ValueNotifier(3.5);
      app.showBtcPriceNotifier = ValueNotifier(false);
      app.aiEnabledNotifier = ValueNotifier(true);
      app.dashboardService = DashboardService(
        app.db,
        rates: () => const FxRates(display: 'USD', btcPrices: {}),
      );
      app.ollamaService = OllamaService(app.db, keyStore: const _NoKeyStore());
      await app.ollamaService.setActiveProvider(AiProvider.ollama);
    });

    tester.view.physicalSize = const Size(430, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const DashboardScreen()),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final recipientLine = find.textContaining('Anthropic');
    expect(recipientLine, findsNothing, reason: 'Ollama on localhost');

    await tester.runAsync(
      () => app.ollamaService.setActiveProvider(AiProvider.claude),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(recipientLine, findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => app.db.close());
  }, timeout: const Timeout(Duration(minutes: 1)));
}
