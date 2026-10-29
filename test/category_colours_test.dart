/// Built-in categories are drawn in distinct colours, the same on every
/// screen.
///
/// The database seeded Housing, Shopping, Subscriptions and Other in one grey,
/// Transport in the Bitcoin orange and Entertainment in the Income green, while
/// `CategoryPalette` had its own, different table — so the dashboard (which
/// reads the database) and Analytics (which read only the palette) disagreed,
/// and four pie slices could not be told apart.
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/shared/constants/app_constants.dart';
import 'package:sats_stack/shared/theme/category_palette.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('every built-in category has its own colour', () {
    final colours = AppConstants.seededCategoryColours.values.toList();
    expect(colours.toSet(), hasLength(colours.length));
  });

  test('the database seeds what the palette draws', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    for (final c in await db.select(db.categories).get()) {
      expect(
        CategoryPalette.of(c.name),
        CategoryPalette.parseHex(c.color),
        reason: c.name,
      );
    }
  });

  test('the v11 upgrade recolours only untouched built-ins', () async {
    final dir = await Directory.systemTemp.createTemp('v11');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    final v10 = AppDatabase.forTesting(NativeDatabase(file));
    Future<void> colour(String name, String hex) => (v10.update(v10.categories)
      ..where(
        (c) => c.name.equals(name),
      )).write(CategoriesCompanion(color: Value(hex)));
    await colour('Housing', '#888780'); // as seeded before v11
    await colour('Shopping', '#123456'); // the user's own choice
    await v10.customStatement('PRAGMA user_version = 10');
    await v10.close();

    final upgraded = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(upgraded.close);
    final byName = {
      for (final c in await upgraded.select(upgraded.categories).get())
        c.name: c.color,
    };
    expect(byName['Housing'], AppConstants.seededCategoryColours['Housing']);
    expect(byName['Shopping'], '#123456');
  });
}
