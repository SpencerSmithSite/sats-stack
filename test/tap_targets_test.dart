/// Touch targets on a phone are at least 48 px (audit U-14).
///
/// `VisualDensity.compact` and shrink-wrapped tap targets made the
/// Transactions app bar icons 40 px, and the filter chips and Clear smaller.
/// Material's default density is already compact on desktop alone.
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

  testWidgets('Transactions, with a filter applied', (tester) async {
    final handle = tester.ensureSemantics();
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
      MaterialApp.router(
        theme: AppTheme.light(),
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

    // A source filter, so the active chip and Clear are on screen.
    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual').last);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Clear'), findsOneWidget);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));

    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => app.db.close());
    // A phone: on desktop, Material's own density is compact on purpose.
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
