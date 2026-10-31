/// Every schema version the app has shipped upgrades to the current one
/// (TODO item 13).
///
/// The upgrade steps used to be tested one at a time, against a fresh
/// database with the newer columns dropped by hand — a guess at what an old
/// install looked like, which is how a whole-row read in the v8 step went
/// unnoticed (#48). `drift_schemas/` holds the real schema of each version,
/// dumped from the commit that shipped it, and `test/generated_migrations/` is
/// generated from those. v1 and v2 predate the repository: they are v3 less
/// what the v1→v2 and v2→v3 steps add.
///
/// Changing the schema means bumping `schemaVersion`, then:
///   dart run drift_dev schema dump lib/core/database/database.dart drift_schemas/
///   dart run drift_dev schema generate --data-classes --companions drift_schemas/ test/generated_migrations/
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/shared/utils/hash_utils.dart';

import 'generated_migrations/schema.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final verifier = SchemaVerifier(GeneratedHelper());

  test('there is a dump of the current schema version', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    expect(GeneratedHelper.versions.last, db.schemaVersion);
  });

  test('a fresh install matches the latest dump', () async {
    final schema = await verifier.schemaAt(GeneratedHelper.versions.last);
    final dumped = AppDatabase.forTesting(schema.newConnection());
    addTearDown(dumped.close);
    // The dump against the table definitions: a schema change made without a
    // new dump fails here.
    await dumped.validateDatabaseSchema();

    final fresh = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(fresh.close);
    await fresh.validateDatabaseSchema();
  });

  group('upgrading', () {
    for (final from in GeneratedHelper.versions.where(
      (v) => v < GeneratedHelper.versions.last,
    )) {
      test('from v$from', () async {
        final schema = await verifier.schemaAt(from);
        final db = AppDatabase.forTesting(schema.newConnection());
        addTearDown(db.close);
        await verifier.migrateAndValidate(db, db.schemaVersion);
      });
    }

    // Rows, not just tables: each data step runs against what a v7 install
    // really held — the case #48's crash needed.
    test('a v7 database keeps its rows through every data step', () async {
      final schema = await verifier.schemaAt(7);
      final raw = schema.rawDatabase;
      raw.execute(
        'INSERT INTO wallets (id, label, type, xpub, color) VALUES '
        "(1, 'Cold', 'xpub', 'zpub', '#F7931A')",
      );
      raw.execute(
        'INSERT INTO categories (id, name, color, icon, is_system) VALUES '
        "(1, 'Food', '#111111', 'restaurant', 0), "
        "(2, 'Food', '#222222', 'restaurant', 0), "
        "(3, 'Housing', '#888780', 'home', 1)",
      );
      raw.execute(
        'INSERT INTO budgets (category_id, amount_fiat, period) '
        "VALUES (2, 300, 'monthly')",
      );
      raw.execute(
        "INSERT INTO app_settings (key, value) VALUES ('currency', 'gbp')",
      );
      raw.execute(
        'INSERT INTO transactions (wallet_id, date, description, amount_sats, '
        'amount_fiat, fiat_currency, category, source, is_bitcoin, dedup_hash, '
        'recurring_period, recurring_anchor_date) VALUES '
        "(1, 1741089600, 'BTC f00df00d', 5000, 4, 'GBP', 'Bitcoin', 'xpub', 1, "
        "'xh', NULL, NULL), "
        "(1, 1741089600, 'Rent', 0, -1200, 'GBP', 'Housing', 'manual', 0, "
        "'rh', 'monthly', 1741089600)",
      );

      final db = AppDatabase.forTesting(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, db.schemaVersion);

      final cats = await db.select(db.categories).get();
      expect(cats.map((c) => c.name), ['Food', 'Food (2)', 'Housing']);
      // v11 recolours a built-in category still in its seeded grey.
      expect(cats.last.color, isNot('#888780'));

      final budget = await db.select(db.budgets).getSingle();
      expect(budget.categoryId, 2);
      expect(budget.currency, 'GBP');

      final rows = await db.select(db.transactions).get();
      final xpub = rows.singleWhere((t) => t.source == 'xpub');
      expect(xpub.dedupHash, HashUtils.scopedToWallet('xh', 1));
      final rent = rows.singleWhere((t) => t.description == 'Rent');
      expect(rent.recurringSeriesId, isNotNull);
      expect(rows.every((t) => !t.isOwnTransfer), isTrue);
    });
  });
}
