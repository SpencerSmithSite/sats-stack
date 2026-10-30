/// Budgets know their currency, and alerts are sent once per occasion.
///
/// A budget was a bare number read in whatever the display currency happened
/// to be, so switching from GBP to USD turned £500 into $500 — and could fire
/// an overspend alert. Alerts were deduplicated by a per-session set of ids:
/// every cold start re-sent them all (the stack goal on every launch once
/// reached), and a new month could not alert until the app was restarted.
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/fx_rates.dart';
import 'package:sats_stack/core/services/budget_service.dart';
import 'package:sats_stack/core/services/notification_service.dart';
import 'package:sats_stack/shared/constants/app_constants.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late int foodId;
  late int walletId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    foodId =
        (await (db.select(db.categories)
              ..where((c) => c.name.equals('Food & Dining'))).getSingle())
            .id;
    walletId = (await db.select(db.wallets).getSingle()).id;
  });
  tearDown(() => db.close());

  // 1 BTC = £50,000 = $62,500, so £1 = $1.25.
  const prices = {'GBP': 50000.0, 'USD': 62500.0};
  FxRates usd() => const FxRates(display: 'USD', btcPrices: prices);
  FxRates usdNoRates() => const FxRates(display: 'USD', btcPrices: {});

  Future<void> spend(double amount, String currency, DateTime date) => db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          walletId: walletId,
          date: date,
          description: 'Groceries',
          amountSats: 0,
          amountFiat: -amount,
          fiatCurrency: currency,
          category: const Value('Food & Dining'),
          source: 'manual',
          dedupHash: '$amount-$currency-$date',
        ),
      );

  group('a budget keeps its currency', () {
    test('a £500 budget reads as \$625 after switching to dollars', () async {
      await BudgetService(
        db,
      ).upsert(categoryId: foodId, amountFiat: 500, currency: 'gbp');
      await spend(550, 'USD', DateTime(2026, 3, 10));

      final p =
          (await BudgetService(
            db,
            rates: usd,
          ).getProgress(DateTime(2026, 3))).single;

      expect(p.budget.currency, 'GBP');
      expect(p.limitFiat, closeTo(625, 1e-9));
      // $550 against $625: not over. Read as $500, it was.
      expect(p.isOverBudget, isFalse);
      expect(p.remainingFiat, closeTo(75, 1e-9));
    });

    test('with no rate it is never reported as overspent', () async {
      await BudgetService(
        db,
      ).upsert(categoryId: foodId, amountFiat: 500, currency: 'GBP');
      await spend(900, 'USD', DateTime(2026, 3, 10));

      final p =
          (await BudgetService(
            db,
            rates: usdNoRates,
          ).getProgress(DateTime(2026, 3))).single;

      expect(p.limitFiat, isNull);
      expect(p.isOverBudget, isFalse);
      expect(p.progress, 0);
    });

    test(
      'editing a budget re-stamps it in the currency it is saved in',
      () async {
        final budgets = BudgetService(db);
        await budgets.upsert(
          categoryId: foodId,
          amountFiat: 500,
          currency: 'GBP',
        );
        await budgets.upsert(
          categoryId: foodId,
          amountFiat: 600,
          currency: 'USD',
        );

        final row = await db.select(db.budgets).getSingle();
        expect((row.amountFiat, row.currency), (600, 'USD'));
      },
    );

    test('the v10 upgrade stamps budgets with the display currency', () async {
      final dir = await Directory.systemTemp.createTemp('v10');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/db.sqlite');

      final v9 = AppDatabase.forTesting(NativeDatabase(file));
      final food =
          (await (v9.select(v9.categories)
                ..where((c) => c.name.equals('Food & Dining'))).getSingle())
              .id;
      await v9.customStatement('ALTER TABLE budgets DROP COLUMN currency');
      await v9.customStatement(
        'INSERT INTO budgets (category_id, amount_fiat, period, created_at) '
        "VALUES (?, 500, 'monthly', 0)",
        [food],
      );
      await v9
          .into(v9.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: AppConstants.settingCurrency,
              value: 'gbp',
            ),
          );
      await v9.customStatement('PRAGMA user_version = 9');
      await v9.close();

      final upgraded = AppDatabase.forTesting(NativeDatabase(file));
      final row = await upgraded.select(upgraded.budgets).getSingle();
      expect(row.currency, 'GBP');
      await upgraded.close();
    });
  });

  group('alerts are sent once per occasion', () {
    test('the ledger claims a key once, across restarts', () async {
      expect(await NotificationLedger(db).claim('stack_goal_100'), isTrue);
      expect(await NotificationLedger(db).claim('stack_goal_100'), isFalse);
      // A raised goal is a new occasion.
      expect(await NotificationLedger(db).claim('stack_goal_200'), isTrue);
    });

    test('a new month alerts again, and old months are forgotten', () async {
      final ledger = NotificationLedger(db);
      expect(await ledger.claim('budget_over_3_2026-03'), isTrue);
      expect(await ledger.claim('budget_warn_3_2026-03'), isTrue);
      expect(await ledger.claim('budget_over_3_2026-03'), isFalse);

      expect(await ledger.claim('budget_over_3_2026-04'), isTrue);

      final keys = (await db.select(db.appSettings).get()).map((s) => s.key);
      expect(keys.where((k) => k.startsWith('notified:budget_')), [
        'notified:budget_over_3_2026-04',
      ]);
    });

    test('checkAndNotify claims each budget alert once per month', () async {
      final claimed = <String>[];
      final ledger = NotificationLedger(db);
      final notifications = NotificationService(
        claim: (key) async {
          final fresh = await ledger.claim(key);
          if (fresh) claimed.add(key);
          return fresh;
        },
      );
      final budgets = BudgetService(db);
      await budgets.upsert(
        categoryId: foodId,
        amountFiat: 100,
        currency: 'USD',
      );
      await spend(150, 'USD', DateTime(2026, 3, 10));
      await spend(150, 'USD', DateTime(2026, 4, 10));

      for (var i = 0; i < 3; i++) {
        await budgets.checkAndNotify(
          notifications: notifications,
          currency: 'USD',
          now: DateTime(2026, 3, 20),
        );
      }
      await budgets.checkAndNotify(
        notifications: notifications,
        currency: 'USD',
        now: DateTime(2026, 4, 20),
      );

      expect(claimed, [
        'budget_over_${foodId}_2026-03',
        'budget_over_${foodId}_2026-04',
      ]);
    });
  });
}
