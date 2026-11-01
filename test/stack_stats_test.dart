/// The Stack screen's aggregates, now computed once per change of data
/// rather than on every BTC price tick.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/features/stack/widgets/stack_stats.dart';

void main() {
  var id = 0;
  Transaction tx(DateTime date, int sats, {bool btc = true}) => Transaction(
    id: id++,
    walletId: 1,
    date: date,
    description: 'row',
    amountSats: sats,
    amountFiat: 0,
    fiatCurrency: 'USD',
    source: 'manual',
    isBitcoin: btc,
    isOwnTransfer: false,
    dedupHash: 'h$id',
    createdAt: date,
  );

  final now = DateTime(2026, 10, 20);
  final txns = [
    tx(DateTime(2026, 8, 3), 100000),
    tx(DateTime(2026, 8, 20), 50000),
    tx(DateTime(2026, 9, 1), 30000),
    tx(DateTime(2026, 10, 2), 20000),
    tx(DateTime(2026, 10, 9), -5000), // spent some
    tx(DateTime(2026, 10, 10), -999999, btc: false), // a fiat row, ignored
  ];

  test('totals only Bitcoin rows', () {
    final s = StackStats.from(txns, now);
    expect(s.totalSats, 195000);
    expect(s.monthSats, 15000);
    expect(s.hasBitcoin, isTrue);
  });

  test('averages complete months only', () {
    // August 150k and September 30k; October is still in progress.
    expect(StackStats.from(txns, now).avgMonthlySats, 90000);
  });

  test('idle months count, so the goal date is not optimistic', () {
    // 120k in January and nothing since: over January–September that is
    // 120k / 9, not 120k / 1.
    final s = StackStats.from([tx(DateTime(2026, 1, 5), 120000)], now);
    expect(s.avgMonthlySats, (120000 / 9).round());
  });

  test('the average looks back a year at most', () {
    // A burst three years ago and steady 10k for the last twelve months.
    final s = StackStats.from([
      tx(DateTime(2023, 3, 1), 5000000),
      for (var m = 1; m <= 12; m++) tx(DateTime(2025, 9 + m, 1), 10000),
    ], now);
    expect(s.avgMonthlySats, 10000);
  });

  test('history is cumulative and in order', () {
    expect(StackStats.from(txns, now).history, {
      DateTime(2026, 7): 0,
      DateTime(2026, 8): 150000,
      DateTime(2026, 9): 180000,
      DateTime(2026, 10): 195000,
    });
  });

  test('every month is in the history, idle ones at the balance', () {
    // Audit U-10: only months with activity were there, so a two-year gap
    // was one step on the chart.
    final s = StackStats.from([
      tx(DateTime(2024, 9, 1), 100000),
      tx(DateTime(2026, 9, 1), 50000),
    ], now);
    expect(s.history.length, 27); // August 2024 to October 2026
    expect(s.history[DateTime(2024, 8)], 0);
    expect(s.history[DateTime(2025, 9)], 100000);
    expect(s.history[DateTime(2026, 8)], 100000);
    expect(s.history[DateTime(2026, 10)], 150000);
  });

  test('a stack that sat still still has a line to draw', () {
    // Nothing for a year: the last three months are the carried balance.
    // The 3M window found no months at all, and showed "Not enough data".
    final s = StackStats.from([tx(DateTime(2025, 6, 1), 80000)], now);
    final lastThree = s.history.entries.where(
      (e) => !e.key.isBefore(DateTime(2026, 8)),
    );
    expect(lastThree.map((e) => e.value), [80000, 80000, 80000]);
  });

  test('knows when the month has turned under it', () {
    final s = StackStats.from(txns, now);
    expect(s.isFor(DateTime(2026, 10, 31, 23, 59)), isTrue);
    expect(s.isFor(DateTime(2026, 11, 1)), isFalse);
  });

  test('no Bitcoin rows means nothing to show', () {
    final s = StackStats.from([tx(now, -100, btc: false)], now);
    expect(s.hasBitcoin, isFalse);
    expect(s.totalSats, 0);
    expect(s.avgMonthlySats, 0);
  });
}
