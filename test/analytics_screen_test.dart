/// The analytics screen (audit T-1: it had 1% line coverage).
///
/// Pins what it shows for a month: each category's share and amount, what a
/// screen reader is told about both charts, the year-to-date figures, the
/// trend narrowed to one category, moving between months, and the empty
/// state.
library;

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/fx_rates.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/category_service.dart';
import 'package:sats_stack/core/services/dashboard_service.dart';
import 'package:sats_stack/features/analytics/analytics_screen.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/theme/app_theme.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month, 10);
  final lastMonth = DateTime(now.year, now.month - 1, 10);

  Future<void> open(
    WidgetTester tester, {
    List<(DateTime, double, String)> rows = const [],
  }) async {
    await tester.runAsync(() async {
      app.db = AppDatabase.forTesting(NativeDatabase.memory());
      app.categoryService = CategoryService(app.db);
      app.btcPriceService = BtcPriceService(app.db);
      app.currencyNotifier = ValueNotifier('USD');
      app.dashboardService = DashboardService(
        app.db,
        rates: () => const FxRates(display: 'USD', btcPrices: {}),
      );
      final wallet = (await app.db.select(app.db.wallets).getSingle()).id;
      for (final (i, (date, amount, category)) in rows.indexed) {
        await app.db
            .into(app.db.transactions)
            .insert(
              TransactionsCompanion.insert(
                walletId: wallet,
                date: date,
                description: category,
                amountSats: 0,
                amountFiat: amount,
                fiatCurrency: 'USD',
                category: Value(category),
                source: 'manual',
                dedupHash: 'row$i',
              ),
            );
      }
    });
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const AnalyticsScreen()),
    );
    await settle(tester);
  }

  Future<void> tidy(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => app.db.close());
  }

  final month = [
    (thisMonth, -60.0, 'Food & Dining'),
    (thisMonth, -40.0, 'Transport'),
    (thisMonth, 500.0, 'Income'),
    (lastMonth, -30.0, 'Food & Dining'),
  ];

  testWidgets('a month: shares, amounts, and what a screen reader hears', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await open(tester, rows: month);

    expect(find.text('SPENDING BY CATEGORY'), findsOneWidget);
    expect(find.text('60.0%'), findsOneWidget);
    expect(find.text('40.0%'), findsOneWidget);
    expect(find.text(r'$60'), findsOneWidget);
    expect(find.text(r'$40'), findsOneWidget);
    // Income is not spending, so it is not a slice.
    expect(find.text('Income'), findsOneWidget); // the YTD label only
    expect(
      find.bySemanticsLabel(
        RegExp(
          r'^Spending by category: Food & Dining 60 percent, '
          // The legend's rows follow, merged into the same node.
          r'Transport 40 percent\n',
        ),
      ),
      findsOneWidget,
    );
    handle.dispose();
    await tidy(tester);
  });

  testWidgets('year to date', (tester) async {
    await open(tester, rows: month);
    // Last month counts too, unless it was last year.
    final spent = 100 + (lastMonth.year == now.year ? 30 : 0);
    expect(find.text('YEAR TO DATE (${now.year})'), findsOneWidget);
    expect(find.text(r'$500'), findsOneWidget);
    expect(find.text('\$$spent'), findsOneWidget);
    expect(find.text('+\$${500 - spent}'), findsOneWidget);
    await tidy(tester);
  });

  testWidgets('the trend narrows to one category', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester, rows: month);
    expect(find.bySemanticsLabel(RegExp('^Spending by month: ')), findsOne);

    await tester.tap(find.text('Transport').last);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('^Transport by month: ')), findsOne);
    handle.dispose();
    await tidy(tester);
  });

  testWidgets('back a month, and no further forward than now', (tester) async {
    await open(tester, rows: month);
    final next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(next.onPressed, isNull);

    await tester.tap(find.byTooltip('Previous month'));
    await settle(tester);
    // Last month had only the one Food & Dining row.
    expect(find.text('100.0%'), findsOneWidget);
    expect(find.text('Transport'), findsNothing);
    await tidy(tester);
  });

  testWidgets('with nothing spent, it says so', (tester) async {
    await open(tester);
    expect(find.text('No spending data yet'), findsOneWidget);
    await tidy(tester);
  });
}

/// Real I/O, so real time: pumps until the screen has loaded — no spinner —
/// or gives up after five seconds and lets the expectations say so.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 50; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
  }
}
