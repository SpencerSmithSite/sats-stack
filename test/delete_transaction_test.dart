/// Deleting a transaction from inside a tab.
///
/// The row and the edit sheet live in the tab's own Navigator, but
/// `showDialog` pushes onto the root one. The dialogs used to pop with the
/// row's (or sheet's) context, which popped the tab's only page — a blank app —
/// or the sheet underneath, leaving the dialog open and nothing deleted.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/category_service.dart';
import 'package:sats_stack/core/services/transaction_service.dart';
import 'package:sats_stack/core/services/wallet_service.dart';
import 'package:sats_stack/features/transactions/transactions_screen.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/theme/app_theme.dart';

GoRouter _router() => GoRouter(
  initialLocation: '/transactions',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (ctx, state, shell) => Scaffold(body: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/transactions',
              builder: (ctx, state) => const TransactionsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/other',
              builder: (ctx, state) => const Text('other'),
            ),
          ],
        ),
      ],
    ),
  ],
);

Future<void> _setup(WidgetTester tester) async {
  await tester.runAsync(() async {
    app.db = AppDatabase.forTesting(NativeDatabase.memory());
    app.categoryService = CategoryService(app.db);
    app.transactionService = TransactionService(app.db);
    app.walletService = WalletService(app.db);
    app.btcPriceService = BtcPriceService(app.db);
    app.currencyNotifier = ValueNotifier('USD');
    app.showBtcPriceNotifier = ValueNotifier(false);
    final wallet = (await app.db.select(app.db.wallets).get()).first.id;
    await app.db
        .into(app.db.transactions)
        .insert(
          TransactionsCompanion.insert(
            walletId: wallet,
            date: DateTime.now(),
            description: 'Coffee',
            amountSats: 0,
            amountFiat: -4,
            fiatCurrency: 'USD',
            source: 'manual',
            dedupHash: 'coffee',
          ),
        );
  });
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp.router(theme: AppTheme.dark(), routerConfig: _router()),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  await tester.runAsync(() => app.db.close());
}

Future<int> _rowCount(WidgetTester tester) async =>
    (await tester.runAsync(() => app.db.select(app.db.transactions).get()))!
        .length;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('long-press, Cancel: dialog closes, row and tab remain', (
    tester,
  ) async {
    await _setup(tester);
    await tester.longPress(find.text('Coffee'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Delete transaction?'), findsNothing);
    expect(find.byType(TransactionsScreen), findsOneWidget);
    expect(await _rowCount(tester), 1);
    await _teardown(tester);
  });

  testWidgets('long-press, Delete: row deleted, tab remains', (tester) async {
    await _setup(tester);
    await tester.longPress(find.text('Coffee'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete transaction?'), findsNothing);
    expect(find.byType(TransactionsScreen), findsOneWidget);
    expect(await _rowCount(tester), 0);
    await _teardown(tester);
  });

  testWidgets('edit sheet, Delete: row deleted, sheet and dialog close', (
    tester,
  ) async {
    await _setup(tester);
    await tester.tap(find.text('Coffee'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete transaction?'), findsNothing);
    expect(find.byType(TransactionsScreen), findsOneWidget);
    expect(await _rowCount(tester), 0);
    await _teardown(tester);
  });
}
