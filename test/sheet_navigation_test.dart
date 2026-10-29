/// Bottom sheets open on the root navigator, above the tab bar, and close
/// themselves rather than the tab underneath.
///
/// They used to open inside the tab's navigator, so the bottom bar stayed live
/// behind them and switching tabs orphaned the sheet. Moving them to the root
/// means a sheet that pops with the context of the widget that opened it pops
/// the tab's page instead — the bug the transaction delete dialogs had.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/budget_service.dart';
import 'package:sats_stack/core/services/category_service.dart';
import 'package:sats_stack/core/services/notification_service.dart';
import 'package:sats_stack/features/budgets/budgets_screen.dart';
import 'package:sats_stack/features/budgets/widgets/set_budget_sheet.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/theme/app_theme.dart';

GoRouter _router() => GoRouter(
  initialLocation: '/budgets',
  routes: [
    StatefulShellRoute.indexedStack(
      builder:
          (ctx, state, shell) => Scaffold(
            body: shell,
            bottomNavigationBar: const SizedBox(
              height: 56,
              child: Text('tabs'),
            ),
          ),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/budgets',
              builder: (ctx, state) => const BudgetsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/other', builder: (ctx, state) => const Text('o')),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUp(() {
    app.db = AppDatabase.forTesting(NativeDatabase.memory());
    app.categoryService = CategoryService(app.db);
    app.budgetService = BudgetService(app.db);
    app.btcPriceService = BtcPriceService(app.db);
    app.notificationService = NotificationService();
    app.currencyNotifier = ValueNotifier('USD');
    app.showBtcPriceNotifier = ValueNotifier(false);
  });

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => app.db.close());
  }

  testWidgets('budget options: Edit closes the options, not the tab', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final food = (await app.categoryService.getAll()).firstWhere(
        (c) => c.name == 'Food & Dining',
      );
      await app.budgetService.upsert(
        categoryId: food.id,
        amountFiat: 300,
        currency: 'USD',
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
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Food & Dining').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit Food & Dining budget'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Edit Food & Dining budget'), findsNothing);
    expect(find.text('Edit Budget'), findsOneWidget);
    expect(find.byType(BudgetsScreen), findsOneWidget);
    await teardown(tester);
  });

  testWidgets(
    'the budget sheet scrolls with the keyboard up on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 291);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: TextButton(
                    onPressed:
                        () => showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          builder:
                              (_) => SetBudgetSheet(
                                budgetService: app.budgetService,
                                categoryService: app.categoryService,
                              ),
                        ),
                    child: const Text('open'),
                  ),
                ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.dragUntilVisible(
        find.text('Save Budget'),
        find.byType(Scrollable).last,
        const Offset(0, -100),
      );
      expect(find.text('Save Budget'), findsOneWidget);
      await teardown(tester);
    },
  );
}
