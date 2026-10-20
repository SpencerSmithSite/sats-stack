import 'package:drift/drift.dart';

/// Category names are unique.
///
/// Transactions, budgets' progress, imported rows and learned mappings all
/// refer to a category by *name*, so two categories sharing one were
/// indistinguishable everywhere that mattered: a rename of either rewrote the
/// transactions of both, one of the pair read zero spend forever, and neither
/// could be deleted because the other's transactions counted against it.
@TableIndex(name: 'idx_categories_name', columns: {#name}, unique: true)
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  // hex color string e.g. '#F7931A'
  TextColumn get color => text().withLength(min: 7, max: 7)();
  // Material icon name e.g. 'restaurant'
  TextColumn get icon => text().withLength(min: 1, max: 50)();
  BoolColumn get isSystem =>
      boolean().withDefault(const Constant(false))();
}
