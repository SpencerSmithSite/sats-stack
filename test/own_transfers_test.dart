/// A Bitcoin movement the user marks as a transfer between their own wallets
/// keeps its sats but leaves the fiat totals (schema v12).
///
/// A self-send between two xpub wallets is a spend in one and a receipt in the
/// other, so it counted as both income and spending. Whether a movement is
/// really the user's own is something only they know, so it is a checkbox,
/// off by default.
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/budget_service.dart';
import 'package:sats_stack/core/services/category_service.dart';
import 'package:sats_stack/core/services/dashboard_service.dart';
import 'package:sats_stack/core/services/transaction_service.dart';
import 'package:sats_stack/features/transactions/widgets/transaction_edit_sheet.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/theme/app_theme.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final march = DateTime(2026, 3, 10);
  var seq = 0;

  Future<int> add(
    AppDatabase db, {
    required int sats,
    required double fiat,
    bool isBitcoin = true,
    bool ownTransfer = false,
    String category = 'Bitcoin',
  }) async {
    final wallet = (await db.select(db.wallets).get()).first.id;
    return db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            walletId: wallet,
            date: march,
            description: 'row ${seq++}',
            amountSats: sats,
            amountFiat: fiat,
            fiatCurrency: 'USD',
            category: Value(category),
            source: isBitcoin ? 'xpub' : 'manual',
            isBitcoin: Value(isBitcoin),
            isOwnTransfer: Value(ownTransfer),
            dedupHash: 'h$seq',
          ),
        );
  }

  group('totals', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('a new row counts in fiat until the user says otherwise', () async {
      final id = await add(db, sats: -10000, fiat: -10);
      final row =
          await (db.select(db.transactions)
            ..where((t) => t.id.equals(id))).getSingle();
      expect(row.isOwnTransfer, isFalse);
      final data = await DashboardService(db).getDashboard(march);
      expect(data.monthlySpendingFiat, 10);
    });

    test(
      'a self-send leaves income and spending, and stays in the stack',
      () async {
        // Out of one wallet with a fee, into the other.
        await add(db, sats: -10500, fiat: -10.5, ownTransfer: true);
        await add(db, sats: 10000, fiat: 10, ownTransfer: true);
        await add(db, sats: 0, fiat: -40, isBitcoin: false, category: 'Other');

        final data = await DashboardService(db).getDashboard(march);
        expect(data.monthlyIncomeFiat, 0);
        expect(data.monthlySpendingFiat, 40);
        expect(data.spendingByCategory.keys, ['Other']);
        expect(data.totalStackSats, -500);
        expect(data.monthStackChangeSats, -500);
        // Left out on purpose, not for want of a rate.
        expect(data.unconvertedCount, 0);
      },
    );

    test('analytics, the per-wallet breakdown and the export agree', () async {
      await add(db, sats: -10000, fiat: -10, ownTransfer: true);
      await add(db, sats: 20000, fiat: 20);
      final service = DashboardService(db);

      final analytics = await service.watchAnalytics(march).first;
      expect(analytics.ytdIncome, 20);
      expect(analytics.ytdSpending, 0);
      expect(analytics.spendingByCategory, isEmpty);

      final wallets = await service.watchPerWallet(march).first;
      expect(wallets.single.monthSpendFiat, 0);
      expect(wallets.single.monthIncomeFiat, 20);

      final csv = await service.exportMonthlySummary(
        month: march,
        currency: 'USD',
      );
      expect(csv, contains('TOTAL,0.00,0.00'));
    });

    test('a budget does not count it as spending', () async {
      final bitcoin =
          await (db.select(db.categories)
            ..where((c) => c.name.equals('Bitcoin'))).getSingle();
      await BudgetService(
        db,
      ).upsert(categoryId: bitcoin.id, amountFiat: 100, currency: 'USD');
      await add(db, sats: -10000, fiat: -30, ownTransfer: true);
      await add(db, sats: -10000, fiat: -20);

      final progress = await BudgetService(db).getProgress(march);
      expect(progress.single.spentFiat, 20);
    });
  });

  group('upgrading', () {
    late Directory dir;
    late File file;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('own_transfer');
      file = File('${dir.path}/db.sqlite');
    });
    tearDown(() => dir.delete(recursive: true));

    test('v11 rows come through as counted', () async {
      final v11 = AppDatabase.forTesting(NativeDatabase(file));
      await add(v11, sats: -10000, fiat: -10);
      await v11.customStatement(
        'ALTER TABLE transactions DROP COLUMN is_own_transfer',
      );
      await v11.customStatement('PRAGMA user_version = 11');
      await v11.close();

      final upgraded = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(upgraded.close);
      final row = await upgraded.select(upgraded.transactions).getSingle();
      expect(row.isOwnTransfer, isFalse);
    });

    // The v8 and v9 steps read whole rows, which map every column the
    // *current* schema has. Against a v7 database the v12 column is not there
    // yet, and being non-null it threw: anyone upgrading from v7 or v8 with an
    // xpub or a recurring row could not open the app.
    test('a v7 database with xpub and recurring rows upgrades', () async {
      final v7 = AppDatabase.forTesting(NativeDatabase(file));
      final wallet = (await v7.select(v7.wallets).getSingle()).id;
      await v7.customStatement('DROP INDEX idx_categories_name');
      for (final column in [
        'transactions DROP COLUMN recurring_series_id',
        'budgets DROP COLUMN currency',
        'transactions DROP COLUMN is_own_transfer',
      ]) {
        await v7.customStatement('ALTER TABLE $column');
      }
      final at = march.millisecondsSinceEpoch ~/ 1000;
      await v7.customStatement(
        'INSERT INTO transactions (wallet_id, date, description, '
        'amount_sats, amount_fiat, fiat_currency, source, is_bitcoin, '
        'dedup_hash, created_at, recurring_period, recurring_anchor_date) '
        "VALUES (?, ?, 'Rent', -1, -1200, 'USD', 'manual', 0, 'r', 0, "
        "'monthly', ?), "
        "(?, ?, 'Received', 5000, 5, 'USD', 'xpub', 1, 'x', 0, NULL, NULL)",
        [wallet, at, at, wallet, at],
      );
      await v7.customStatement('PRAGMA user_version = 7');
      await v7.close();

      final upgraded = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(upgraded.close);
      final rows = await upgraded.select(upgraded.transactions).get();
      final rent = rows.singleWhere((r) => r.description == 'Rent');
      final received = rows.singleWhere((r) => r.description == 'Received');
      expect(rent.recurringSeriesId, isNotNull);
      expect(received.dedupHash, isNot('x'));
      expect(rows.every((r) => !r.isOwnTransfer), isTrue);
    });
  });

  group('the edit sheet', () {
    setUp(() {
      app.db = AppDatabase.forTesting(NativeDatabase.memory());
      app.categoryService = CategoryService(app.db);
      app.transactionService = TransactionService(app.db);
      app.btcPriceService = BtcPriceService(app.db);
    });

    Future<void> open(WidgetTester tester, Transaction tx) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: TransactionEditSheet.forExisting(tx)),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    Future<Transaction> row(WidgetTester tester, {required bool btc}) async =>
        (await tester.runAsync(() async {
          final id = await add(
            app.db,
            sats: btc ? -10000 : 0,
            fiat: -10,
            isBitcoin: btc,
          );
          return (app.db.select(app.db.transactions)
            ..where((t) => t.id.equals(id))).getSingle();
        }))!;

    Future<void> teardown(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() => app.db.close());
    }

    testWidgets('a Bitcoin row can be marked, and it is saved', (tester) async {
      final tx = await row(tester, btc: true);
      await open(tester, tx);

      final box = find.text('Transfer between my own wallets');
      expect(box, findsOneWidget);
      await tester.tap(box);
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      final saved =
          (await tester.runAsync(
            () =>
                (app.db.select(app.db.transactions)
                  ..where((t) => t.id.equals(tx.id))).getSingle(),
          ))!;
      expect(saved.isOwnTransfer, isTrue);
      expect(saved.amountSats, tx.amountSats);
      await teardown(tester);
    });

    testWidgets('a fiat row has no such box', (tester) async {
      await open(tester, await row(tester, btc: false));
      expect(find.text('Transfer between my own wallets'), findsNothing);
      await teardown(tester);
    });
  });
}
