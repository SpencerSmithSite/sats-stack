/// Search waits for a pause in typing (audit U-17).
///
/// Every keystroke filtered every transaction and regrouped them by day,
/// which lagged on a long history.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
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

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('the list filters once typing pauses', (tester) async {
    await tester.runAsync(() async {
      app.db = AppDatabase.forTesting(NativeDatabase.memory());
      app.categoryService = CategoryService(app.db);
      app.transactionService = TransactionService(app.db);
      app.walletService = WalletService(app.db);
      app.btcPriceService = BtcPriceService(app.db);
      app.currencyNotifier = ValueNotifier('USD');
      app.showBtcPriceNotifier = ValueNotifier(false);
      final wallet = (await app.db.select(app.db.wallets).get()).first.id;
      for (final (name, amount) in [('Coffee', -4.0), ('Rent', -1200.0)]) {
        await app.db
            .into(app.db.transactions)
            .insert(
              TransactionsCompanion.insert(
                walletId: wallet,
                date: DateTime.now(),
                description: name,
                amountSats: 0,
                amountFiat: amount,
                fiatCurrency: 'USD',
                source: 'manual',
                dedupHash: name,
              ),
            );
      }
    });
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const TransactionsScreen()),
          ],
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Coffee'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 're');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'rent');
    await tester.pump(const Duration(milliseconds: 100));
    // Still typing: nothing filtered yet.
    expect(find.text('Coffee'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Coffee'), findsNothing);
    expect(find.text('Rent'), findsOneWidget);

    // Clearing is immediate.
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(find.text('Coffee'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => app.db.close());
  });
}
