/// Restoring a backup checks it properly first, a restore's leftover copy of
/// the old database is deleted, "Reset all data" leaves nothing readable
/// behind, and a database that will not open no longer stops the app
/// launching (audit D-4, D-5).
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/screens/database_recovery_screen.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('restore'));
  tearDown(() => dir.delete(recursive: true));

  File at(String name) => File('${dir.path}/$name');

  Future<void> addRow(AppDatabase db, String description) async {
    final wallet = (await db.select(db.wallets).get()).first.id;
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            walletId: wallet,
            date: DateTime(2026, 3, 1),
            description: description,
            amountSats: 0,
            amountFiat: -1200,
            fiatCurrency: 'GBP',
            source: 'manual',
            dedupHash: description,
          ),
        );
  }

  /// A real backup, as Settings → Data → Export makes one.
  Future<File> goodBackup() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await addRow(db, 'Rent');
    final file = at('backup.sqlite');
    await exportDatabaseTo(db, file.path);
    await db.close();
    return file;
  }

  group('checking a backup', () {
    Future<String?> problem(File f) => backupProblem(f, schemaVersion: 12);

    test('a real backup passes', () async {
      expect(await problem(await goodBackup()), isNull);
    });

    test('a backup from an older version passes, and is upgraded', () async {
      final file = await goodBackup();
      final old = AppDatabase.forTesting(NativeDatabase(file));
      await old.customStatement(
        'ALTER TABLE transactions DROP COLUMN is_own_transfer',
      );
      await old.customStatement('PRAGMA user_version = 11');
      await old.close();
      expect(await problem(file), isNull);
    });

    test('a file that is not sqlite is refused', () async {
      final file = at('notes.db')..writeAsStringSync('hello' * 100);
      expect(await problem(file), contains('not a Sats Stack backup'));
    });

    test("another app's sqlite database is refused", () async {
      // A sqlite file with someone else's table and no schema version.
      // Opening it as ours would build a fresh, empty database in its place.
      final file = at('other.sqlite');
      final db = AppDatabase.forTesting(NativeDatabase(file));
      final tables =
          await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table' "
                "AND name NOT LIKE 'sqlite_%'",
              )
              .get();
      await db.customStatement('PRAGMA foreign_keys = OFF');
      for (final t in tables) {
        await db.customStatement('DROP TABLE "${t.data['name']}"');
      }
      await db.customStatement('CREATE TABLE notes (body TEXT)');
      await db.customStatement('PRAGMA user_version = 0');
      await db.close();
      expect(await problem(file), contains('not a Sats Stack backup'));
    });

    test('a backup from a newer version is refused', () async {
      final file = await goodBackup();
      final db = AppDatabase.forTesting(NativeDatabase(file));
      await db.customStatement('PRAGMA user_version = 99');
      await db.close();
      expect(await problem(file), contains('newer version'));
    });

    test('a truncated backup is refused', () async {
      final file = await goodBackup();
      final bytes = file.readAsBytesSync();
      file.writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
      expect(await problem(file), contains('damaged'));
    });

    test('checking leaves the backup untouched', () async {
      final file = await goodBackup();
      final before = file.readAsBytesSync();
      await problem(file);
      expect(file.readAsBytesSync(), before);
    });
  });

  group('what a restore and a reset leave behind', () {
    test('the restore backup is discarded', () async {
      final live = at('live.sqlite')..writeAsStringSync('new');
      restoreBackupFor(live).writeAsStringSync('old data');
      await discardRestoreBackup(live);
      expect(restoreBackupFor(live).existsSync(), isFalse);
      expect(live.existsSync(), isTrue);
      // And it is fine to call with nothing there.
      await discardRestoreBackup(live);
    });

    test('after a reset, deleted rows are not in the file', () async {
      final live = at('live.sqlite');
      final db = AppDatabase.forTesting(NativeDatabase(live));
      await addRow(db, 'SECRET-PAYEE-MARKER');
      await db.resetAndReseed();
      restoreBackupFor(live).writeAsStringSync('old data');

      await eraseDeletedData(db, live);
      await db.close();

      final bytes = latin1.decode(live.readAsBytesSync());
      expect(bytes.contains('SECRET-PAYEE-MARKER'), isFalse);
      expect(restoreBackupFor(live).existsSync(), isFalse);
    });
  });

  group('a database that will not open', () {
    Future<void> pump(WidgetTester tester, File live) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        DatabaseRecoveryApp(database: live, error: 'file is not a database'),
      );
    }

    testWidgets('puts the previous data back, without the broken journal', (
      tester,
    ) async {
      final live = at('live.sqlite')..writeAsStringSync('broken');
      final journal = File('${live.path}-journal')..writeAsStringSync('j');
      restoreBackupFor(live).writeAsStringSync('the user data');
      await pump(tester, live);
      expect(find.textContaining('still here'), findsOneWidget);

      await tester.runAsync(
        () => tester.tap(find.text('Put back the previous data')),
      );
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }

      expect(live.readAsStringSync(), 'the user data');
      expect(restoreBackupFor(live).existsSync(), isFalse);
      expect(journal.existsSync(), isFalse);
      expect(find.text('Your previous data is back'), findsOneWidget);
    });

    testWidgets('with no copy to put back, it says nothing was deleted', (
      tester,
    ) async {
      final live = at('live.sqlite')..writeAsStringSync('broken');
      await pump(tester, live);
      expect(find.textContaining('Nothing has been deleted'), findsOneWidget);
      expect(find.text('Put back the previous data'), findsNothing);
      expect(live.readAsStringSync(), 'broken');
    });
  });
}
