import 'package:drift/drift.dart';
import '../../shared/constants/app_constants.dart';
import '../database/database.dart';

/// A category with this name already exists.
///
/// Names are the key that transactions, budgets and imports use, so they must
/// be unique — see the index on `Categories`.
class DuplicateCategoryNameException implements Exception {
  const DuplicateCategoryNameException(this.name);
  final String name;

  @override
  String toString() => 'A category called "$name" already exists';
}

class CategoryService {
  CategoryService(this._db);

  final AppDatabase _db;

  Stream<List<Category>> watchAll() {
    return (_db.select(_db.categories)..orderBy([
      // System categories first, then custom alphabetically
      (t) => OrderingTerm.asc(t.isSystem),
      (t) => OrderingTerm.asc(t.name),
    ])).watch();
  }

  Future<List<Category>> getAll() {
    return _db.select(_db.categories).get();
  }

  /// Throws [DuplicateCategoryNameException] if [name] is taken by another
  /// category than [exceptId].
  ///
  /// Case-insensitive, which is stricter than the index: "Food" and "food"
  /// would be two keys to the database but one to anybody reading the list.
  Future<void> _checkNameFree(String name, {int? exceptId}) async {
    final lower = name.toLowerCase();
    final clash = (await getAll()).any(
      (c) => c.id != exceptId && c.name.toLowerCase() == lower,
    );
    if (clash) throw DuplicateCategoryNameException(name);
  }

  Future<void> createCategory({
    required String name,
    required String color,
    required String icon,
  }) async {
    await _checkNameFree(name);
    await _db
        .into(_db.categories)
        .insert(
          CategoriesCompanion.insert(name: name, color: color, icon: icon),
        );
  }

  /// Renames or restyles a category, carrying every row that referred to it
  /// by name along with it.
  ///
  /// `transactions.category`, `importedTransactions.category` and
  /// `descriptionCategoryMappings.category` are free text matched by string —
  /// `BudgetService.getProgress` joins on the name, not the id. Updating only
  /// `Categories.name` therefore orphaned every transaction in the category:
  /// the budget card dropped to "0 of 500", no overspend notification could
  /// fire, the pie chart kept a phantom slice under the old name, and the next
  /// import re-learned the stale name from the mapping table.
  ///
  /// All four writes go in one transaction, so a failure cannot leave the
  /// category renamed with its transactions still pointing at the old name.
  Future<void> updateCategory({
    required int id,
    required String name,
    required String color,
    required String icon,
  }) async {
    await _db.transaction(() async {
      await _checkNameFree(name, exceptId: id);
      final existing =
          await (_db.select(_db.categories)
            ..where((t) => t.id.equals(id))).getSingleOrNull();

      await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
        CategoriesCompanion(
          name: Value(name),
          color: Value(color),
          icon: Value(icon),
        ),
      );

      final oldName = existing?.name;
      if (oldName == null || oldName == name) return;

      if (existing!.isSystem) await _recordSystemRename(oldName, name);

      await (_db.update(_db.transactions)..where(
        (t) => t.category.equals(oldName),
      )).write(TransactionsCompanion(category: Value(name)));
      await (_db.update(_db.importedTransactions)..where(
        (t) => t.category.equals(oldName),
      )).write(ImportedTransactionsCompanion(category: Value(name)));
      await (_db.update(_db.descriptionCategoryMappings)..where(
        (t) => t.category.equals(oldName),
      )).write(DescriptionCategoryMappingsCompanion(category: Value(name)));
    });
  }

  /// Records that a built-in category called [oldName] is now [newName], so
  /// imports file keyword matches under the name it has now.
  ///
  /// Keyed on the seeded name: either an earlier rename already maps that to
  /// [oldName], or [oldName] is the seeded name itself.
  Future<void> _recordSystemRename(String oldName, String newName) async {
    const prefix = AppConstants.systemCategoryNamePrefix;
    final earlier =
        await (_db.select(_db.appSettings)..where(
          (t) => t.key.like('$prefix%') & t.value.equals(oldName),
        )).getSingleOrNull();
    final seeded = earlier?.key.substring(prefix.length) ?? oldName;
    if (seeded == newName) {
      await (_db.delete(_db.appSettings)
        ..where((t) => t.key.equals('$prefix$seeded'))).go();
      return;
    }
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: '$prefix$seeded', value: newName),
        );
  }

  /// Returns the number of transactions and budgets referencing this category.
  /// Call before delete to check if safe.
  ///
  /// Counted in SQL. It loaded every row in the category to take `.length`
  /// (audit D-13).
  Future<({int transactions, int budgets})> usageCounts(
    int categoryId,
    String categoryName,
  ) async {
    final txCount = _db.transactions.id.count();
    final txRow =
        await (_db.selectOnly(_db.transactions)
              ..addColumns([txCount])
              ..where(_db.transactions.category.equals(categoryName)))
            .getSingle();
    final budgetCount = _db.budgets.id.count();
    final budgetRow =
        await (_db.selectOnly(_db.budgets)
              ..addColumns([budgetCount])
              ..where(_db.budgets.categoryId.equals(categoryId)))
            .getSingle();
    return (
      transactions: txRow.read(txCount) ?? 0,
      budgets: budgetRow.read(budgetCount) ?? 0,
    );
  }

  /// Deletes a custom category. Returns false if it is still referenced by
  /// transactions or budgets (caller should show a warning instead).
  ///
  /// One transaction, so nothing can start using the category between the
  /// check and the delete. The import mappings learned for it go with it, and
  /// the import history forgets it: they kept the deleted name, and the next
  /// import filed rows under a category that no longer existed, which no
  /// budget ever counted (audit D-8).
  Future<bool> deleteCategory(int categoryId, String categoryName) {
    return _db.transaction(() async {
      final counts = await usageCounts(categoryId, categoryName);
      if (counts.transactions > 0 || counts.budgets > 0) return false;
      await (_db.delete(_db.descriptionCategoryMappings)
        ..where((t) => t.category.equals(categoryName))).go();
      await (_db.update(_db.importedTransactions)..where(
        (t) => t.category.equals(categoryName),
      )).write(const ImportedTransactionsCompanion(category: Value(null)));
      await (_db.delete(_db.categories)
        ..where((t) => t.id.equals(categoryId))).go();
      return true;
    });
  }
}
