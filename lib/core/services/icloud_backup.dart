import 'dart:io';

import 'package:flutter/services.dart';

import '../../shared/constants/app_constants.dart';
import '../database/database.dart';

/// Whether the database goes into iCloud and device backups on iOS.
///
/// It always did, without a word: the whole financial history in iCloud,
/// readable by Apple unless the user has Advanced Data Protection on, while
/// Android deliberately leaves the same file out of its cloud backup (audit
/// P-2). Now it is the user's choice. A new install starts with it off. An
/// existing one keeps the backup it already had, rather than losing its only
/// copy without being told, and can switch it off.
///
/// iOS decides by a flag on each file, which Flutter cannot set, hence the
/// channel to `AppDelegate`. The flag is set again at every launch, because a
/// restored backup is a new file that does not carry it.
abstract final class ICloudBackup {
  static const _channel = MethodChannel('app.satsstack/backup');

  /// Whether this platform has the choice to make.
  static bool get applies => Platform.isIOS;

  /// The stored choice. When there is none yet, decided once and stored: on
  /// for an install that had finished onboarding (it was being backed up),
  /// off otherwise.
  static Future<bool> included(AppDatabase db) async {
    final rows =
        await (db.select(db.appSettings)..where(
          (s) => s.key.isIn([
            AppConstants.settingICloudBackup,
            AppConstants.settingOnboardingComplete,
          ]),
        )).get();
    final values = {for (final r in rows) r.key: r.value};
    final stored = values[AppConstants.settingICloudBackup];
    if (stored != null) return stored == 'true';
    final existing = values[AppConstants.settingOnboardingComplete] == 'true';
    await _store(db, existing);
    return existing;
  }

  /// Records the choice and applies it to the database's files.
  static Future<void> setIncluded(AppDatabase db, bool included) async {
    await _store(db, included);
    await apply(included: included);
  }

  /// Sets the flag on the database file and its companions. Does nothing
  /// off iOS.
  static Future<void> apply({required bool included}) async {
    if (!applies) return;
    final database = await databaseFile();
    for (final file in [database, File('${database.path}-journal')]) {
      if (!file.existsSync()) continue;
      await _channel.invokeMethod<void>('setExcludedFromBackup', {
        'path': file.path,
        'excluded': !included,
      });
    }
  }

  /// [apply]s the stored choice. Called at launch.
  static Future<void> applyStored(AppDatabase db) async {
    if (!applies) return;
    await apply(included: await included(db));
  }

  static Future<void> _store(AppDatabase db, bool included) => db
      .into(db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: AppConstants.settingICloudBackup,
          value: '$included',
        ),
      );
}
