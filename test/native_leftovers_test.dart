/// The native follow-ups item 15 left: exports that work on a phone, and the
/// icon generator's sources out of the app bundle.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('a database snapshot is a whole, openable copy', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final wallet = (await db.select(db.wallets).getSingle()).id;
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            walletId: wallet,
            date: DateTime(2026, 3, 1),
            description: 'Rent',
            amountSats: -1000000,
            amountFiat: -1200,
            fiatCurrency: 'GBP',
            source: 'manual',
            dedupHash: 'rent',
          ),
        );

    final bytes = await databaseSnapshot(db);
    expect(ascii.decode(bytes.sublist(0, 15)), 'SQLite format 3');

    final dir = await Directory.systemTemp.createTemp('snapshot');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/copy.sqlite')..writeAsBytesSync(bytes);
    final copy = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(copy.close);
    final rows = await copy.select(copy.transactions).get();
    expect(rows.single.description, 'Rent');
  });

  // On iOS and Android `saveFile` writes the bytes it is given and returns no
  // path to write to; without them it throws. Both exports called it without,
  // so neither worked on a phone.
  test('every save dialog is handed the bytes to write', () {
    final calls = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in RegExp(r'\.saveFile\(').allMatches(src)) {
        // To the call's closing parenthesis.
        var depth = 0, i = m.end - 1;
        for (; i < src.length; i++) {
          if (src[i] == '(') depth++;
          if (src[i] == ')' && --depth == 0) break;
        }
        final call = src.substring(m.start, i);
        calls.add(f.path);
        expect(call, contains('bytes:'), reason: f.path);
      }
    }
    expect(calls, hasLength(2));
  });

  test(
    'the icon sources are not bundled, and the generators can find them',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final assets =
          RegExp(
            r'^  assets:\n((?:    .*\n)+)',
            multiLine: true,
          ).firstMatch(pubspec)!.group(1)!;
      expect(assets, isNot(contains('assets/icons')));

      final configs = [
        File('flutter_launcher_icons.yaml').readAsStringSync(),
        pubspec, // flutter_native_splash's section
      ];
      for (final config in configs) {
        for (final m in RegExp(r'assets/icons/[\w.]+').allMatches(config)) {
          expect(File(m.group(0)!).existsSync(), isTrue, reason: m.group(0));
        }
      }
    },
  );
}
