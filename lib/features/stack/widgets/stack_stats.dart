/// The Stack screen's aggregates, computed in one pass.
library;

import '../../../core/database/database.dart';

/// Everything the Stack screen derives from the transaction list.
///
/// One walk over the rows, done when they change. These were four getters on
/// the content widget, each its own walk, re-run on every rebuild — and the
/// content rebuilds on every BTC price tick.
class StackStats {
  const StackStats({
    required this.totalSats,
    required this.monthSats,
    required this.avgMonthlySats,
    required this.history,
    required this.month,
  });

  factory StackStats.from(List<Transaction> txns, DateTime now) {
    final currentMonth = DateTime(now.year, now.month);
    var total = 0;
    var thisMonth = 0;
    final byMonth = <DateTime, int>{};
    for (final t in txns) {
      if (!t.isBitcoin) continue;
      total += t.amountSats;
      final m = DateTime(t.date.year, t.date.month);
      byMonth[m] = (byMonth[m] ?? 0) + t.amountSats;
      if (!t.date.isBefore(currentMonth)) thisMonth += t.amountSats;
    }

    // Average over complete calendar months only, so the current partial
    // month does not drag it down mid-month.
    final complete = [
      for (final e in byMonth.entries)
        if (e.key.isBefore(currentMonth)) e.value,
    ];
    final avg =
        complete.isEmpty
            ? 0
            : (complete.fold(0, (s, v) => s + v) / complete.length).round();

    // Cumulative balance at the end of each month with activity.
    final sorted = byMonth.keys.toList()..sort();
    var cumulative = 0;
    final history = <DateTime, int>{
      for (final m in sorted) m: cumulative += byMonth[m]!,
    };

    return StackStats(
      totalSats: total,
      monthSats: thisMonth,
      avgMonthlySats: avg,
      history: history,
      month: currentMonth,
    );
  }

  final int totalSats;

  /// Net sats since the start of [month].
  final int monthSats;

  /// Mean net sats per complete calendar month before [month].
  final int avgMonthlySats;

  /// Month → cumulative sats at its end, oldest first.
  final Map<DateTime, int> history;

  /// The calendar month "this month" was computed for.
  final DateTime month;

  bool get hasBitcoin => history.isNotEmpty;

  /// Whether these stats are still current at [now].
  bool isFor(DateTime now) =>
      month.year == now.year && month.month == now.month;
}
