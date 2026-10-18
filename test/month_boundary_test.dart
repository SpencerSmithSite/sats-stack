import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/budget_service.dart';
import 'package:sats_stack/core/services/dashboard_service.dart';
import 'package:sats_stack/shared/utils/date_range.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('DateRange', () {
    test('the last instant of a month belongs to that month', () {
      final march = DateRange.month(DateTime(2025, 3));

      // The old closed range ended at 23:59:59.000, so each of these fell
      // through the 999 ms gap between one month and the next.
      expect(march.contains(DateTime(2025, 3, 31, 23, 59, 59, 400)), isTrue);
      expect(march.contains(DateTime(2025, 3, 31, 23, 59, 59, 999)), isTrue);
      expect(march.contains(DateTime(2025, 3, 31, 23, 59, 59, 999, 999)),
          isTrue);
    });

    test('midnight on the 1st belongs to the new month, not the old', () {
      final march = DateRange.month(DateTime(2025, 3));
      final april = DateRange.month(DateTime(2025, 4));
      final boundary = DateTime(2025, 4, 1);

      expect(march.contains(boundary), isFalse);
      expect(april.contains(boundary), isTrue);
      expect(march.contains(DateTime(2025, 3, 1)), isTrue);
      expect(march.contains(DateTime(2025, 2, 28, 23, 59, 59, 999)), isFalse);
    });

    test('consecutive months tile the timeline with no gap', () {
      // Every millisecond in the two seconds either side of a month boundary
      // lands in exactly one of the two months — that window is where the old
      // closed range left its gap.
      final feb = DateRange.month(DateTime(2024, 2));
      final mar = DateRange.month(DateTime(2024, 3));
      var instant = DateTime(2024, 2, 29, 23, 59, 58);
      final stop = DateTime(2024, 3, 1, 0, 0, 2);
      while (instant.isBefore(stop)) {
        final inOne = (feb.contains(instant) ? 1 : 0) +
            (mar.contains(instant) ? 1 : 0);
        expect(inOne, 1, reason: 'no month claims $instant');
        instant = instant.add(const Duration(milliseconds: 1));
      }
    });

    test('December rolls into the next year', () {
      final dec = DateRange.month(DateTime(2025, 12));
      expect(dec.end, DateTime(2026, 1, 1));
      expect(dec.contains(DateTime(2025, 12, 31, 23, 59, 59, 999)), isTrue);
      expect(dec.contains(DateTime(2026, 1, 1)), isFalse);
    });

    test('a year range covers 31 December', () {
      final y = DateRange.year(DateTime(2025, 6));
      expect(y.contains(DateTime(2025, 12, 31, 23, 59, 59, 800)), isTrue);
      expect(y.contains(DateTime(2026, 1, 1)), isFalse);
      expect(y.contains(DateTime(2024, 12, 31, 23, 59, 59, 999)), isFalse);
    });
  });

  group('aggregates at the month boundary', () {
    late AppDatabase db;
    late DashboardService dashboard;
    late BudgetService budgets;
    late int walletId;
    late int foodId;

    // The instant that used to belong to no month at all. Reachable because
    // the add-transaction sheet seeds the date with DateTime.now().
    final lastInstant = DateTime(2025, 3, 31, 23, 59, 59, 400);

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dashboard = DashboardService(db);
      budgets = BudgetService(db);
      walletId = (await db.select(db.wallets).getSingle()).id;
      foodId = (await (db.select(db.categories)
                ..where((c) => c.name.equals('Food & Dining')))
              .getSingle())
          .id;

      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            walletId: walletId,
            date: lastInstant,
            description: 'Late dinner',
            amountSats: -600000,
            amountFiat: -47,
            fiatCurrency: 'USD',
            category: const Value('Food & Dining'),
            source: 'manual',
            dedupHash: 'late-dinner',
          ));
    });

    tearDown(() => db.close());

    test('the dashboard counts it in March', () async {
      final data = await dashboard.getDashboard(DateTime(2025, 3));
      expect(data.monthlySpendingFiat, 47);
      expect(data.spendingByCategory['Food & Dining'], 47);
    });

    test('and not in April', () async {
      final data = await dashboard.getDashboard(DateTime(2025, 4));
      expect(data.monthlySpendingFiat, 0);
    });

    test('the budget counts it against March', () async {
      await budgets.upsert(categoryId: foodId, amountFiat: 500);
      final progress = await budgets.getProgress(DateTime(2025, 3));
      expect(progress.single.spentFiat, 47);
    });

    test('the exported summary counts it', () async {
      final csv = await dashboard.exportMonthlySummary(
        month: DateTime(2025, 3),
        currency: 'USD',
      );
      expect(csv, contains('Food & Dining,0.00,47.00'));
    });

    test('analytics counts it in the month and the year', () async {
      final data = await dashboard.watchAnalytics(DateTime(2025, 3)).first;
      expect(data.spendingByCategory['Food & Dining'], 47);
      expect(data.ytdSpending, 47);
      expect(data.monthlyTotals.last.spending, 47);
    });

    test('the per-wallet breakdown counts it', () async {
      final summaries =
          await dashboard.watchPerWallet(DateTime(2025, 3)).first;
      expect(summaries.single.monthSpendFiat, 47);
    });
  });
}
