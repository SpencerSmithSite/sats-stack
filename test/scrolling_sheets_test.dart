/// Sheets scroll rather than overflow (audit U-12).
///
/// Plain columns with no scroll: with many wallets or categories, or a large
/// text size, the bottom rows and the Apply or Save button could not be
/// reached, and Flutter reported an overflow.
library;

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/category_service.dart';
import 'package:sats_stack/core/services/transaction_service.dart';
import 'package:sats_stack/core/services/wallet_service.dart';
import 'package:sats_stack/core/services/xpub_service.dart';
import 'package:sats_stack/features/stack/widgets/stack_goal_card.dart';
import 'package:sats_stack/features/transactions/transactions_screen.dart';
import 'package:sats_stack/features/transactions/widgets/manage_wallets_sheet.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/theme/app_theme.dart';

/// The BIP84 test vector's account key.
const _zpub =
    'zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1ADqtf'
    'SdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  /// A short phone at double text size, the sheet in the bottom half.
  Future<void> pumpSheet(
    WidgetTester tester,
    Widget sheet, {
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: sheet,
              ),
            ),
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  testWidgets('the stack goal sheet', (tester) async {
    await pumpSheet(tester, SetGoalSheet(current: null, onSave: (_) {}));
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('the wallets sheet, with many wallets', (tester) async {
    late AppDatabase db;
    await tester.runAsync(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      for (var i = 0; i < 12; i++) {
        await db
            .into(db.wallets)
            .insert(
              WalletsCompanion.insert(
                label: 'Wallet $i',
                type: 'xpub',
                color: '#F7931A',
                xpub: const Value(_zpub),
              ),
            );
      }
    });
    await pumpSheet(
      tester,
      settle: false,
      ManageWalletsSheet(
        xpubService: XpubService(db),
        walletService: WalletService(db),
        btcPriceService: BtcPriceService(db),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Wallet 11', skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  });

  testWidgets('the transactions filter sheet', (tester) async {
    await tester.runAsync(() async {
      app.db = AppDatabase.forTesting(NativeDatabase.memory());
      app.categoryService = CategoryService(app.db);
      app.transactionService = TransactionService(app.db);
      app.walletService = WalletService(app.db);
      app.btcPriceService = BtcPriceService(app.db);
      app.currencyNotifier = ValueNotifier('USD');
      app.showBtcPriceNotifier = ValueNotifier(false);
    });
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.dark(),
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
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
    // The empty list overflowed too, before any sheet opened.
    expect(tester.takeException(), isNull, reason: 'the empty list');
    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Apply'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => app.db.close());
  });
}
