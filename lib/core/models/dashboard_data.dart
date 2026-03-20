import '../database/database.dart';

class DashboardData {
  const DashboardData({
    required this.totalStackSats,
    required this.monthStackChangeSats,
    required this.monthlyIncomeFiat,
    required this.monthlySpendingFiat,
    required this.monthlySurplusFiat,
    required this.fiatLeakRate,
    required this.inflationCostFiat,
    required this.spendingByCategory,
    required this.recentTransactions,
    this.stackGoalSats,
  });

  /// Total sats held across all xpub wallets (isBitcoin = true).
  final int totalStackSats;

  /// Net sats change from Bitcoin transactions in the selected month.
  final int monthStackChangeSats;

  /// Sum of positive-fiat transactions in the selected month.
  final double monthlyIncomeFiat;

  /// Absolute sum of negative-fiat transactions in the selected month.
  final double monthlySpendingFiat;

  /// monthlyIncomeFiat - monthlySpendingFiat
  final double monthlySurplusFiat;

  /// spending / income × 100 (0–100). 0 if income is 0.
  final double fiatLeakRate;

  /// Estimated purchasing power lost per month (income × 3.5% ÷ 12).
  final double inflationCostFiat;

  /// category name → absolute fiat spent in the selected month.
  final Map<String, double> spendingByCategory;

  /// 5 most recent transactions across all sources.
  final List<Transaction> recentTransactions;

  /// User-configured stack goal in sats, or null if not set.
  final int? stackGoalSats;

  double get stackGoalProgress {
    if (stackGoalSats == null || stackGoalSats! <= 0) return 0;
    return (totalStackSats / stackGoalSats!).clamp(0.0, 1.0);
  }

  static const empty = DashboardData(
    totalStackSats: 0,
    monthStackChangeSats: 0,
    monthlyIncomeFiat: 0,
    monthlySpendingFiat: 0,
    monthlySurplusFiat: 0,
    fiatLeakRate: 0,
    inflationCostFiat: 0,
    spendingByCategory: {},
    recentTransactions: [],
    stackGoalSats: null,
  );
}
