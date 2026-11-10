/// The sheet where money is entered by hand (audit T-1: it had no tests at
/// all).
///
/// Pins what a row is saved as: the sign from Expense or Income, the amount
/// in the active currency or in sats with the other side converted at the
/// live price, the category, notes, and a repeating series.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/category_service.dart';
import 'package:sats_stack/core/services/transaction_service.dart';
import 'package:sats_stack/core/services/wallet_service.dart';
import 'package:sats_stack/features/transactions/widgets/add_transaction_sheet.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/theme/app_theme.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late BtcPriceService prices;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
    }
  }

  /// Opens the sheet as the app does, from a button, so Save's pop closes it.
  Future<void> open(WidgetTester tester, {double? price = 50000}) async {
    await tester.runAsync(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      prices = BtcPriceService(db)..priceNotifier.value = price;
    });
    // A pound user: the row must say GBP, not a hardcoded USD.
    app.currencyNotifier = ValueNotifier('GBP');
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder:
                            (_) => AddTransactionSheet(
                              transactionService: TransactionService(db),
                              categoryService: CategoryService(db),
                              walletService: WalletService(db),
                              btcPriceService: prices,
                            ),
                      ),
                  child: const Text('Open'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'on opening');
  }

  Future<List<Transaction>> rows(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.transactions).get()))!;

  Future<void> fill(WidgetTester tester, String amount, String what) async {
    await tester.enterText(find.widgetWithText(TextFormField, '0.00'), amount);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description'),
      what,
    );
    await tester.pump();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Save Transaction'));
    await tester.tap(find.text('Save Transaction'));
    await settle(tester);
  }

  Future<void> tidy(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  }

  testWidgets('an empty form says what is missing and saves nothing', (
    tester,
  ) async {
    await open(tester);
    await save(tester);
    expect(find.text('Enter amount'), findsOneWidget);
    expect(find.text('Enter a description'), findsOneWidget);
    expect(await rows(tester), isEmpty);
    await tidy(tester);
  });

  testWidgets('an expense in pounds: negative, in GBP, sats at the price', (
    tester,
  ) async {
    await open(tester);
    await fill(tester, '12.50', 'Coffee');
    // £12.50 at £50,000: 25,000 sats.
    expect(find.text('≈ 25,000 sats'), findsOneWidget);
    await save(tester);

    final row = (await rows(tester)).single;
    expect(row.description, 'Coffee');
    expect(row.amountFiat, -12.5);
    expect(row.fiatCurrency, 'GBP');
    expect(row.amountSats, -25000);
    expect(row.source, 'manual');
    // The first category that is not Income is chosen for an expense.
    expect(row.category, isNot('Income'));
    expect(row.category, isNotNull);
    expect(row.recurringPeriod, isNull);
    // Saved, so the sheet closed.
    expect(find.byType(AddTransactionSheet), findsNothing);
    await tidy(tester);
  });

  testWidgets('income in sats: positive, pounds worked out', (tester) async {
    await open(tester);
    await tester.tap(find.text('Income'));
    // The currency chip switches the amount to sats.
    await tester.tap(find.text('GBP'));
    await tester.pump();
    expect(find.text('SATS'), findsOneWidget);
    await fill(tester, '21000', 'Sold a lamp');
    await save(tester);

    final row = (await rows(tester)).single;
    expect(row.amountSats, 21000);
    expect(row.amountFiat, closeTo(10.5, 1e-9));
    expect(row.fiatCurrency, 'GBP');
    await tidy(tester);
  });

  testWidgets('with no price, the sats are not invented', (tester) async {
    await open(tester, price: null);
    await fill(tester, '12.50', 'Coffee');
    expect(find.text('BTC price unavailable'), findsOneWidget);
    await save(tester);

    final row = (await rows(tester)).single;
    expect(row.amountFiat, -12.5);
    expect(row.amountSats, 0);
    await tidy(tester);
  });

  testWidgets('category, notes and a weekly repeat are kept', (tester) async {
    await open(tester);
    await fill(tester, '9.99', 'Streaming');
    // The chips are a horizontal, lazily built list.
    await tester.scrollUntilVisible(
      find.text('Subscriptions'),
      100,
      scrollable:
          find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
    );
    await tester.ensureVisible(find.text('Subscriptions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subscriptions'));
    await tester.ensureVisible(find.text('Add notes'));
    await tester.tap(find.text('Add notes'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Notes'),
      'Family plan',
    );
    await tester.ensureVisible(find.text('Repeat'));
    await tester.tap(find.text('Repeat'));
    await tester.pump();
    await tester.ensureVisible(find.text('Weekly'));
    await tester.tap(find.text('Weekly'));
    await tester.pump();
    await save(tester);

    final row = (await rows(tester)).single;
    expect(row.category, 'Subscriptions');
    expect(row.notes, 'Family plan');
    expect(row.recurringPeriod, 'weekly');
    expect(row.recurringSeriesId, isNotNull);
    expect(row.recurringAnchorDate, isNotNull);
    await tidy(tester);
  });
}
