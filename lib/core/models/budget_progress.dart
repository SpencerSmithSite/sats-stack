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
  bool get isOverBudget {
    final limit = limitFiat;
    return limit != null && limit > 0 && spentFiat > limit;
  }

  double? get remainingFiat {
    final limit = limitFiat;
    return limit == null ? null : limit - spentFiat;
  }
}
