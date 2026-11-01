/// The dashboard, per-wallet and analytics figures, now read from a month's
/// rows and SQL sums rather than from every transaction ever recorded, still
/// come out exactly as a plain pass over every row computes them (audit D-2).
library;

import 'dart:math';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/fx_rates.dart';
import 'package:sats_stack/core/services/dashboard_service.dart';
import 'package:sats_stack/shared/utils/date_range.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const prices = {'USD': 100000.0, 'GBP': 80000.0, 'EUR': 90000.0};
  FxRates rates() => const FxRates(display: 'USD', btcPrices: prices);

  late AppDatabase db;
  late DashboardService service;
  late List<Transaction> all;
  final march = DateTime(2025, 3);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = DashboardService(db, rates: rates);
    final first = (await db.select(db.wallets).getSingle()).id;
    final second = await db
        .into(db.wallets)
        .insert(
          WalletsCompanion.insert(
            label: 'Cold',
            type: 'xpub',
            color: '#000000',
          ),
        );
    final rnd = Random(7);
    const currencies = ['USD', 'GBP', 'EUR'];
    const categories = ['Food & Dining', 'Transport', 'Housing', null];
    for (var i = 0; i < 400; i++) {
      final bitcoin = rnd.nextInt(4) == 0;
      // Mostly around March 2025, some in the months and years around it,
      // and several on the very same days so the recent list has ties.
      final date = DateTime(2024, 9 + rnd.nextInt(10), 1 + rnd.nextInt(28));
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              walletId: rnd.nextBool() ? first : second,
              date: date,
              description: 'row $i',
              amountSats: bitcoin ? rnd.nextInt(200000) - 80000 : 0,
              amountFiat: (rnd.nextInt(40000) - 25000) / 100,
              fiatCurrency: currencies[rnd.nextInt(3)],
              category: Value(categories[rnd.nextInt(4)]),
              source: 'manual',
              isBitcoin: Value(bitcoin),
              isOwnTransfer: Value(bitcoin && rnd.nextInt(5) == 0),
              dedupHash: 'h$i',
            ),
          );
    }
    all = await db.select(db.transactions).get();
  });

  tearDown(() => db.close());

  /// A row's fiat as every figure counts it: converted, and nothing for an
  /// own transfer.
  double fiat(Transaction t) =>
      t.isOwnTransfer ? 0 : rates().convert(t.amountFiat, t.fiatCurrency)!;

  test('the dashboard', () async {
    final data = await service.getDashboard(march);
    final month = all.where((t) => DateRange.month(march).contains(t.date));

    expect(
      data.monthlyIncomeFiat,
      closeTo(
        month.map(fiat).where((v) => v > 0).fold(0.0, (a, b) => a + b),
        1e-6,
      ),
    );
    expect(
      data.monthlySpendingFiat,
      closeTo(
        month.map(fiat).where((v) => v < 0).fold(0.0, (a, b) => a - b),
        1e-6,
      ),
    );
    expect(
      data.totalStackSats,
      all.where((t) => t.isBitcoin).fold(0, (a, t) => a + t.amountSats),
    );
    expect(
      data.monthStackChangeSats,
      month.where((t) => t.isBitcoin).fold(0, (a, t) => a + t.amountSats),
    );
    // Newest first; on the same date, in the order recorded.
    final sorted = List.of(all)..sort((a, b) => b.date.compareTo(a.date));
    expect(
      data.recentTransactions.map((t) => t.id),
      sorted.take(5).map((t) => t.id),
    );
  });

  test('the per-wallet breakdown', () async {
    final summaries = await service.watchPerWallet(march).first;
    for (final s in summaries) {
      final mine = all.where((t) => t.walletId == s.wallet.id);
      expect(s.transactionCount, mine.length);
      expect(
        s.totalSats,
        mine.where((t) => t.isBitcoin).fold(0, (a, t) => a + t.amountSats),
      );
      final month = mine.where((t) => DateRange.month(march).contains(t.date));
      expect(
        s.monthSpendFiat,
        closeTo(
          month.map(fiat).where((v) => v < 0).fold(0.0, (a, b) => a - b),
          1e-6,
        ),
      );
    }
  });

  test('analytics: the six months and the whole year', () async {
    final data = await service.watchAnalytics(march).first;
    final year = all.where((t) => DateRange.year(march).contains(t.date));
    expect(
      data.ytdSpending,
      closeTo(
        year.map(fiat).where((v) => v < 0).fold(0.0, (a, b) => a - b),
        1e-6,
      ),
    );
    expect(data.monthlyTotals, hasLength(6));
    for (final m in data.monthlyTotals) {
      final rows = all.where((t) => DateRange.month(m.month).contains(t.date));
      expect(
        m.income,
        closeTo(
          rows.map(fiat).where((v) => v > 0).fold(0.0, (a, b) => a + b),
          1e-6,
        ),
        reason: '${m.month}',
      );
    }
  });
}
