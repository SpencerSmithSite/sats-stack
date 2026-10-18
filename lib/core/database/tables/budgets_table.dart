import 'package:drift/drift.dart';
import 'categories_table.dart';

/// One budget per category.
///
/// Without the unique index, `BudgetService.upsert` — a read-then-write with
/// no transaction — could be made to insert twice by double-tapping Save, and
/// every later upsert for that category then threw `StateError` out of
/// `getSingleOrNull`, so the budget could never be edited again.
@TableIndex(name: 'idx_budgets_category_id', columns: {#categoryId}, unique: true)
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  RealColumn get amountFiat => real()();
  // 'monthly' | 'weekly' | 'yearly'
  TextColumn get period => text().withLength(min: 1, max: 10)();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}
