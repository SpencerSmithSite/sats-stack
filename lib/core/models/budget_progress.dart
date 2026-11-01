import '../database/database.dart';

class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.category,
    required this.spentFiat,
    required this.limitFiat,
  });

  final Budget budget;
  final Category category;

  /// This month's spending in the category, in the display currency.
  final double spentFiat;

  /// The budget, in the display currency — or null when it is set in another
  /// currency and there is no rate to convert it with.
  ///
  /// Read this, never `budget.amountFiat`: that is in `budget.currency`, and
  /// comparing it with [spentFiat] directly is how switching currency used to
  /// turn a £500 budget into a $500 one.
  final double? limitFiat;

  double get progress {
    final limit = limitFiat;
    return limit != null && limit > 0 ? spentFiat / limit : 0.0;
  }

  /// A budget of zero is not a budget the user can be over, and nor is one
  /// that cannot be converted: claiming an overspend from a guess is how a
  /// currency switch fired a false alert.
  ///
  /// Without the zero guard, a category with no amount set reads as overspent
  /// the moment anything is spent in it, and the alert says "you've exceeded
  /// your $0 Food budget by $47".
  ///
  /// Compared in whole cents. Spending is a running sum of doubles, and
  /// cent amounts that add up to exactly the budget often sum a hair over it
  /// (`143.92000000000002 > 143.92`): the card went red and an "exceeded by
  /// $0" alert used up that month's one alert (audit D-6).
  bool get isOverBudget {
    final limit = limitFiat;
    return limit != null && limit > 0 && _cents(spentFiat) > _cents(limit);
  }

  static int _cents(double amount) => (amount * 100).round();

  double? get remainingFiat {
    final limit = limitFiat;
    return limit == null ? null : limit - spentFiat;
  }
}
