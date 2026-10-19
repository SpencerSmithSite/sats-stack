/// End-to-end: aggregates over a month that mixes currencies.
///
/// Every aggregate used to sum `amountFiat` without looking at `fiatCurrency`,
/// so a GBP user with a USD card saw dollars added to pounds under a `£` label
/// on the dashboard, in budget progress and in the exported summary — while
/// the transactions list showed each row correctly.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/fx_rates.dart';
import 'package:sats_stack/core/services/budget_service.dart';
import 'package:sats_stack/core/services/dashboard_service.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late int walletId;
  late int foodId;
  var hashSeq = 0;

  // 1 USD = 0.8 GBP.
  const prices = {'USD': 100000.0, 'GBP': 80000.0};
  FxRates gbp() => const FxRates(display: 'GBP', btcPrices: prices);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    walletId = (await db.select(db.wallets).getSingle()).id;
    foodId = (await (db.select(db.categories)
              ..where((c) => c.name.equals('Food & Dining')))
            .getSingle())
        .id;
  });

  tearDown(() => db.close());

  Future<void> add({
    required double fiat,
    required String currency,
    String category = 'Food & Dining',
    int sats = 0,
    bool isBitcoin = false,
  }) =>
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            walletId: walletId,
            date: DateTime(2026, 3, 10),
            description: 'row ${hashSeq++}',
            amountSats: sats,
            amountFiat: fiat,
            fiatCurrency: currency,
            category: Value(category),
            source: 'manual',
            isBitcoin: Value(isBitcoin),
            dedupHash: 'h$hashSeq',
          ));

  test('the dashboard converts foreign rows instead of adding them raw', () async {
    await add(fiat: -100, currency: 'GBP'); // £100 groceries
    await add(fiat: -50, currency: 'USD'); //  $50 on a US card
    await add(fiat: 2000, currency: 'GBP', category: 'Income');

    final data = await DashboardService(db, rates: gbp)
        .getDashboard(DateTime(2026, 3));

    // Was £150. $50 is £40 at 1 USD = 0.8 GBP.
    expect(data.monthlySpendingFiat, closeTo(140, 1e-9));
    expect(data.monthlyIncomeFiat, closeTo(2000, 1e-9));
    expect(data.spendingByCategory['Food & Dining'], closeTo(140, 1e-9));
    expect(data.unconvertedCount, 0);
  });

  test('recent rows keep their own currency for display', () async {
    // The list renders each row with its own currency label, so restating
    // the amount would print "$40.00" for a $50 charge.
    await add(fiat: -50, currency: 'USD');

    final data = await DashboardService(db, rates: gbp)
        .getDashboard(DateTime(2026, 3));

    final row = data.recentTransactions.single;
    expect(row.amountFiat, -50);
    expect(row.fiatCurrency, 'USD');
  });

  test('a row with no rate is excluded from fiat and counted', () async {
    await add(fiat: -100, currency: 'GBP');
    await add(fiat: -5000, currency: 'JPY'); // no JPY price available

    final data = await DashboardService(db, rates: gbp)
        .getDashboard(DateTime(2026, 3));

    // Not ¥5000 added to pounds, and not silently missing either.
    expect(data.monthlySpendingFiat, closeTo(100, 1e-9));
    expect(data.unconvertedCount, 1);
  });

  test('an unconvertible row still counts toward the stack', () async {
    // Sats need no exchange rate, so losing a fiat rate must not lose them.
    await add(
      fiat: 5000,
      currency: 'JPY',
      sats: 250000,
      isBitcoin: true,
      category: 'Bitcoin',
    );

    final data = await DashboardService(db, rates: gbp)
        .getDashboard(DateTime(2026, 3));

    expect(data.totalStackSats, 250000);
    expect(data.unconvertedCount, 1);
  });

  test('budget progress is measured in the display currency', () async {
    await db.into(db.budgets).insert(BudgetsCompanion.insert(
          categoryId: foodId,
          amountFiat: 500,
          period: 'monthly',
        ));
    await add(fiat: -100, currency: 'GBP');
    await add(fiat: -50, currency: 'USD');

    final progress = await BudgetService(db, rates: gbp)
        .getProgress(DateTime(2026, 3));

    // A £500 budget against £140 of spending — was measured against "£150".
    expect(progress.single.spentFiat, closeTo(140, 1e-9));
  });

  test('without a converter, a service behaves exactly as before', () async {
    // What every existing test constructing a service directly relies on.
    await add(fiat: -100, currency: 'GBP');
    await add(fiat: -50, currency: 'USD');

    final data = await DashboardService(db).getDashboard(DateTime(2026, 3));
    expect(data.monthlySpendingFiat, closeTo(150, 1e-9));
  });
}
