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

  test('history is cumulative and in order', () {
    expect(StackStats.from(txns, now).history, {
      DateTime(2026, 8): 150000,
      DateTime(2026, 9): 180000,
      DateTime(2026, 10): 195000,
    });
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
