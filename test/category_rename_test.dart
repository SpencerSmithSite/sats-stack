import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/budget_service.dart';
import 'package:sats_stack/core/services/category_service.dart';
import 'package:sats_stack/core/services/dashboard_service.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late CategoryService categories;
  late BudgetService budgets;
  late DashboardService dashboard;
  late int walletId;
  late int foodId;

  final month = DateTime(2025, 3);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    categories = CategoryService(db);
    budgets = BudgetService(db);
    dashboard = DashboardService(db);
    walletId = (await db.select(db.wallets).getSingle()).id;
    foodId =
        (await (db.select(db.categories)
              ..where((c) => c.name.equals('Food & Dining'))).getSingle())
            .id;

    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            walletId: walletId,
            date: DateTime(2025, 3, 10),
            description: 'Groceries',
            amountSats: -1000000,
            amountFiat: -120,
            fiatCurrency: 'USD',
            category: const Value('Food & Dining'),
            source: 'manual',
            dedupHash: 'groceries',
          ),
        );
    await budgets.upsert(categoryId: foodId, amountFiat: 500, currency: 'USD');
  });

  tearDown(() => db.close());

  Future<void> rename(String to) => categories.updateCategory(
    id: foodId,
    name: to,
    color: '#E24B4A',
    icon: 'restaurant',
  );

  test('a rename carries the budget progress with it', () async {
    expect((await budgets.getProgress(month)).single.spentFiat, 120);

    await rename('Eating Out');

    final progress = await budgets.getProgress(month);
    // The bug: transactions still said 'Food & Dining', so the card read
    // "$0 of $500" and no overspend notification could ever fire.
    expect(progress.single.category.name, 'Eating Out');
    expect(progress.single.spentFiat, 120);
  });

  test('a rename leaves no phantom slice under the old name', () async {
    await rename('Eating Out');

    final data = await dashboard.getDashboard(month);
    expect(data.spendingByCategory.containsKey('Food & Dining'), isFalse);
    expect(data.spendingByCategory['Eating Out'], 120);
  });

  test('imported rows and learned mappings follow the rename', () async {
    final sourceId = await db
        .into(db.importSources)
        .insert(
          ImportSourcesCompanion.insert(
            name: 'Chase',
            type: 'bank',
            currency: 'USD',
          ),
        );
    await db
        .into(db.importedTransactions)
        .insert(
          ImportedTransactionsCompanion.insert(
            sourceId: sourceId,
            date: DateTime(2025, 3, 11),
            amountCents: -4200,
            direction: 'debit',
            description: 'TESCO',
            category: const Value('Food & Dining'),
            currency: 'USD',
            rawDescription: 'TESCO',
            importHash: 'tesco',
          ),
        );
    await db
        .into(db.descriptionCategoryMappings)
        .insert(
          DescriptionCategoryMappingsCompanion.insert(
            description: 'tesco',
            sourceId: sourceId,
            category: 'Food & Dining',
          ),
        );

    await rename('Eating Out');

    final imported = await db.select(db.importedTransactions).getSingle();
    final mapping = await db.select(db.descriptionCategoryMappings).getSingle();
    expect(imported.category, 'Eating Out');
    // Otherwise the next import would re-learn the name that no longer exists.
    expect(mapping.category, 'Eating Out');
  });

  group('deleting a custom category', () {
    late int customId;
    setUp(() async {
      await categories.createCategory(
        name: 'Pets',
        color: '#123456',
        icon: 'pets',
      );
      customId =
          (await (db.select(db.categories)
                ..where((c) => c.name.equals('Pets'))).getSingle())
              .id;
    });

    test('counts what uses it', () async {
      // Audit D-13: counted by loading every row.
      expect(await categories.usageCounts(foodId, 'Food & Dining'), (
        transactions: 1,
        budgets: 1,
      ));
      expect(await categories.usageCounts(customId, 'Pets'), (
        transactions: 0,
        budgets: 0,
      ));
    });

    test('takes its import mappings with it', () async {
      // Audit D-8: they kept the deleted name, and the next import filed
      // rows under it.
      final sourceId = await db
          .into(db.importSources)
          .insert(
            ImportSourcesCompanion.insert(
              name: 'Chase',
              type: 'bank',
              currency: 'USD',
            ),
          );
      await db
          .into(db.importedTransactions)
          .insert(
            ImportedTransactionsCompanion.insert(
              sourceId: sourceId,
              date: DateTime(2025, 3, 11),
              amountCents: -2500,
              direction: 'debit',
              description: 'PET SHOP',
              category: const Value('Pets'),
              currency: 'USD',
              rawDescription: 'PET SHOP',
              importHash: 'pets',
            ),
          );
      await db
          .into(db.descriptionCategoryMappings)
          .insert(
            DescriptionCategoryMappingsCompanion.insert(
              description: 'pet shop',
              sourceId: sourceId,
              category: 'Pets',
            ),
          );

      expect(await categories.deleteCategory(customId, 'Pets'), isTrue);

      expect(await db.select(db.descriptionCategoryMappings).get(), isEmpty);
      expect(
        (await db.select(db.importedTransactions).getSingle()).category,
        isNull,
      );
    });

    test('is refused while a transaction uses it', () async {
      expect(await categories.deleteCategory(foodId, 'Food & Dining'), isFalse);
      expect(
        await (db.select(db.categories)
          ..where((c) => c.id.equals(foodId))).getSingleOrNull(),
        isNotNull,
      );
    });
  });

  test('changing only the colour touches no transaction', () async {
    await categories.updateCategory(
      id: foodId,
      name: 'Food & Dining',
      color: '#123456',
      icon: 'restaurant',
    );

    final cat =
        await (db.select(db.categories)
          ..where((c) => c.id.equals(foodId))).getSingle();
    expect(cat.color, '#123456');
    expect(
      (await db.select(db.transactions).getSingle()).category,
      'Food & Dining',
    );
  });

  group('one budget per category', () {
    test('a second upsert updates rather than inserting', () async {
      await budgets.upsert(
        categoryId: foodId,
        amountFiat: 650,
        currency: 'USD',
      );

      final rows = await db.select(db.budgets).get();
      expect(rows, hasLength(1));
      expect(rows.single.amountFiat, 650);
    });

    test(
      'the v6 migration collapses duplicates an older install left',
      () async {
        // Reproduce a pre-v6 table: no index, two budgets for one category.
        await db.customStatement('DROP INDEX idx_budgets_category_id');
        for (final amount in [200.0, 300.0]) {
          await db
              .into(db.budgets)
              .insert(
                BudgetsCompanion.insert(
                  categoryId: foodId,
                  amountFiat: amount,
                  period: 'monthly',
                ),
              );
        }
        expect(await db.select(db.budgets).get(), hasLength(3));

        await db.migrateToV6(Migrator(db));

        final rows = await db.select(db.budgets).get();
        expect(rows, hasLength(1));
        expect(rows.single.amountFiat, 300); // the newest survives
        // And the index is in place, so it cannot happen again.
        await expectLater(
          db
              .into(db.budgets)
              .insert(
                BudgetsCompanion.insert(
                  categoryId: foodId,
                  amountFiat: 400,
                  period: 'monthly',
                ),
              ),
          throwsA(isA<Exception>()),
        );
      },
    );

    test('two concurrent upserts cannot leave two rows behind', () async {
      // The shape of a double-tapped Save: both reads used to see no row and
      // both inserted, after which every later upsert threw StateError out of
      // getSingleOrNull and the budget could not be edited again.
      final other =
          (await (db.select(db.categories)
                ..where((c) => c.name.equals('Transport'))).getSingle())
              .id;

      await Future.wait([
        budgets.upsert(categoryId: other, amountFiat: 200, currency: 'USD'),
        budgets.upsert(categoryId: other, amountFiat: 300, currency: 'USD'),
      ]);

      final rows =
          await (db.select(db.budgets)
            ..where((b) => b.categoryId.equals(other))).get();
      expect(rows, hasLength(1));

      // And it is still editable.
      await budgets.upsert(categoryId: other, amountFiat: 450, currency: 'USD');
      expect(
        (await (db.select(db.budgets)
              ..where((b) => b.categoryId.equals(other))).getSingle())
            .amountFiat,
        450,
      );
    });
  });
}
