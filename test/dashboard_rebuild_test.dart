/// The Dashboard against real services on an in-memory database.
///
/// Its price and currency listeners used to wrap the whole content, so every
/// BTC price poll rebuilt every section and every transaction row. Each
/// section that shows a price-derived figure now listens for itself.
///
/// Measured by widget identity: a row whose parent did not rebuild keeps the
/// very same widget object across the price change.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/fx_rates.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/category_service.dart';
import 'package:sats_stack/core/services/dashboard_service.dart';
import 'package:sats_stack/features/dashboard/dashboard_screen.dart';
import 'package:sats_stack/features/dashboard/widgets/hero_card.dart';
import 'package:sats_stack/features/transactions/widgets/transaction_list_item.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/theme/app_theme.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<void> addRow(int sats, double fiat, String description) async {
    final wallet = (await app.db.select(app.db.wallets).get()).first.id;
    await app.db.into(app.db.transactions).insert(TransactionsCompanion.insert(
          walletId: wallet,
          date: DateTime.now(),
          description: description,
          amountSats: sats,
          amountFiat: fiat,
          fiatCurrency: 'USD',
          source: 'manual',
          dedupHash: description,
        ));
  }

  testWidgets('a price tick rebuilds what shows the price, not every row',
      (tester) async {
    await tester.runAsync(() async {
      app.db = AppDatabase.forTesting(NativeDatabase.memory());
      app.categoryService = CategoryService(app.db);
      app.btcPriceService = BtcPriceService(app.db);
      app.currencyNotifier = ValueNotifier('USD');
      app.inflationRateNotifier = ValueNotifier(3.5);
      app.aiEnabledNotifier = ValueNotifier(false);
      app.showBtcPriceNotifier = ValueNotifier(false);
      app.dashboardService = DashboardService(app.db,
          rates: () => const FxRates(display: 'USD', btcPrices: {}));
      await addRow(-25000, -20, 'Has stored sats');
      await addRow(0, -10, 'No stored sats');
    });

    // Tall enough that the lazily built list reaches the recent rows.
    tester.view.physicalSize = const Size(430, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const DashboardScreen(),
    ));
    // Let the drift queries land, then build with their results.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 300));

    TransactionListItem row(String description) =>
        tester.widget<TransactionListItem>(find.byWidgetPredicate((w) =>
            w is TransactionListItem &&
            w.transaction.description == description));

    final storedBefore = row('Has stored sats');
    final derivedBefore = row('No stored sats');
    final heroBefore = tester.widget<HeroCard>(find.byType(HeroCard));

    app.btcPriceService.priceNotifier.value = 80000;
    await tester.pump();

    // Untouched: its sats are stored, so the price means nothing to it.
    expect(identical(row('Has stored sats'), storedBefore), isTrue);
    // Rebuilt: it derives its sats from the price.
    expect(identical(row('No stored sats'), derivedBefore), isFalse);
    expect(row('No stored sats').btcPrice, 80000);
    // And the hero shows the new price.
    expect(tester.widget<HeroCard>(find.byType(HeroCard)).btcPrice, 80000);
    expect(identical(tester.widget<HeroCard>(find.byType(HeroCard)), heroBefore),
        isFalse);

    // Unmount first, and let drift's stream teardown run on the test clock;
    // closing with a stream query still scheduled there never completes.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => app.db.close());
  }, timeout: const Timeout(Duration(minutes: 1)));
}
