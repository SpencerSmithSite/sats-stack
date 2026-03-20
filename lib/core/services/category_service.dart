import 'package:drift/drift.dart';
import '../database/database.dart';

class CategoryService {
  CategoryService(this._db);

  final AppDatabase _db;

  Stream<List<Category>> watchAll() {
    return (_db.select(_db.categories)
          ..orderBy([
            // System categories first, then custom alphabetically
            (t) => OrderingTerm.asc(t.isSystem),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .watch();
  }

  Future<List<Category>> getAll() {
    return _db.select(_db.categories).get();
  }

  Future<void> createCategory({
    required String name,
    required String color,
    required String icon,
  }) {
    return _db.into(_db.categories).insert(
          CategoriesCompanion.insert(
            name: name,
            color: color,
            icon: icon,
          ),
        );
  }

  Future<void> updateCategory({
    required int id,
    required String name,
    required String color,
    required String icon,
  }) {
    return (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
          CategoriesCompanion(
            name: Value(name),
            color: Value(color),
            icon: Value(icon),
          ),
        );
  }

  /// Returns the number of transactions and budgets referencing this category.
  /// Call before delete to check if safe.
  Future<({int transactions, int budgets})> usageCounts(
      int categoryId, String categoryName) async {
    final txCount = await (_db.select(_db.transactions)
          ..where((t) => t.category.equals(categoryName)))
        .get()
        .then((l) => l.length);
    final budgetCount = await (_db.select(_db.budgets)
          ..where((b) => b.categoryId.equals(categoryId)))
        .get()
        .then((l) => l.length);
    return (transactions: txCount, budgets: budgetCount);
  }

  /// Deletes a custom category. Returns false if it is still referenced by
  /// transactions or budgets (caller should show a warning instead).
  Future<bool> deleteCategory(int categoryId, String categoryName) async {
    final counts = await usageCounts(categoryId, categoryName);
    if (counts.transactions > 0 || counts.budgets > 0) return false;
    await (_db.delete(_db.categories)
          ..where((t) => t.id.equals(categoryId)))
        .go();
    return true;
  }
}
