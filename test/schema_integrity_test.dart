/// Tests for the v7 schema work: referential integrity and the indexes the
/// app's hot queries depend on.
///
/// `PRAGMA foreign_keys` is off by default in sqlite, per connection, so every
/// `.references(...)` in the table definitions was decorative until v7 — a row
/// could point at a wallet or category that did not exist.
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/shared/utils/hash_utils.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// `beforeOpen` runs on the first query, so anything that needs the pragma
  /// in force has to touch the database first.
  Future<void> open() => db.select(db.wallets).get();

  group('foreign keys are enforced', () {
    test('the pragma is on once the database is open', () async {
      await open();
      final result = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(result.data.values.first, anyOf(1, true));
    });

    test(
      'a transaction cannot point at a wallet that does not exist',
      () async {
        await open();
        await expectLater(
          db
              .into(db.transactions)
              .insert(
                TransactionsCompanion.insert(
                  walletId: 9999,
                  date: DateTime(2026, 3, 1),
                  description: 'Orphan',
                  amountSats: -1000,
                  amountFiat: -10,
                  fiatCurrency: 'USD',
                  source: 'manual',
                  dedupHash: 'orphan-wallet',
                ),
              ),
          throwsA(isA<Exception>()),
        );
      },
    );

    test('a budget cannot point at a category that does not exist', () async {
      await open();
      await expectLater(
        db
            .into(db.budgets)
            .insert(
              BudgetsCompanion.insert(
                categoryId: 9999,
                amountFiat: 100,
                period: 'monthly',
              ),
            ),
        throwsA(isA<Exception>()),
      );
    });

    test('the seeded wallet and categories still satisfy it', () async {
      // The seed runs in onCreate, before the pragma is on; this proves it did
      // not leave anything the constraint would reject.
      await open();
      final wallet = await db.select(db.wallets).getSingle();
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              walletId: wallet.id,
              date: DateTime(2026, 3, 1),
              description: 'Coffee',
              amountSats: -5000,
              amountFiat: -4.5,
              fiatCurrency: 'USD',
              source: 'manual',
              dedupHash: 'seeded-ok',
            ),
          );
      expect(await db.select(db.transactions).get(), hasLength(1));
    });

    test('resetAndReseed does not trip the constraint', () async {
      await open();
      final wallet = await db.select(db.wallets).getSingle();
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              walletId: wallet.id,
              date: DateTime(2026, 3, 1),
              description: 'Coffee',
              amountSats: -5000,
              amountFiat: -4.5,
              fiatCurrency: 'USD',
              source: 'manual',
              dedupHash: 'reset-ok',
            ),
          );

      // Deletes parents and children; with the pragma on, the order matters.
      await db.resetAndReseed();

      expect(await db.select(db.transactions).get(), isEmpty);
      expect(await db.select(db.wallets).get(), hasLength(1));
      expect(await db.select(db.categories).get(), hasLength(9));
    });
  });

  group('indexes', () {
    test('the hot query columns are indexed', () async {
      await open();
      final rows =
          await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'index'",
              )
              .get();
      final names = rows.map((r) => r.data['name'] as String).toSet();

      for (final expected in const [
        'idx_transactions_date',
        'idx_transactions_wallet_id',
        'idx_transactions_category',
        'idx_transactions_recurring_period',
        'idx_imported_transactions_source_id',
        'idx_description_mappings_source_description',
        'idx_budgets_category_id',
      ]) {
        expect(names, contains(expected));
      }
    });

    test(
      'a month range query uses the date index rather than a scan',
      () async {
        await open();
        final plan =
            await db
                .customSelect(
                  'EXPLAIN QUERY PLAN SELECT * FROM transactions '
                  'WHERE date >= ? AND date < ? ORDER BY date DESC',
                  variables: [Variable.withInt(0), Variable.withInt(1)],
                )
                .get();
        final detail = plan.map((r) => r.data['detail'] as String).join(' ');
        expect(detail, contains('idx_transactions_date'));
        expect(detail, isNot(contains('SCAN transactions')));
      },
    );
  });

  group('migrateToV7', () {
    test('collapses duplicate learned mappings before indexing them', () async {
      await open();
      final sourceId = await db
          .into(db.importSources)
          .insert(
            ImportSourcesCompanion.insert(
              name: 'Barclays',
              type: 'bank',
              currency: 'GBP',
            ),
          );

      // Make this look like a v6 database: none of v7's indexes exist yet.
      for (final index in const [
        'idx_transactions_date',
        'idx_transactions_wallet_id',
        'idx_transactions_category',
        'idx_transactions_recurring_period',
        'idx_imported_transactions_source_id',
        'idx_description_mappings_source_description',
      ]) {
        await db.customStatement('DROP INDEX IF EXISTS $index');
      }

      // The shape a pre-v7 install could hold: the old writer deleted then
      // inserted without a transaction, so two imports could interleave.
      for (final category in const ['Other', 'Food & Dining', 'Transport']) {
        await db
            .into(db.descriptionCategoryMappings)
            .insert(
              DescriptionCategoryMappingsCompanion.insert(
                description: 'tesco',
                sourceId: sourceId,
                category: category,
              ),
            );
      }
      expect(
        await db.select(db.descriptionCategoryMappings).get(),
        hasLength(3),
      );

      await db.migrateToV7(Migrator(db));

      final rows = await db.select(db.descriptionCategoryMappings).get();
      expect(rows, hasLength(1));
      expect(rows.single.category, 'Transport'); // newest survives

      // And the index now prevents it recurring.
      await expectLater(
        db
            .into(db.descriptionCategoryMappings)
            .insert(
              DescriptionCategoryMappingsCompanion.insert(
                description: 'tesco',
                sourceId: sourceId,
                category: 'Shopping',
              ),
            ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('migrateToV8', () {
    Future<int> walletId() async =>
        (await db.select(db.wallets).get()).first.id;

    test('renames duplicate category names instead of deleting them', () async {
      await open();
      // A v7 database could hold two categories with one name.
      await db.customStatement('DROP INDEX IF EXISTS idx_categories_name');
      final first = await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              name: 'Pets',
              color: '#F7931A',
              icon: 'pets',
            ),
          );
      final second = await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              name: 'Pets',
              color: '#E24B4A',
              icon: 'pets',
            ),
          );
      // The second has a budget, which deleting it would have broken.
      await db
          .into(db.budgets)
          .insert(
            BudgetsCompanion.insert(
              categoryId: second,
              amountFiat: 50,
              period: 'monthly',
            ),
          );

      await db.migrateToV8(Migrator(db));

      final byId = {
        for (final c in await db.select(db.categories).get()) c.id: c,
      };
      expect(byId[first]!.name, 'Pets', reason: 'the oldest keeps the name');
      expect(byId[second]!.name, 'Pets (2)');
      expect(await db.select(db.budgets).get(), hasLength(1));

      // And the index now prevents it recurring.
      await expectLater(
        db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                name: 'Pets',
                color: '#1D9E75',
                icon: 'pets',
              ),
            ),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'a renamed duplicate never takes a name that is already used',
      () async {
        await open();
        await db.customStatement('DROP INDEX IF EXISTS idx_categories_name');
        for (final name in const ['Pets', 'Pets', 'Pets (2)']) {
          await db
              .into(db.categories)
              .insert(
                CategoriesCompanion.insert(
                  name: name,
                  color: '#F7931A',
                  icon: 'pets',
                ),
              );
        }
        await db.migrateToV8(Migrator(db));
        final names = (await db.select(db.categories).get()).map((c) => c.name);
        expect(names.where((n) => n.startsWith('Pets')).toSet(), {
          'Pets',
          'Pets (2)',
          'Pets (3)',
        });
      },
    );

    test(
      'rescopes stored xpub hashes to their wallet, keeping the rows',
      () async {
        await open();
        await db.customStatement('DROP INDEX IF EXISTS idx_categories_name');
        final wallet = await walletId();
        Future<void> add(String hash, String source) => db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                walletId: wallet,
                date: DateTime(2026, 3, 1),
                description: 'BTC abcd1234',
                amountSats: 1000,
                amountFiat: 1,
                fiatCurrency: 'USD',
                source: source,
                category: const Value('Groceries — set by the user'),
                dedupHash: hash,
              ),
            );
        await add('xpubhash', 'xpub');
        await add('csvhash', 'csv');

        await db.migrateToV8(Migrator(db));

        final rows = {
          for (final t in await db.select(db.transactions).get()) t.source: t,
        };
        expect(
          rows['xpub']!.dedupHash,
          HashUtils.scopedToWallet('xpubhash', wallet),
        );
        // What a delete-and-resync would have lost.
        expect(rows['xpub']!.category, 'Groceries — set by the user');
        expect(
          rows['csv']!.dedupHash,
          'csvhash',
          reason: 'only xpub rows move',
        );
      },
    );
  });
}
