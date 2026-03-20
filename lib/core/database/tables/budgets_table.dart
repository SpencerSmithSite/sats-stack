import 'package:drift/drift.dart';
import 'categories_table.dart';

class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  RealColumn get amountFiat => real()();
  // 'monthly' | 'weekly' | 'yearly'
  TextColumn get period => text().withLength(min: 1, max: 10)();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}
