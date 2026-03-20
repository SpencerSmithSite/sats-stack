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

  bool get isOverBudget => spentFiat > budget.amountFiat;

  double get remainingFiat => budget.amountFiat - spentFiat;
}
