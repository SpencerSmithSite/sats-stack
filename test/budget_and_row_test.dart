/// Adding a budget cannot replace one, and an outgoing Bitcoin payment is
/// shown as one.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/budget_service.dart';
import 'package:sats_stack/core/services/category_service.dart';
import 'package:sats_stack/features/budgets/widgets/set_budget_sheet.dart';
import 'package:sats_stack/features/transactions/widgets/transaction_list_item.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/theme/app_theme.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('the add-budget sheet offers only unbudgeted categories', (
    tester,
  ) async {
    late BudgetService budgets;
    late CategoryService categories;
    await tester.runAsync(() async {
      app.db = AppDatabase.forTesting(NativeDatabase.memory());
      app.currencyNotifier = ValueNotifier('GBP');
      budgets = BudgetService(app.db);
      categories = CategoryService(app.db);
      final food = (await categories.getAll()).firstWhere(
        (c) => c.name == 'Food & Dining',
      );
      await budgets.upsert(
        categoryId: food.id,
        amountFiat: 300,
        currency: 'USD',
      );
    });
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SetBudgetSheet(
            budgetService: budgets,
            categoryService: categories,
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    // Picking it and saving replaced the £300 budget.
    expect(find.text('Food & Dining'), findsNothing);
    expect(find.text('Transport'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => app.db.close());
  });

  testWidgets('an unpriced outgoing Bitcoin payment reads as outgoing', (
    tester,
  ) async {
    // Fiat 0: no historical price was found. The sign came from the fiat, so
    // this showed as a green "+" receipt.
    final tx = Transaction(
      id: 1,
      walletId: 1,
      date: DateTime(2025, 3, 4),
      description: 'BTC f00df00d',
      amountSats: -50000,
      amountFiat: 0,
      fiatCurrency: 'USD',
      source: 'xpub',
      isBitcoin: true,
      isOwnTransfer: false,
      dedupHash: 'h',
      createdAt: DateTime(2025, 3, 4),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: TransactionListItem(transaction: tx, category: null),
        ),
      ),
    );
    expect(find.text('-50,000 sats'), findsOneWidget);
  });
}
