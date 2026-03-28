import 'package:intl/intl.dart';

import '../database/database.dart';
import '../models/analytics_data.dart';
import '../models/dashboard_data.dart';
import '../models/wallet_summary.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/utils/currency_utils.dart';

class DashboardService {
  DashboardService(this._db);

  final AppDatabase _db;

  /// Emits a fresh [DashboardData] whenever any transaction changes.
  /// The [month] parameter controls which month's aggregates are returned.
  Stream<DashboardData> watchDashboard(DateTime month,
      {double inflationRate = 3.5}) {
    return _db.select(_db.transactions).watch().asyncMap(
          (txns) => _compute(txns, month, inflationRate: inflationRate),
        );
  }

  /// Emits a per-wallet breakdown whenever any transaction changes.
  Stream<List<WalletSummary>> watchPerWallet(DateTime month) {
    return _db.select(_db.transactions).watch().asyncMap(
          (txns) => _computePerWallet(txns, month),
        );
  }

  Future<List<WalletSummary>> _computePerWallet(
    List<Transaction> allTxns,
    DateTime month,
  ) async {
    final wallets = await _db.select(_db.wallets).get();
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0, 23, 59, 59);

    final result = <WalletSummary>[];
    for (final wallet in wallets) {
      final walletTxns =
          allTxns.where((t) => t.walletId == wallet.id).toList();

      final totalSats = walletTxns
          .where((t) => t.isBitcoin)
          .fold(0, (s, t) => s + t.amountSats);

      final monthTxns = walletTxns
          .where((t) => !t.date.isBefore(firstDay) && !t.date.isAfter(lastDay))
          .toList();

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

      result.add(WalletSummary(
        wallet: wallet,
        totalSats: totalSats,
        monthChangeSats: monthChangeSats,
        monthIncomeFiat: monthIncome,
        monthSpendFiat: monthSpend,
        transactionCount: walletTxns.length,
      ));
    }

    return result;
  }

  Stream<AnalyticsData> watchAnalytics(DateTime selectedMonth) {
    return _db.select(_db.transactions).watch().asyncMap(
          (txns) => _computeAnalytics(txns, selectedMonth),
        );
  }

  Future<AnalyticsData> _computeAnalytics(
    List<Transaction> allTxns,
    DateTime selectedMonth,
  ) async {
    // ── Selected month breakdown ─────────────────────────────────────────────
    final firstDay =
        DateTime(selectedMonth.year, selectedMonth.month, 1);
    final lastDay =
        DateTime(selectedMonth.year, selectedMonth.month + 1, 0, 23, 59, 59);
    final monthTxns = allTxns
        .where((t) => !t.date.isBefore(firstDay) && !t.date.isAfter(lastDay))
        .toList();

    final byCategory = <String, double>{};
    for (final t in monthTxns.where((t) => t.amountFiat < 0)) {
      final cat = t.category ?? 'Other';
      byCategory[cat] = (byCategory[cat] ?? 0) + t.amountFiat.abs();
    }

    // ── Last 6 months totals ─────────────────────────────────────────────────
    final monthlyTotals = <MonthlyTotal>[];
    for (int i = 5; i >= 0; i--) {
      final m = DateTime(selectedMonth.year, selectedMonth.month - i, 1);
      final mFirst = DateTime(m.year, m.month, 1);
      final mLast = DateTime(m.year, m.month + 1, 0, 23, 59, 59);
      final mTxns = allTxns
          .where(
              (t) => !t.date.isBefore(mFirst) && !t.date.isAfter(mLast))
          .toList();

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
      monthlyTotals.add(MonthlyTotal(
        month: m,
        income: inc,
        spending: spend,
        byCategory: mByCategory,
      ));
    }

    // ── YTD ──────────────────────────────────────────────────────────────────
    final ytdFirst = DateTime(selectedMonth.year, 1, 1);
    final ytdLast = DateTime(selectedMonth.year, 12, 31, 23, 59, 59);
    final ytdTxns = allTxns
        .where((t) =>
            !t.date.isBefore(ytdFirst) && !t.date.isAfter(ytdLast))
        .toList();

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
    final txns = await _db.select(_db.transactions).get();
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
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
    final spentByCat = <String, double>{};
    for (final t in txns.where(
        (t) => !t.date.isBefore(firstDay) && !t.date.isAfter(lastDay) && t.amountFiat < 0)) {
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
      final sats = btcPrice != null && btcPrice > 0
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

    final totalPct =
        totalBudgeted > 0 ? totalSpent / totalBudgeted * 100 : 0.0;
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
    List<Transaction> allTxns,
    DateTime month, {
    double inflationRate = 3.5,
  }) async {
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0, 23, 59, 59);

    final monthTxns = allTxns
        .where((t) => !t.date.isBefore(firstDay) && !t.date.isAfter(lastDay))
        .toList();

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
    final leakRate = income > 0 ? (spending / income * 100).clamp(0.0, 100.0) : 0.0;
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

    final monthBtcTxns =
        monthTxns.where((t) => t.isBitcoin);
    final monthStackChange =
        monthBtcTxns.fold<int>(0, (s, t) => s + t.amountSats);

    // ── Recent transactions ──────────────────────────────────────────────────
    final sorted = List<Transaction>.from(allTxns)
      ..sort((a, b) => b.date.compareTo(a.date));
    final recent = sorted.take(5).toList();

    // ── Stack goal from settings ─────────────────────────────────────────────
    final goalEntry = await (_db.select(_db.appSettings)
          ..where((s) => s.key.equals(AppConstants.settingStackGoalSats)))
        .getSingleOrNull();
    final goalSats =
        goalEntry != null ? int.tryParse(goalEntry.value) : null;

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
    );
  }
}
