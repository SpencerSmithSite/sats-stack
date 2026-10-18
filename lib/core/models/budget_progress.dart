import '../database/database.dart';

class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.category,
    required this.spentFiat,
  });

  final Budget budget;
  final Category category;
  final double spentFiat;

  double get progress =>
      budget.amountFiat > 0 ? spentFiat / budget.amountFiat : 0.0;

  /// A budget of zero is not a budget the user can be over.
  ///
  /// Without the guard that [progress] already has, a category with no amount
  /// set reads as overspent the moment anything is spent in it, and the alert
  /// says "you've exceeded your $0 Food budget by $47".
  bool get isOverBudget =>
      budget.amountFiat > 0 && spentFiat > budget.amountFiat;

  double get remainingFiat => budget.amountFiat - spentFiat;
}
