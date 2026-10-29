/// An upgrade interrupted partway leaves the database as it was, so the next
/// launch can run it again.
///
/// The upgrade ran statement by statement with no transaction. A launch killed
/// after v8 created its index, but before the schema version was written, left
/// a database the next launch could not open: v8 ran again and failed on
/// "index already exists", every time.
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';

/// Dies partway through v8: after its index exists, before it finishes.
class _KilledDuringV8 extends AppDatabase {
  _KilledDuringV8(File file) : super.forTesting(NativeDatabase(file));

  @override
  Future<void> migrateToV8(Migrator m) async {
    await m.createIndex(idxCategoriesName);
    throw StateError('process killed');
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('a v8 upgrade killed partway can be run again', () async {
    final dir = await Directory.systemTemp.createTemp('migration');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    // A v7 database: current tables, without v8's index, version 7…
    final fresh = AppDatabase.forTesting(NativeDatabase(file));
    await fresh.customSelect('SELECT 1').get();
    await fresh.customStatement('DROP INDEX idx_categories_name');
    // …and without v9's column.
    await fresh.customStatement(
      'ALTER TABLE transactions DROP COLUMN recurring_series_id',
    );
    await fresh.customStatement('PRAGMA user_version = 7');
    await fresh.close();

    final killed = _KilledDuringV8(file);
    await expectLater(
      killed.customSelect('SELECT 1').get(),
      throwsA(isA<Object>()),
    );
    await killed.close();

    // The next launch.
    final relaunched = AppDatabase.forTesting(NativeDatabase(file));
    final version =
        await relaunched.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, 9);
    final index =
        await relaunched
            .customSelect(
              "SELECT name FROM sqlite_master WHERE name = 'idx_categories_name'",
            )
            .get();
    expect(index, hasLength(1));
    await relaunched.close();
  });
}
