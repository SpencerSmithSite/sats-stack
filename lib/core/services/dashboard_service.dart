// Column operators and aggregates (`isBiggerOrEqualValue`, `sum`) are drift
// extensions, which a `show` clause would hide.
import 'package:drift/drift.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/app_constants.dart';
import '../../shared/utils/currency_utils.dart';
import '../../shared/utils/date_range.dart';
import '../database/database.dart';
import '../models/analytics_data.dart';
import '../models/dashboard_data.dart';
import '../models/fx_rates.dart';
import '../models/wallet_summary.dart';

class DashboardService {
  /// [rates] supplies the display currency and today's BTC prices. Read at
  /// compute time, so a currency switch takes effect on the next recompute
  /// without the service having to be rebuilt. Without it every amount passes
  /// through unconverted — what tests constructing the service directly get.
  DashboardService(this._db, {FxRates Function()? rates})
    : _rates = rates ?? _noConversion;

  final AppDatabase _db;
  final FxRates Function() _rates;

  static FxRates _noConversion() => const FxRates.passthrough();

  /// [txns] with `amountFiat` restated in the display currency, for
  /// aggregation only, and how many rows had no rate.
  ///
  /// Every aggregate below reads from this, so they all agree, and none of
  /// them sums across currencies any more — which every one of them used to.
  ///
  /// A row that cannot be converted keeps its sats and gets a fiat value of
  /// zero, so it drops out of the income/spending sums without dropping out of
  /// the stack total: sats need no conversion and must not be lost because a
  /// fiat rate is. The count lets the screen say a total is incomplete rather
  /// than quietly showing a smaller number.
  ///
  /// A row the user marked as a transfer between their own wallets is zeroed
  /// the same way, on purpose rather than for want of a rate, so it is not
  /// counted as unconverted.
  ({List<Transaction> rows, Set<int> unconverted}) _restate(
    List<Transaction> txns,
  ) {
    final fx = _rates();
    final unconverted = <int>{};
    final rows = [
      for (final t in txns)
        if (t.isOwnTransfer)
          t.copyWith(amountFiat: 0)
        else
          switch (fx.convert(t.amountFiat, t.fiatCurrency)) {
            null => () {
              unconverted.add(t.id);
              return t.copyWith(amountFiat: 0);
            }(),
            final v when v == t.amountFiat => t,
            final v => t.copyWith(amountFiat: v),
          },
    ];
    return (rows: rows, unconverted: unconverted);
  }

  /// Emits once, then whenever any of [tables] changes.
  ///
  /// `select(...).watch()` only tracks the table it selects from, which is not
  /// the same set a computed aggregate reads.
  Stream<void> _changesTo(
    Set<ResultSetImplementation<dynamic, dynamic>> tables,
  ) => _db.customSelect('SELECT 1', readsFrom: tables).watch();

  // ── Targeted reads ─────────────────────────────────────────────────────────
  //
  // Every figure here used to be computed from every transaction ever
  // recorded — read, mapped and restated on the UI isolate — on every change,
  // twice over for the dashboard and its per-wallet breakdown, and again
  // every ten minutes when the price service wrote its cache (audit D-2).
  // Each now reads what it shows: a date range through the v7 index, or a sum
  // sqlite works out without handing over the rows.

  /// The rows dated within [range].
  Future<List<Transaction>> _rowsIn(DateRange range) =>
      (_db.select(_db.transactions)..where(
        (t) =>
            t.date.isBiggerOrEqualValue(range.start) &
            t.date.isSmallerThanValue(range.end),
      )).get();

  /// Every Bitcoin row's sats added up, per wallet.
  Future<Map<int, int>> _stackSatsByWallet() async {
    final t = _db.transactions;
    final sats = t.amountSats.sum();
    final rows =
        await (_db.selectOnly(t)
              ..addColumns([t.walletId, sats])
              ..where(t.isBitcoin.equals(true))
              ..groupBy([t.walletId]))
            .get();
    return {for (final r in rows) r.read(t.walletId)!: r.read(sats) ?? 0};
  }

  /// How many rows each wallet holds.
  Future<Map<int, int>> _rowCountByWallet() async {
    final t = _db.transactions;
    final count = t.id.count();
    final rows =
        await (_db.selectOnly(t)
              ..addColumns([t.walletId, count])
              ..groupBy([t.walletId]))
            .get();
    return {for (final r in rows) r.read(t.walletId)!: r.read(count) ?? 0};
  }

  /// Emits a fresh [DashboardData] whenever anything it reads changes.
  /// The [month] parameter controls which month's aggregates are returned.
  ///
  /// `appSettings` is in the set because [_compute] reads the stack goal from
  /// it. Watching only `transactions` was masked for as long as the widget
  /// tree rebuilt this stream on every frame; with the stream built once, a
  /// change to the goal would otherwise never reach the card.
  Stream<DashboardData> watchDashboard(
    DateTime month, {
    double inflationRate = 3.5,
  }) {
    return _changesTo({
      _db.transactions,
      _db.appSettings,
    }).asyncMap((_) => _compute(month, inflationRate: inflationRate));
  }

  /// Emits a per-wallet breakdown whenever a transaction or a wallet changes.
  Stream<List<WalletSummary>> watchPerWallet(DateTime month) {
    return _changesTo({
      _db.transactions,
      _db.wallets,
    }).asyncMap((_) => _computePerWallet(month));
  }

  Future<List<WalletSummary>> _computePerWallet(DateTime month) async {
    final wallets = await _db.select(_db.wallets).get();
    final stackSats = await _stackSatsByWallet();
    final rowCounts = await _rowCountByWallet();

    // The month's rows, grouped in one pass.
    final byWallet = <int, List<Transaction>>{};
    for (final t in _restate(await _rowsIn(DateRange.month(month))).rows) {
      (byWallet[t.walletId] ??= <Transaction>[]).add(t);
    }

    final result = <WalletSummary>[];
    for (final wallet in wallets) {
      final totalSats = stackSats[wallet.id] ?? 0;
      final monthTxns = byWallet[wallet.id] ?? const <Transaction>[];

      final monthChangeSats = monthTxns
          .where((t) => t.isBitcoin)
          .fold(0, (s, t) => s + t.amountSats);

      double monthIncome = 0, monthSpend = 0;
      for (final t in monthTxns) {
        if (t.amountFiat > 0) {
          monthIncome += t.amountFiat;
        } else {
          monthSpend += t.amountFiat.abs();
        }
      }

      result.add(
        WalletSummary(
          wallet: wallet,
          totalSats: totalSats,
          monthChangeSats: monthChangeSats,
          monthIncomeFiat: monthIncome,
          monthSpendFiat: monthSpend,
          transactionCount: rowCounts[wallet.id] ?? 0,
        ),
      );
    }

    return result;
  }

  Stream<AnalyticsData> watchAnalytics(DateTime selectedMonth) {
    return _changesTo({
      _db.transactions,
    }).asyncMap((_) => _computeAnalytics(selectedMonth));
  }

  Future<AnalyticsData> _computeAnalytics(DateTime selectedMonth) async {
    // Everything shown is within the six months to the selected one, or its
    // calendar year, so only those rows are read.
    final sixMonthsBack = DateTime(
      selectedMonth.year,
      selectedMonth.month - 5,
      1,
    );
    final yearStart = DateTime(selectedMonth.year, 1, 1);
    final allTxns =
        _restate(
          await _rowsIn(
            DateRange(
              sixMonthsBack.isBefore(yearStart) ? sixMonthsBack : yearStart,
              // "YTD" here is the whole calendar year, as it always was.
              DateRange.year(selectedMonth).end,
            ),
          ),
        ).rows;
    // ── Selected month breakdown ─────────────────────────────────────────────
    final range = DateRange.month(selectedMonth);
    final monthTxns = allTxns.where((t) => range.contains(t.date)).toList();

    final byCategory = <String, double>{};
    for (final t in monthTxns.where((t) => t.amountFiat < 0)) {
      final cat = t.category ?? 'Other';
      byCategory[cat] = (byCategory[cat] ?? 0) + t.amountFiat.abs();
    }

    // ── Last 6 months totals ─────────────────────────────────────────────────
    final monthlyTotals = <MonthlyTotal>[];
    for (int i = 5; i >= 0; i--) {
      final m = DateTime(selectedMonth.year, selectedMonth.month - i, 1);
      final mRange = DateRange.month(m);
      final mTxns = allTxns.where((t) => mRange.contains(t.date)).toList();

      double inc = 0, spend = 0;
      final mByCategory = <String, double>{};
      for (final t in mTxns) {
        if (t.amountFiat > 0) {
          inc += t.amountFiat;
        } else {
          spend += t.amountFiat.abs();
          final cat = t.category ?? 'Other';
          mByCategory[cat] = (mByCategory[cat] ?? 0) + t.amountFiat.abs();
        }
      }
      monthlyTotals.add(
        MonthlyTotal(
          month: m,
          income: inc,
          spending: spend,
          byCategory: mByCategory,
        ),
      );
    }

    // ── YTD ──────────────────────────────────────────────────────────────────
    final ytdRange = DateRange.year(selectedMonth);
    final ytdTxns = allTxns.where((t) => ytdRange.contains(t.date)).toList();

    double ytdInc = 0, ytdSpend = 0;
    for (final t in ytdTxns) {
      if (t.amountFiat > 0) {
        ytdInc += t.amountFiat;
      } else {
        ytdSpend += t.amountFiat.abs();
      }
    }

    return AnalyticsData(
      selectedMonth: selectedMonth,
      spendingByCategory: byCategory,
      monthlyTotals: monthlyTotals,
      ytdIncome: ytdInc,
      ytdSpending: ytdSpend,
    );
  }

  /// Builds a human-readable CSV for [month] containing per-category spending
  /// vs budget, utilisation %, and sats opportunity cost.
  Future<String> exportMonthlySummary({
    required DateTime month,
    required String currency,
    double? btcPrice,
  }) async {
    final txns = _restate(await _rowsIn(DateRange.month(month))).rows;
    final budgets = await _db.select(_db.budgets).get();
    final categories = await _db.select(_db.categories).get();

    final catById = {for (final c in categories) c.id: c};

    // Budget amount per category name (monthly equivalent)
    final budgetByCat = <String, double>{};
    for (final b in budgets) {
      final cat = catById[b.categoryId];
      final limit = _rates().convert(b.amountFiat, b.currency);
      if (cat != null && limit != null) budgetByCat[cat.name] = limit;
    }

    // Spending per category for the selected month
    final range = DateRange.month(month);
    final spentByCat = <String, double>{};
    for (final t in txns.where(
      (t) => range.contains(t.date) && t.amountFiat < 0,
    )) {
      final cat = t.category ?? 'Other';
      spentByCat[cat] = (spentByCat[cat] ?? 0) + t.amountFiat.abs();
    }

    final allCats = {...spentByCat.keys, ...budgetByCat.keys}.toList()..sort();

    final sym = CurrencyUtils.symbolFor(currency);
    final monthLabel = DateFormat('MMMM yyyy').format(month);
    final rows = <String>[
      'Sats Stack — Monthly Spending Summary',
      'Month: $monthLabel',
      'Currency: $currency',
      '',
      'Category,Budgeted ($sym),Spent ($sym),Utilisation (%),Sats Opp. Cost',
    ];

    double totalBudgeted = 0;
    double totalSpent = 0;
    int totalSats = 0;

    for (final cat in allCats) {
      final budgeted = budgetByCat[cat] ?? 0;
      final spent = spentByCat[cat] ?? 0;
      final pct = budgeted > 0 ? spent / budgeted * 100 : 0.0;
      final sats =
          btcPrice != null && btcPrice > 0
              ? (spent / btcPrice * 100000000).round()
              : 0;
      rows.add(
        '$cat,'
        '${budgeted.toStringAsFixed(2)},'
        '${spent.toStringAsFixed(2)},'
        '${pct.toStringAsFixed(0)}%,'
        '$sats',
      );
      totalBudgeted += budgeted;
      totalSpent += spent;
      totalSats += sats;
    }

    final totalPct = totalBudgeted > 0 ? totalSpent / totalBudgeted * 100 : 0.0;
    rows
      ..add('')
      ..add(
        'TOTAL,'
        '${totalBudgeted.toStringAsFixed(2)},'
        '${totalSpent.toStringAsFixed(2)},'
        '${totalPct.toStringAsFixed(0)}%,'
        '$totalSats',
      );

    return rows.join('\n');
  }

  Future<DashboardData> getDashboard(DateTime month) => _compute(month);

  // ── Private ────────────────────────────────────────────────────────────────

  Future<DashboardData> _compute(
    DateTime month, {
    double inflationRate = 3.5,
  }) async {
    final restated = _restate(await _rowsIn(DateRange.month(month)));
    final monthTxns = restated.rows;

    // ── Fiat aggregates ──────────────────────────────────────────────────────
    double income = 0;
    double spending = 0;
    for (final t in monthTxns) {
      if (t.amountFiat > 0) {
        income += t.amountFiat;
      } else {
        spending += t.amountFiat.abs();
      }
    }

    final surplus = income - spending;
    final leakRate =
        income > 0 ? (spending / income * 100).clamp(0.0, 100.0) : 0.0;
    final annualInflationRate = inflationRate / 100;
    final inflationCost = income * annualInflationRate / 12;

    // ── Spending by category (this month's expenses only) ───────────────────
    final byCategory = <String, double>{};
    for (final t in monthTxns.where((t) => t.amountFiat < 0)) {
      final cat = t.category ?? 'Other';
      byCategory[cat] = (byCategory[cat] ?? 0) + t.amountFiat.abs();
    }

    // ── Bitcoin stack ────────────────────────────────────────────────────────
    final totalStackSats = (await _stackSatsByWallet()).values.fold<int>(
      0,
      (s, v) => s + v,
    );

    final monthBtcTxns = monthTxns.where((t) => t.isBitcoin);
    final monthStackChange = monthBtcTxns.fold<int>(
      0,
      (s, t) => s + t.amountSats,
    );

    // ── Recent transactions ──────────────────────────────────────────────────
    // From the originals, not the restated rows: these are rendered with each
    // row's own currency label, so a $50 charge must still read $50 — a
    // converted figure under the original label would be a new version of the
    // same bug.
    // Newest first; on the same date, in the order they were recorded.
    final recent =
        await (_db.select(_db.transactions)
              ..orderBy([
                (t) => OrderingTerm.desc(t.date),
                (t) => OrderingTerm.asc(t.id),
              ])
              ..limit(5))
            .get();

    // ── Stack goal from settings ─────────────────────────────────────────────
    final goalEntry =
        await (_db.select(_db.appSettings)..where(
          (s) => s.key.equals(AppConstants.settingStackGoalSats),
        )).getSingleOrNull();
    final goalSats = goalEntry != null ? int.tryParse(goalEntry.value) : null;

    return DashboardData(
      totalStackSats: totalStackSats,
      monthStackChangeSats: monthStackChange,
      monthlyIncomeFiat: income,
      monthlySpendingFiat: spending,
      monthlySurplusFiat: surplus,
      fiatLeakRate: leakRate,
      inflationCostFiat: inflationCost,
      spendingByCategory: byCategory,
      recentTransactions: recent,
      stackGoalSats: goalSats,
      // This month's, which is what the totals beside it cover. It counted
      // every row ever recorded, so one old foreign-currency import kept the
      // note up on every month.
      unconvertedCount:
          monthTxns.where((t) => restated.unconverted.contains(t.id)).length,
    );
  }
}
