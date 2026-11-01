/// The Stack screen's cards, an import source and a tab's app bar fit a phone
/// at large accessibility text sizes (audit U-7). Built as `accessibility_test` does the dashboard's.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/import_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';
import 'package:sats_stack/features/stack/widgets/dca_simulator.dart';
import 'package:sats_stack/features/stack/widgets/stack_goal_card.dart';
import 'package:sats_stack/features/stack/widgets/stack_hero.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/screens/import/import_file_screen.dart';
import 'package:sats_stack/shared/theme/app_theme.dart';
import 'package:sats_stack/shared/widgets/btc_price_chip.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required double textScale,
  double width = 360,
}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

class _NoKeys extends SecureKeyStore {
  const _NoKeys();
  @override
  Future<String> read(String providerId) async => '';
  @override
  Future<bool> write(String providerId, String value) async => true;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  for (final scale in const [1.0, 3.0]) {
    testWidgets('an import source card fits at ${scale}x', (tester) async {
      await tester.runAsync(() async {
        app.db = AppDatabase.forTesting(NativeDatabase.memory());
        app.ollamaService = OllamaService(app.db, keyStore: const _NoKeys());
        app.importService = ImportService(app.db, app.ollamaService);
        app.aiEnabledNotifier = ValueNotifier(false);
        await app.importService.createSource(
          name: 'Joint current account at the building society',
          type: 'bank',
          currency: 'GBP',
        );
      });
      tester.view.physicalSize = const Size(360, 1400);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light(), home: const ImportFileScreen()),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.widgetWithText(FilledButton, 'Import'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() => app.db.close());
    });
  }

  for (final scale in const [1.0, 3.0]) {
    testWidgets('the transactions app bar fits at ${scale}x', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final prices =
          BtcPriceService(db)
            ..priceNotifier.value = 81234.56
            ..lastFetchedAt = DateTime.now();
      app.currencyNotifier = ValueNotifier('USD');
      app.showBtcPriceNotifier = ValueNotifier(true);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      // The Transactions tab's bar: the chip and three icons.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            appBar: AppBar(
              title: const FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('Transactions'),
              ),
              centerTitle: false,
              actions: [
                BtcPriceChip(service: prices),
                const SizedBox(width: 4),
                for (final icon in const [
                  Icons.filter_list_outlined,
                  Icons.account_balance_wallet_outlined,
                  Icons.upload_file_outlined,
                ])
                  IconButton(
                    icon: Icon(icon),
                    onPressed: () {},
                    padding: const EdgeInsets.all(8),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final scale in const [1.0, 2.0, 3.0]) {
    testWidgets('the stack hero fits at ${scale}x', (tester) async {
      await _pump(
        tester,
        const StackHero(
          totalSats: 123456789,
          monthSats: -2345678,
          currency: 'USD',
          btcPrice: 81234.56,
        ),
        textScale: scale,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the stack goal card fits at ${scale}x', (tester) async {
      await _pump(
        tester,
        StackGoalCard(
          totalSats: 12345678,
          goalSats: 100000000,
          avgMonthlySats: 234567,
          btcPrice: 81234.56,
          currency: 'USD',
          onEdit: () {},
        ),
        textScale: scale,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the DCA simulator fits at ${scale}x', (tester) async {
      final ctrl = TextEditingController(text: '250');
      addTearDown(ctrl.dispose);
      await _pump(
        tester,
        DcaSimulator(
          btcPrice: 81234.56,
          controller: ctrl,
          years: 5,
          onYearsChanged: (_) {},
          currency: 'USD',
        ),
        textScale: scale,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
