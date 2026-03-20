class MonthlyTotal {
  const MonthlyTotal({
    required this.month,
    required this.income,
    required this.spending,
    required this.byCategory,
  });

  final DateTime month;
  final double income;
  final double spending;
  final Map<String, double> byCategory;

  double get surplus => income - spending;
}

class AnalyticsData {
  const AnalyticsData({
    required this.selectedMonth,
    required this.spendingByCategory,
    required this.monthlyTotals,
    required this.ytdIncome,
    required this.ytdSpending,
  });

  /// Spending breakdown for [selectedMonth].
  final DateTime selectedMonth;
  final Map<String, double> spendingByCategory;

  /// Last 6 months in chronological order (oldest → newest).
  final List<MonthlyTotal> monthlyTotals;

  final double ytdIncome;
  final double ytdSpending;

  double get ytdSurplus => ytdIncome - ytdSpending;

  static final empty = AnalyticsData(
    selectedMonth: DateTime.now(),
    spendingByCategory: {},
    monthlyTotals: [],
    ytdIncome: 0,
    ytdSpending: 0,
  );
}
