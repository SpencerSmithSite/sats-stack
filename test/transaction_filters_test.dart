/// The Transactions tab: close matches under their own heading, and a date
/// filter that counts on the badge, combines with the others and clears.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 9);
  // The last second of the 15th, as the database keeps it, and the first
  // instant of the 16th: either side of a picked end day.
  final lastMonth15 = DateTime(now.year, now.month - 1, 15, 23, 59, 59);
  final lastMonth16 = DateTime(now.year, now.month - 1, 16);

  Future<void> open(WidgetTester tester) async {
    await tester.runAsync(() async {
      app.db = AppDatabase.forTesting(NativeDatabase.memory());
      app.categoryService = CategoryService(app.db);
      app.transactionService = TransactionService(app.db);
      app.walletService = WalletService(app.db);
      app.btcPriceService = BtcPriceService(app.db);
      app.currencyNotifier = ValueNotifier('USD');
      app.showBtcPriceNotifier = ValueNotifier(false);
      final wallet = (await app.db.select(app.db.wallets).get()).first.id;
      for (final (name, amount, date, source) in [
        ('STARBUCKS #1234', -4.75, today, 'manual'),
        ('Starbuks Reserve', -6.0, today, 'manual'),
        ('AMZN Mktp US', -12.5, today, 'manual'),
        ('Rent', -1200.0, lastMonth15, 'manual'),
        ('Council tax', -150.0, lastMonth16, 'csv'),
      ]) {
        await app.db
            .into(app.db.transactions)
            .insert(
              TransactionsCompanion.insert(
                walletId: wallet,
                date: date,
                description: name,
                amountSats: 0,
                amountFiat: amount,
                fiatCurrency: 'USD',
                source: source,
                dedupHash: name,
              ),
            );
      }
    });
    tester.view.physicalSize = const Size(430, 1400);
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
    expect(find.text('Rent'), findsOneWidget);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => app.db.close());
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder badge(String count) =>
      find.descendant(of: find.byType(Badge), matching: find.text(count));

  Future<void> filter(WidgetTester tester, List<String> chips) async {
    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    for (final chip in chips) {
      await tester.tap(find.text(chip).last);
      await tester.pump();
    }
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
  }

  double top(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  testWidgets('a typo finds the row, listed after the exact matches', (
    tester,
  ) async {
    await open(tester);

    // Typed as the misspelt row spells it: that row is exact, the real
    // Starbucks a close match below the heading.
    await search(tester, 'starbuks');
    expect(find.text('Rent'), findsNothing);
    expect(find.text('Close matches'), findsOneWidget);
    expect(
      top(tester, 'Starbuks Reserve'),
      lessThan(top(tester, 'Close matches')),
    );
    expect(
      top(tester, 'Close matches'),
      lessThan(top(tester, 'STARBUCKS #1234')),
    );

    // Spelt properly, the two swap.
    await search(tester, 'starbucks');
    expect(
      top(tester, 'STARBUCKS #1234'),
      lessThan(top(tester, 'Close matches')),
    );
    expect(
      top(tester, 'Close matches'),
      lessThan(top(tester, 'Starbuks Reserve')),
    );

    // Nothing close to tolerate: no heading.
    await search(tester, 'amzn mktp');
    expect(find.text('AMZN Mktp US'), findsOneWidget);
    expect(find.text('Close matches'), findsNothing);
    expect(find.text('STARBUCKS #1234'), findsNothing);

    // An amount.
    await search(tester, '12.50');
    expect(find.text('AMZN Mktp US'), findsOneWidget);
    expect(find.text('Starbuks Reserve'), findsNothing);

    // Two letters do not fuzz.
    await search(tester, 'rn');
    expect(find.text('No results'), findsOneWidget);

    await close(tester);
  });

  testWidgets('a date preset filters, counts and combines', (tester) async {
    await open(tester);
    expect(find.byType(Badge), findsOneWidget);
    expect(badge('1'), findsNothing);

    await filter(tester, ['Last month']);
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('Council tax'), findsOneWidget);
    expect(find.text('STARBUCKS #1234'), findsNothing);
    expect(find.widgetWithText(Chip, 'Last month'), findsOneWidget);
    expect(badge('1'), findsOneWidget);

    // With a source too: both apply, and both count.
    await filter(tester, ['Manual']);
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('Council tax'), findsNothing);
    expect(badge('2'), findsOneWidget);

    // And with a search.
    await search(tester, 'rnet');
    expect(find.text('Rent'), findsOneWidget);
    await search(tester, '');

    // Removing the date chip leaves the source filter.
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(Chip, 'Last month'),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pump();
    expect(find.text('STARBUCKS #1234'), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('Council tax'), findsNothing);
    expect(badge('1'), findsOneWidget);

    // A preset chosen again turns off, and Clear all clears the date too.
    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This month'));
    await tester.pump();
    await tester.tap(find.text('This month'));
    await tester.pump();
    final thisMonth = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'This month'),
    );
    expect(thisMonth.selected, isFalse);
    await tester.tap(find.text('Last 90 days'));
    await tester.pump();
    await tester.tap(find.text('Clear all'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Council tax'), findsOneWidget);
    expect(badge('1'), findsNothing);

    await close(tester);
  });

  testWidgets('a picked range keeps the whole of its last day', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom…'));
    await tester.pumpAndSettle();
    expect(find.text('Show transactions from'), findsOneWidget);

    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    final first = DateTime(now.year, now.month - 1, 1);
    final last = DateTime(now.year, now.month - 1, 15);
    final typed = DateFormat('MM/dd/yyyy');
    await tester.enterText(
      find.widgetWithText(TextField, 'Start Date'),
      typed.format(first),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'End Date'),
      typed.format(last),
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final label =
        '${DateFormat.MMMd().format(first)} – '
        '${DateFormat.yMMMd().format(last)}';
    // The custom chip shows the range it holds.
    expect(find.widgetWithText(FilterChip, label), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Chip, label), findsOneWidget);
    expect(
      find.text('Rent'),
      findsOneWidget,
      reason: 'last second of the 15th',
    );
    expect(find.text('Council tax'), findsNothing, reason: 'the 16th');
    expect(find.text('STARBUCKS #1234'), findsNothing);
    expect(badge('1'), findsOneWidget);

    await close(tester);
  });
}
