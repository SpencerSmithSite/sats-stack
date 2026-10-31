import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../shared/constants/app_constants.dart';
import '../../shared/utils/hash_utils.dart';
import 'tables/ai_conversations_table.dart';
import 'tables/btc_price_cache_table.dart';
import 'tables/btc_price_history_table.dart';
import 'tables/budgets_table.dart';
import 'tables/categories_table.dart';
import 'tables/description_category_mappings_table.dart';
import 'tables/import_sources_table.dart';
import 'tables/import_transactions_table.dart';
import 'tables/settings_table.dart';
import 'tables/transactions_table.dart';
import 'tables/wallets_table.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Wallets,
    Transactions,
    Categories,
    Budgets,
    AppSettings,
    BtcPriceCache,
    BtcPriceHistory,
    AiConversations,
    ImportSources,
    ImportedTransactions,
    DescriptionCategoryMappings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Runs against a caller-supplied executor — tests use
  /// `NativeDatabase.memory()` so they never touch the on-disk database.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 12;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _seedSystemCategories();
      await _seedDefaultWallet();
    },
    // One transaction for the whole upgrade, so it either all happens or none
    // of it does. Without it, a launch killed partway through v8 left the new
    // index created but the schema version unchanged: the next launch ran v8
    // again, failed on "index already exists", and the app could not open its
    // database at all — or, killed later in the step, re-scoped every xpub
    // hash a second time. sqlite's DDL is transactional, so the indexes roll
    // back with the rest.
    onUpgrade: (m, from, to) async {
      await transaction(() async {
        if (from < 2) {
          await m.addColumn(transactions, transactions.recurringPeriod);
          await m.addColumn(transactions, transactions.recurringAnchorDate);
        }
        if (from < 3) {
          await m.createTable(btcPriceHistory);
        }
        if (from < 4) {
          await m.createTable(importSources);
          await m.createTable(importedTransactions);
        }
        if (from < 5) {
          await m.createTable(descriptionCategoryMappings);
        }
        if (from < 6) {
          await migrateToV6(m);
        }
        if (from < 7) {
          await migrateToV7(m);
        }
        if (from < 8) {
          await migrateToV8(m);
        }
        if (from < 9) {
          await m.addColumn(transactions, transactions.recurringSeriesId);
          await adoptLegacyRecurringSeries();
        }
        if (from < 10) {
          await migrateToV10(m);
        }
        if (from < 11) {
          await migrateToV11();
        }
        if (from < 12) {
          await m.addColumn(transactions, transactions.isOwnTransfer);
        }
      });
    },
    beforeOpen: (details) async {
      // sqlite ignores foreign keys unless asked, per connection, so every
      // `.references(...)` in the table definitions was decorative: a row
      // could point at a wallet or category that no longer existed and
      // nothing would complain until something read it back.
      //
      // After the migrator, not before: a migration that rebuilds a table
      // legitimately breaks references while it runs.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// v5 → v6: one budget per category, enforced.
  ///
  /// The index cannot be created over a table that already holds duplicates,
  /// and a pre-v6 install could — `BudgetService.upsert` was a read-then-write
  /// with no transaction. Collapse first, keeping the newest row per category,
  /// then create the index.
  ///
  /// Named rather than inlined so a test can run the real statements; there is
  /// no generated schema history to migrate against.
  Future<void> migrateToV6(Migrator m) async {
    await customStatement(
      'DELETE FROM budgets WHERE id NOT IN '
      '(SELECT MAX(id) FROM budgets GROUP BY category_id)',
    );
    await m.createIndex(idxBudgetsCategoryId);
  }

  /// v6 → v7: indexes for the columns the app filters and sorts on.
  ///
  /// The schema had almost none, so every month range, per-wallet total and
  /// budget grouping was a full table scan. Same shape as [migrateToV6]: the
  /// unique index on the learned-category mappings cannot be created over a
  /// table that already holds duplicates, and a pre-v7 install could, because
  /// the old delete-then-insert was not atomic.
  Future<void> migrateToV7(Migrator m) async {
    await customStatement(
      'DELETE FROM description_category_mappings WHERE id NOT IN '
      '(SELECT MAX(id) FROM description_category_mappings '
      'GROUP BY source_id, description)',
    );
    await m.createIndex(idxTransactionsDate);
    await m.createIndex(idxTransactionsWalletId);
    await m.createIndex(idxTransactionsCategory);
    await m.createIndex(idxTransactionsRecurringPeriod);
    await m.createIndex(idxImportedTransactionsSourceId);
    await m.createIndex(idxDescriptionMappingsSourceDescription);
  }

  /// v7 → v8: unique category names, and xpub rows scoped to their wallet.
  ///
  /// **Categories.** The index cannot be created over duplicate names, and a
  /// pre-v8 install could hold them. Unlike the earlier migrations this does
  /// not delete: a category has budgets pointing at its id. Every duplicate
  /// after the oldest is renamed "Name (2)", "Name (3)" instead, keeping its
  /// id, colour and budget. The transactions stay with the oldest, under the
  /// original name — they were matched by name, so there was never a way to
  /// tell whose they were, and that is the category the user made first.
  ///
  /// **xpub rows.** Their dedup hash was salted with the txid alone, and the
  /// sync skipped any hash already present in *any* wallet, so adding the same
  /// xpub twice gave the second wallet zero rows while reporting them all as
  /// skipped. The hash is now scoped to the wallet with
  /// [HashUtils.scopedToWallet], applied here to every stored xpub row so the
  /// next sync recognises them rather than deleting and re-adding them — which
  /// would have dropped every category and note the user had set.
  Future<void> migrateToV8(Migrator m) async {
    // Only the columns this step uses, here and below. A whole-row `select`
    // maps every column the *current* schema has, and an older database being
    // upgraded does not have them yet: a non-null column added after v8 made
    // this throw for anyone upgrading with an xpub row.
    final all =
        await (selectOnly(categories)
              ..addColumns([categories.id, categories.name])
              ..orderBy([OrderingTerm.asc(categories.id)]))
            .map(
              (r) => (
                id: r.read(categories.id)!,
                name: r.read(categories.name)!,
              ),
            )
            .get();
    final taken = {for (final c in all) c.name};
    final seen = <String>{};
    for (final c in all) {
      if (seen.add(c.name)) continue;
      var n = 2;
      String candidate;
      do {
        candidate = _withSuffix(c.name, n++);
      } while (taken.contains(candidate));
      taken.add(candidate);
      await (update(categories)..where(
        (t) => t.id.equals(c.id),
      )).write(CategoriesCompanion(name: Value(candidate)));
    }
    await m.createIndex(idxCategoriesName);

    final t = transactions;
    final xpubRows =
        await (selectOnly(t)
              ..addColumns([t.id, t.walletId, t.dedupHash])
              ..where(t.source.equals('xpub')))
            .map(
              (r) => (
                id: r.read(t.id)!,
                walletId: r.read(t.walletId)!,
                dedupHash: r.read(t.dedupHash)!,
              ),
            )
            .get();
    for (final row in xpubRows) {
      await (update(transactions)..where((t) => t.id.equals(row.id))).write(
        TransactionsCompanion(
          dedupHash: Value(
            HashUtils.scopedToWallet(row.dedupHash, row.walletId),
          ),
        ),
      );
    }
  }

  /// v8 → v9, and any recurring row since written without a series id: give
  /// each series a stable [Transactions.recurringSeriesId].
  ///
  /// Series used to be told apart by [legacySeriesKey] — the period, anchor,
  /// description and amount — so editing an instance's description or amount
  /// (or renaming the anchor) split it into a series of its own, the original
  /// regenerated, and the user got duplicates. Rows are grouped here the way
  /// that key grouped them, and additionally by wallet, which the old key left
  /// out: two identical series in two accounts were one series.
  ///
  /// The id is derived from the old key and the wallet, so running this twice
  /// gives the same answer, and each series keeps its generation cursor
  /// (re-filed from the old key's setting to the new id's).
  Future<void> adoptLegacyRecurringSeries() async {
    // Only the columns it uses: this runs as the v9 step, against a database
    // that has none of the columns added since — see [migrateToV8].
    final t = transactions;
    final rows =
        await (selectOnly(t)
              ..addColumns([
                t.id,
                t.walletId,
                t.recurringPeriod,
                t.recurringAnchorDate,
                t.description,
                t.amountFiat,
              ])
              ..where(
                t.recurringPeriod.isNotNull() &
                    t.recurringAnchorDate.isNotNull() &
                    t.recurringSeriesId.isNull(),
              ))
            .map(
              (r) => (
                id: r.read(t.id)!,
                walletId: r.read(t.walletId)!,
                oldKey: _legacySeriesKey(
                  period: r.read(t.recurringPeriod)!,
                  anchor: r.read(t.recurringAnchorDate)!,
                  description: r.read(t.description)!,
                  amountFiat: r.read(t.amountFiat)!,
                ),
              ),
            )
            .get();
    if (rows.isEmpty) return;

    await transaction(() async {
      final oldKeys = <String>{};
      final adopted = <String>{};
      for (final row in rows) {
        final oldKey = row.oldKey;
        final id = sha256
            .convert(utf8.encode('$oldKey|${row.walletId}'))
            .toString()
            .substring(0, 16);
        await (update(transactions)..where(
          (t) => t.id.equals(row.id),
        )).write(TransactionsCompanion(recurringSeriesId: Value(id)));
        oldKeys.add(oldKey);
        if (!adopted.add(id)) continue;

        final cursor =
            await (select(appSettings)..where(
              (t) => t.key.equals(AppConstants.recurringCursorKey(oldKey)),
            )).getSingleOrNull();
        if (cursor != null) {
          await into(appSettings).insert(
            AppSettingsCompanion.insert(
              key: AppConstants.recurringCursorKey(id),
              value: cursor.value,
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      }
      await (delete(appSettings)..where(
        (t) => t.key.isIn(oldKeys.map(AppConstants.recurringCursorKey)),
      )).go();
    });
  }

  /// How a series was identified before v9 — kept only so
  /// [adoptLegacyRecurringSeries] can group rows the way it did.
  static String legacySeriesKey(Transaction tx) => _legacySeriesKey(
    period: tx.recurringPeriod!,
    anchor: tx.recurringAnchorDate!,
    description: tx.description,
    amountFiat: tx.amountFiat,
  );

  static String _legacySeriesKey({
    required String period,
    required DateTime anchor,
    required String description,
    required double amountFiat,
  }) {
    final raw =
        '$period|${anchor.millisecondsSinceEpoch}|$description|$amountFiat';
    return sha256.convert(utf8.encode(raw)).toString().substring(0, 16);
  }

  /// v9 → v10: budgets record their currency.
  ///
  /// Every existing budget was entered in — and has only ever been shown in —
  /// the display currency, so that is what it is stamped with.
  Future<void> migrateToV10(Migrator m) async {
    await m.addColumn(budgets, budgets.currency);
    await customStatement(
      'UPDATE budgets SET currency = UPPER(COALESCE(NULLIF('
      '(SELECT value FROM app_settings WHERE key = ?), \'\'), ?))',
      [AppConstants.settingCurrency, AppConstants.defaultCurrency],
    );
  }

  /// v10 → v11: built-in categories the user never recoloured get distinct
  /// colours.
  ///
  /// The seed made Housing, Shopping, Subscriptions and Other the same grey,
  /// Transport the Bitcoin orange and Entertainment the Income green, so four
  /// slices of a pie chart could not be told apart. Only a row still named and
  /// coloured as seeded is changed: a colour the user picked is theirs.
  Future<void> migrateToV11() async {
    const before = {
      'Transport': '#F7931A',
      'Housing': '#888780',
      'Shopping': '#888780',
      'Subscriptions': '#888780',
      'Entertainment': '#1D9E75',
    };
    for (final MapEntry(key: name, value: old) in before.entries) {
      await (update(categories)..where(
        (c) =>
            c.isSystem.equals(true) &
            c.name.equals(name) &
            c.color.upper().equals(old),
      )).write(
        CategoriesCompanion(
          color: Value(AppConstants.seededCategoryColours[name]!),
        ),
      );
    }
  }

  /// "Name (n)", trimmed so it still fits the 60-character name column.
  static String _withSuffix(String name, int n) {
    final suffix = ' ($n)';
    final room = 60 - suffix.length;
    return '${name.length > room ? name.substring(0, room) : name}$suffix';
  }

  /// Deletes all user data and re-seeds the factory defaults.
  Future<void> resetAndReseed() async {
    await transaction(() async {
      await delete(aiConversations).go();
      await delete(importedTransactions).go();
      await delete(descriptionCategoryMappings).go();
      await delete(importSources).go();
      await delete(budgets).go();
      await delete(transactions).go();
      await delete(wallets).go();
      await delete(categories).go();
      await delete(btcPriceCache).go();
      await delete(btcPriceHistory).go();
      await delete(appSettings).go();
      await _seedSystemCategories();
      await _seedDefaultWallet();
    });
  }

  Future<void> _seedSystemCategories() async {
    final systemCategories = [
      CategoriesCompanion.insert(
        name: 'Food & Dining',
        color: AppConstants.seededCategoryColours['Food & Dining']!,
        icon: 'restaurant',
        isSystem: const Value(true),
      ),
      CategoriesCompanion.insert(
        name: 'Transport',
        color: AppConstants.seededCategoryColours['Transport']!,
        icon: 'directions_car',
        isSystem: const Value(true),
      ),
      CategoriesCompanion.insert(
        name: 'Housing',
        color: AppConstants.seededCategoryColours['Housing']!,
        icon: 'home',
        isSystem: const Value(true),
      ),
      CategoriesCompanion.insert(
        name: 'Shopping',
        color: AppConstants.seededCategoryColours['Shopping']!,
        icon: 'shopping_bag',
        isSystem: const Value(true),
      ),
      CategoriesCompanion.insert(
        name: 'Subscriptions',
        color: AppConstants.seededCategoryColours['Subscriptions']!,
        icon: 'subscriptions',
        isSystem: const Value(true),
      ),
      CategoriesCompanion.insert(
        name: 'Entertainment',
        color: AppConstants.seededCategoryColours['Entertainment']!,
        icon: 'movie',
        isSystem: const Value(true),
      ),
      CategoriesCompanion.insert(
        name: 'Bitcoin',
        color: AppConstants.seededCategoryColours['Bitcoin']!,
        icon: 'currency_bitcoin',
        isSystem: const Value(true),
      ),
      CategoriesCompanion.insert(
        name: 'Income',
        color: AppConstants.seededCategoryColours['Income']!,
        icon: 'payments',
        isSystem: const Value(true),
      ),
      CategoriesCompanion.insert(
        name: 'Other',
        color: AppConstants.seededCategoryColours['Other']!,
        icon: 'more_horiz',
        isSystem: const Value(true),
      ),
    ];
    await batch((b) => b.insertAll(categories, systemCategories));
  }

  Future<void> _seedDefaultWallet() async {
    await into(wallets).insert(
      WalletsCompanion.insert(
        label: 'My Account',
        type: 'manual',
        color: '#F7931A',
      ),
    );
  }
}

QueryExecutor _openConnection() {
  return driftDatabase(name: AppConstants.dbName);
}

/// The file drift actually opens.
///
/// There is one of these because there used to be two: Settings → Data built
/// the path from `getApplicationSupportDirectory()` while `driftDatabase`
/// defaults to `getApplicationDocumentsDirectory()`. Export therefore reported
/// "Database file not found", and Import wrote the backup to a path nothing
/// ever reads and then told the user the restore had succeeded. Anything that
/// touches the database file must go through here.
Future<File> databaseFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File(p.join(dir.path, '${AppConstants.dbName}.sqlite'));
}

/// Writes a consistent copy of [db] to [path], replacing any file there.
///
/// VACUUM INTO rather than a file copy: the database is open and may be
/// mid-write, and a byte copy of a live rollback-journal database can be torn
/// — a backup that only fails when you need it. VACUUM INTO asks sqlite for a
/// consistent snapshot, and compacts it on the way out. It refuses to
/// overwrite, so whatever the save dialog created is cleared first.
Future<void> exportDatabaseTo(AppDatabase db, String path) async {
  final dest = File(path);
  if (dest.existsSync()) await dest.delete();
  await db.customStatement('VACUUM INTO ?', [path]);
}

/// How [replaceDatabaseFile] ended.
enum RestoreOutcome {
  /// [replaceDatabaseFile]'s source is now the database.
  replaced,

  /// The copy failed, and the previous database was put back.
  failedOriginalRestored,

  /// The copy failed and the previous database could not be put back; it is
  /// still in the `.bak` beside the database, if one could be made.
  failedOriginalLost,
}

/// Replaces [target] with [source], keeping the original as `<target>.bak`.
///
/// The caller must already have closed the database. On failure the copy may
/// have stopped partway, so the original is copied back over the torn file
/// before returning: a relaunch should open the user's own data, not half of
/// a backup.
///
/// [copy] is for tests, which need a copy that fails partway.
Future<({RestoreOutcome outcome, Object? error})> replaceDatabaseFile({
  required File source,
  required File target,
  Future<void> Function(File from, String to)? copy,
}) async {
  final copyFile = copy ?? (from, to) => from.copy(to);
  final backup = File('${target.path}.bak');
  try {
    if (target.existsSync()) await target.copy(backup.path);
    await copyFile(source, target.path);
    return (outcome: RestoreOutcome.replaced, error: null);
  } catch (e) {
    try {
      if (backup.existsSync()) {
        await backup.copy(target.path);
        return (outcome: RestoreOutcome.failedOriginalRestored, error: e);
      }
    } catch (_) {}
    return (outcome: RestoreOutcome.failedOriginalLost, error: e);
  }
}
