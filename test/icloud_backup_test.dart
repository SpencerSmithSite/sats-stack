/// Whether the database goes into iCloud backups is the user's choice
/// (audit P-2).
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/icloud_backup.dart';
import 'package:sats_stack/features/settings/widgets/data_section.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/shared/constants/app_constants.dart';
import 'package:sats_stack/shared/theme/app_theme.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<String?> stored() async =>
      (await (db.select(db.appSettings)..where(
            (s) => s.key.equals(AppConstants.settingICloudBackup),
          )).getSingleOrNull())
          ?.value;

  test('a new install starts with its data out of iCloud', () async {
    expect(await ICloudBackup.included(db), isFalse);
    expect(await stored(), 'false');
  });

  test('an existing install keeps the backup it had', () async {
    // It finished onboarding before this choice existed, and was being
    // backed up all along; taking that away silently could cost it its only
    // copy.
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: AppConstants.settingOnboardingComplete,
            value: 'true',
          ),
        );
    expect(await ICloudBackup.included(db), isTrue);
    expect(await stored(), 'true');
  });

  test('once chosen, the choice stands', () async {
    await ICloudBackup.setIncluded(db, true);
    expect(await ICloudBackup.included(db), isTrue);
    await ICloudBackup.setIncluded(db, false);
    expect(await ICloudBackup.included(db), isFalse);
  });

  testWidgets('Settings offers it, and says what iCloud needs to be private', (
    tester,
  ) async {
    app.db = db;
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: DataSection(showICloudChoice: true)),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(find.text('Include in iCloud backup'), findsOneWidget);
    expect(find.textContaining('stays on this iPhone'), findsOneWidget);

    await tester.tap(find.text('Include in iCloud backup'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.textContaining('Advanced Data Protection'), findsOneWidget);
    expect(await tester.runAsync(stored), 'true');
  });

  testWidgets('elsewhere there is no such switch', (tester) async {
    app.db = db;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: DataSection(showICloudChoice: false)),
      ),
    );
    await tester.pump();
    expect(find.text('Include in iCloud backup'), findsNothing);
  });

  test('after a reset, a finished onboarding is not mistaken for an old '
      'install', () async {
    // What the Danger Zone now does after emptying the tables.
    await db.resetAndReseed();
    await ICloudBackup.setIncluded(db, false);
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppConstants.settingOnboardingComplete,
            value: 'true',
          ),
        );
    expect(await ICloudBackup.included(db), isFalse);
  });
}
