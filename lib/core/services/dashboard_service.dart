import 'package:drift/drift.dart' show ResultSetImplementation;
import 'package:intl/intl.dart';

import '../database/database.dart';
import '../models/analytics_data.dart';
import '../models/dashboard_data.dart';
import '../models/fx_rates.dart';
import '../models/wallet_summary.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/utils/currency_utils.dart';
import '../../shared/utils/date_range.dart';

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
  ({List<Transaction> rows, int unconverted}) _restate(List<Transaction> txns) {
    final fx = _rates();
    var unconverted = 0;
    final rows = [
      for (final t in txns)
        switch (fx.convert(t.amountFiat, t.fiatCurrency)) {
          null => () {
            unconverted++;
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
    return _changesTo({_db.transactions, _db.appSettings}).asyncMap((_) async {
      final txns = await _db.select(_db.transactions).get();
      return _compute(txns, month, inflationRate: inflationRate);
    });
  }

  /// Emits a per-wallet breakdown whenever a transaction or a wallet changes.
  Stream<List<WalletSummary>> watchPerWallet(DateTime month) {
    return _changesTo({_db.transactions, _db.wallets}).asyncMap((_) async {
      final txns = await _db.select(_db.transactions).get();
      return _computePerWallet(txns, month);
    });
  }

  Future<List<WalletSummary>> _computePerWallet(
    List<Transaction> originalTxns,
    DateTime month,
  ) async {
    final allTxns = _restate(originalTxns).rows;
    final wallets = await _db.select(_db.wallets).get();
    final range = DateRange.month(month);

    // Grouped in one pass. Filtering `allTxns` inside the wallet loop made
    // this O(wallets × transactions), re-walking the whole history once per
    // wallet on every change — on the UI isolate.
    final byWallet = <int, List<Transaction>>{};
    for (final t in allTxns) {
      (byWallet[t.walletId] ??= <Transaction>[]).add(t);
    }

    final result = <WalletSummary>[];
    for (final wallet in wallets) {
      final walletTxns = byWallet[wallet.id] ?? const <Transaction>[];

      final totalSats = walletTxns
          .where((t) => t.isBitcoin)
          .fold(0, (s, t) => s + t.amountSats);

      final monthTxns =
          walletTxns.where((t) => range.contains(t.date)).toList();

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
          transactionCount: walletTxns.length,
        ),
      );
    }

    return result;
  }

  Stream<AnalyticsData> watchAnalytics(DateTime selectedMonth) {
    return _db
        .select(_db.transactions)
        .watch()
        .asyncMap((txns) => _computeAnalytics(txns, selectedMonth));
  }

  Future<AnalyticsData> _computeAnalytics(
    List<Transaction> originalTxns,
    DateTime selectedMonth,
  ) async {
    final allTxns = _restate(originalTxns).rows;
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
    final txns = _restate(await _db.select(_db.transactions).get()).rows;
    final budgets = await _db.select(_db.budgets).get();
    final categories = await _db.select(_db.categories).get();

    final catById = {for (final c in categories) c.id: c};

    // Budget amount per category name (monthly equivalent)
    final budgetByCat = <String, double>{};
    for (final b in budgets) {
      final cat = catById[b.categoryId];
      if (cat != null) budgetByCat[cat.name] = b.amountFiat;
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

  Future<DashboardData> getDashboard(DateTime month) async {
    final txns = await _db.select(_db.transactions).get();
    return _compute(txns, month);
  }

  // ── Private ────────────────────────────────────────────────────────────────

  Future<DashboardData> _compute(
    List<Transaction> originalTxns,
    DateTime month, {
    double inflationRate = 3.5,
  }) async {
    final range = DateRange.month(month);
    final restated = _restate(originalTxns);
    final allTxns = restated.rows;

    final monthTxns = allTxns.where((t) => range.contains(t.date)).toList();

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
    final btcTxns = allTxns.where((t) => t.isBitcoin);
    final totalStackSats = btcTxns.fold<int>(0, (s, t) => s + t.amountSats);

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
    final sorted = List<Transaction>.from(originalTxns)
      ..sort((a, b) => b.date.compareTo(a.date));
    final recent = sorted.take(5).toList();

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
      unconvertedCount: restated.unconverted,
    );
  }
}
