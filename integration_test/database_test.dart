import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sats_stack/core/database/database.dart';

/// Proves the database opens on this platform, the way the app opens it.
///
/// `sqlite3` 3 bundles SQLite through a native-asset hook rather than a
/// plugin, and `flutter test` loads the host's copy, so a hook that bundles
/// nothing, or a library the app is not allowed to load, shows up only in a
/// real build: as the "database could not be opened" screen at launch. Opened
/// in the temporary folder, so the app's own data is never touched. Run with:
///
///   flutter test integration_test/database_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the database opens, seeds, and enforces foreign keys', (
    _,
  ) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/integration_probe.sqlite');
    if (file.existsSync()) file.deleteSync();

    final db = AppDatabase.forTesting(
      driftDatabase(
        name: 'integration_probe',
        native: DriftNativeOptions(databaseDirectory: () async => dir),
      ),
    );
    try {
      final version =
          await db.customSelect('SELECT sqlite_version() AS v').getSingle();
      expect(version.read<String>('v'), isNotEmpty);

      // `onCreate` ran: the seeded categories and default wallet are there.
      expect(await db.select(db.categories).get(), isNotEmpty);
      expect(await db.select(db.wallets).get(), hasLength(1));

      // `beforeOpen` turned foreign keys on for this connection.
      final fk = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(fk.read<int>('foreign_keys'), 1);
    } finally {
      await db.close();
      if (file.existsSync()) file.deleteSync();
    }
  });
}
