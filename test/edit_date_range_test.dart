/// Editing a row dated outside the picker's usual range opens the picker on
/// that date (audit U-11).
///
/// The range was Bitcoin's first block to tomorrow, with the row's date as
/// the initial one: a pre-2009 fiat row or a future-dated bank row tripped
/// the picker's assertion.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/category_service.dart';
import 'package:sats_stack/core/services/transaction_service.dart';
import 'package:sats_stack/features/transactions/widgets/transaction_edit_sheet.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/theme/app_theme.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<Transaction> row(DateTime date) async {
    final wallet = (await app.db.select(app.db.wallets).getSingle()).id;
    final id = await app.db
        .into(app.db.transactions)
        .insert(
          TransactionsCompanion.insert(
            walletId: wallet,
            date: date,
            description: 'Old rent',
            amountSats: 0,
            amountFiat: -400,
            fiatCurrency: 'USD',
            source: 'csv',
            dedupHash: 'u11-$date',
          ),
        );
    return (app.db.select(app.db.transactions)
      ..where((t) => t.id.equals(id))).getSingle();
  }

  for (final date in [
    DateTime(2005, 6, 15),
    DateTime.now().add(const Duration(days: 40)),
  ]) {
    testWidgets('a row dated ${date.year}-${date.month} opens the picker', (
      tester,
    ) async {
      late Transaction tx;
      await tester.runAsync(() async {
        app.db = AppDatabase.forTesting(NativeDatabase.memory());
        app.categoryService = CategoryService(app.db);
        app.btcPriceService = BtcPriceService(app.db);
        app.transactionService = TransactionService(app.db);
        tx = await row(date);
      });
      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: TransactionEditSheet.forExisting(tx),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.calendar_today_outlined));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DatePickerDialog), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => app.db.close());
    });
  }
}
