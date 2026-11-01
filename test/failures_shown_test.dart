/// A save, delete or reset that fails says so (audit U-6).
///
/// Each was a try with no catch, or an unawaited call: a failure became an
/// unhandled error, the spinner stopped (or never did), and nothing was
/// shown — so a failed edit looked like one that had worked.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/category_service.dart';
import 'package:sats_stack/core/services/transaction_service.dart';
import 'package:sats_stack/features/settings/widgets/danger_zone_section.dart';
import 'package:sats_stack/features/transactions/widgets/transaction_edit_sheet.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/theme/app_theme.dart';

class _Failing extends TransactionService {
  _Failing(super.db);
  @override
  Future<void> update(TransactionsCompanion companion) async =>
      throw StateError('disk full');
  @override
  Future<void> deleteById(int id) async => throw StateError('disk full');
}

class _FailingReset extends AppDatabase {
  _FailingReset() : super.forTesting(NativeDatabase.memory());
  @override
  Future<void> resetAndReseed() async => throw StateError('database locked');
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
    }
  }

  group('the edit sheet', () {
    late Transaction tx;
    setUp(() async {
      app.db = AppDatabase.forTesting(NativeDatabase.memory());
      app.categoryService = CategoryService(app.db);
      app.btcPriceService = BtcPriceService(app.db);
      app.transactionService = _Failing(app.db);
      final wallet = (await app.db.select(app.db.wallets).getSingle()).id;
      final id = await app.db
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
      tx =
          await (app.db.select(app.db.transactions)
            ..where((t) => t.id.equals(id))).getSingle();
    });
    tearDown(() => app.db.close());

    testWidgets('a failed save is shown on the sheet', (tester) async {
      await pump(tester, TransactionEditSheet.forExisting(tx));
      await settle(tester);
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.textContaining('Could not save'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget); // still open, and usable
    });

    testWidgets('a failed delete is shown on the sheet', (tester) async {
      await pump(tester, TransactionEditSheet.forExisting(tx));
      await settle(tester);
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await settle(tester);
      expect(find.textContaining('Could not delete'), findsOneWidget);
    });
  });

  testWidgets('a reset that fails says it did not finish', (tester) async {
    app.db = _FailingReset();
    await pump(tester, const DangerZoneSection());
    await tester.tap(find.text('Reset all data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Everything'));
    await settle(tester);
    expect(find.text('Reset did not finish'), findsOneWidget);
    expect(find.textContaining('database locked'), findsOneWidget);
    await tester.runAsync(() => app.db.close());
  });
}
