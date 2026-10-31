/// Each tab subscribes to its data once, and keeps it across a rebuild
/// (TODO item 13).
///
/// The bug class: a stream built in `build()` is a new query on every
/// rebuild, so the screen drops back to its loading state — a flash of
/// spinner, a list that empties and refills — whenever anything above it
/// changes, and a long session piles up live queries. Each tab here is shown
/// its data, rebuilt from above by a theme change, and must still show it on
/// the very next frame, before any query could have answered again; then a new
/// row must still arrive, so the one subscription is still live.
///
/// Built like `dashboard_rebuild_test`: real services on an in-memory
/// database.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/fx_rates.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/budget_service.dart';
import 'package:sats_stack/core/services/category_service.dart';
import 'package:sats_stack/core/services/dashboard_service.dart';
import 'package:sats_stack/core/services/notification_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/transaction_service.dart';
import 'package:sats_stack/core/services/wallet_service.dart';
import 'package:sats_stack/core/services/xpub_service.dart';
import 'package:sats_stack/features/budgets/budgets_screen.dart';
import 'package:sats_stack/features/stack/stack_screen.dart';
import 'package:sats_stack/features/transactions/transactions_screen.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/theme/app_theme.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  var seq = 0;
  Future<void> addRow({
    required String description,
    int sats = 0,
    double fiat = -10,
    String category = 'Food & Dining',
    bool bitcoin = false,
  }) async {
    final wallet = (await app.db.select(app.db.wallets).get()).first.id;
    await app.db
        .into(app.db.transactions)
        .insert(
          TransactionsCompanion.insert(
            walletId: wallet,
            date: DateTime.now(),
            description: description,
            amountSats: sats,
            amountFiat: fiat,
            fiatCurrency: 'USD',
            category: Value(category),
            source: 'manual',
            isBitcoin: Value(bitcoin),
            dedupHash: 'h${seq++}',
          ),
        );
  }

  Future<void> services() async {
    app.db = AppDatabase.forTesting(NativeDatabase.memory());
    FxRates rates() => const FxRates(display: 'USD', btcPrices: {});
    app.categoryService = CategoryService(app.db);
    app.transactionService = TransactionService(app.db);
    app.walletService = WalletService(app.db);
    app.btcPriceService = BtcPriceService(app.db);
    app.budgetService = BudgetService(app.db, rates: rates);
    app.dashboardService = DashboardService(app.db, rates: rates);
    app.xpubService = XpubService(app.db);
    app.ollamaService = OllamaService(app.db);
    app.notificationService = NotificationService();
    app.currencyNotifier = ValueNotifier('USD');
    app.showBtcPriceNotifier = ValueNotifier(false);
    app.inflationRateNotifier = ValueNotifier(3.5);
    app.aiEnabledNotifier = ValueNotifier(false);
  }

  /// Lets drift's queries answer, then builds with what they returned.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> check(
    WidgetTester tester, {
    required Widget screen,
    required Future<void> Function() seed,
    required Finder shown,
    required Future<void> Function() addMore,
    required Finder shownAfter,
  }) async {
    await tester.runAsync(() async {
      await services();
      await seed();
    });
    tester.view.physicalSize = const Size(430, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final dark = ValueNotifier(true);
    await tester.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: dark,
        builder:
            (_, isDark, _) => MaterialApp(
              theme: isDark ? AppTheme.dark() : AppTheme.light(),
              home: screen,
            ),
      ),
    );
    await settle(tester);
    expect(shown, findsWidgets);

    // Rebuilt from above, and looked at on the very next frame.
    dark.value = false;
    await tester.pump();
    expect(shown, findsWidgets, reason: 'lost its data on a rebuild');
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.runAsync(addMore);
    await settle(tester);
    expect(shownAfter, findsWidgets, reason: 'stopped listening');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => app.db.close());
  }

  testWidgets('Transactions', (tester) async {
    await check(
      tester,
      screen: const TransactionsScreen(),
      seed: () => addRow(description: 'Groceries'),
      shown: find.text('Groceries'),
      addMore: () => addRow(description: 'Coffee'),
      shownAfter: find.text('Coffee'),
    );
  });

  testWidgets('Budgets', (tester) async {
    Future<void> budget(String name, double limit) async {
      final c = (await app.categoryService.getAll()).firstWhere(
        (c) => c.name == name,
      );
      await app.budgetService.upsert(
        categoryId: c.id,
        amountFiat: limit,
        currency: 'USD',
      );
    }

    await check(
      tester,
      screen: const BudgetsScreen(),
      seed: () async {
        await budget('Food & Dining', 300);
        await addRow(description: 'Groceries', fiat: -42);
      },
      shown: find.text('Food & Dining'),
      addMore: () => budget('Transport', 80),
      shownAfter: find.text('Transport'),
    );
  });

  testWidgets('Stack', (tester) async {
    await check(
      tester,
      screen: const StackScreen(),
      seed:
          () => addRow(
            description: 'Bought',
            sats: 125000,
            fiat: -100,
            category: 'Bitcoin',
            bitcoin: true,
          ),
      shown: find.textContaining('125,000'),
      addMore:
          () => addRow(
            description: 'Bought more',
            sats: 50000,
            fiat: -40,
            category: 'Bitcoin',
            bitcoin: true,
          ),
      shownAfter: find.textContaining('175,000'),
    );
  });
}
