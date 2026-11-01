import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/database/database.dart';
import '../../../core/services/icloud_backup.dart';
import '../../../main.dart' as app;
import '../../../shared/theme/app_colors.dart';

/// Settings → Data: export the database, and replace it from a backup.
class DataSection extends StatefulWidget {
  const DataSection({super.key, bool? showICloudChoice})
    : _showICloudChoice = showICloudChoice;

  /// Whether to offer the iCloud backup choice — iOS only, unless a test says
  /// otherwise.
  final bool? _showICloudChoice;

  @override
  State<DataSection> createState() => _DataSectionState();
}

class _DataSectionState extends State<DataSection> {
  late final bool _showICloud =
      widget._showICloudChoice ?? ICloudBackup.applies;

  /// Null until read.
  bool? _inICloud;

  @override
  void initState() {
    super.initState();
    if (_showICloud) _loadICloud();
  }

  Future<void> _loadICloud() async {
    final included = await ICloudBackup.included(app.db);
    if (mounted) setState(() => _inICloud = included);
  }

  Future<void> _setICloud(bool included) async {
    setState(() => _inICloud = included);
    try {
      await ICloudBackup.setIncluded(app.db, included);
    } catch (e) {
      if (mounted) {
        setState(() => _inICloud = !included);
        _showSnack('Could not change the backup setting: $e');
      }
    }
  }

  Future<void> _exportDb() async {
    try {
      final dbFile = await databaseFile();
      if (!mounted) return;
      if (!dbFile.existsSync()) {
        _showSnack('Database file not found');
        return;
      }
      // The bytes go to the dialog, which writes them: on iOS and Android it
      // will not hand back a path to write to, and threw without them.
      final bytes = await databaseSnapshot(app.db);
      if (!mounted) return;
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Sats Stack database',
        fileName: 'sats_stack_backup.sqlite',
        allowedExtensions: ['sqlite', 'db'],
        type: FileType.custom,
        bytes: bytes,
      );
      if (savePath == null) return;

      if (!mounted) return;
      _showSnack('Database exported successfully');
    } catch (e) {
      if (mounted) _showSnack('Export failed: $e');
    }
  }

  Future<void> _importDb() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Import database?'),
            content: const Text(
              'This will replace all current data with the selected backup. The app will need to restart.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                ),
                child: const Text('Replace & Restart'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select Sats Stack backup',
        allowedExtensions: ['sqlite', 'db'],
        type: FileType.custom,
      );
      if (result == null || result.files.single.path == null) return;

      final srcFile = File(result.files.single.path!);
      // Opened as a copy and checked before anything is replaced: the
      // header check alone let a damaged backup through, and the app then
      // could not launch.
      final problem = await backupProblem(
        srcFile,
        schemaVersion: app.db.schemaVersion,
      );
      if (problem != null) {
        if (mounted) _showSnack('$problem — nothing changed');
        return;
      }

      final dbFile = await databaseFile();

      await app.db.close();
      // From here the database is closed for the rest of this process —
      // `AppDatabase` is opened once, before runApp, and cannot be reopened
      // underneath the services holding it. So every outcome ends at "quit and
      // relaunch". A failure used to show a snackbar and carry on, and every
      // query after it threw.
      final restore = await replaceDatabaseFile(
        source: srcFile,
        target: dbFile,
      );
      if (!mounted) return;
      await _showRelaunchDialog(
        title:
            restore.outcome == RestoreOutcome.replaced
                ? 'Import complete'
                : 'Import failed',
        body: switch (restore.outcome) {
          RestoreOutcome.replaced =>
            'The database has been replaced. Quit '
                'and reopen Sats Stack to load the imported data. Your '
                'previous data is kept until it opens, then deleted.',
          RestoreOutcome.failedOriginalRestored =>
            'The backup could not be '
                'copied in (${restore.error}). Your previous data has been put '
                'back. Quit and reopen Sats Stack to keep using it.',
          RestoreOutcome.failedOriginalLost =>
            'The backup could not be '
                'copied in (${restore.error}), and your previous database could '
                'not be put back automatically. A copy of it is at '
                '${dbFile.path}.bak. Quit and reopen Sats Stack.',
        },
      );
    } catch (e) {
      // Only reached before the database is closed — the picker or the
      // header check — so carrying on is safe here.
      if (mounted) _showSnack('Import failed: $e');
    }
  }

  /// A dialog that can only be left by quitting, for when the database has
  /// been closed and this process can no longer use it.
  Future<void> _showRelaunchDialog({
    required String title,
    required String body,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => PopScope(
            canPop: false,
            child: AlertDialog(
              title: Text(title),
              content: Text(body),
              actions: [
                FilledButton(
                  onPressed: () => exit(0),
                  child: const Text('Quit'),
                ),
              ],
            ),
          ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.upload_outlined),
          title: const Text('Export database'),
          subtitle: const Text('Save a copy of your SQLite file'),
          onTap: _exportDb,
        ),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('Import database'),
          subtitle: const Text('Replace current data from a backup'),
          onTap: _importDb,
        ),
        if (_showICloud && _inICloud != null)
          SwitchListTile(
            secondary: const Icon(Icons.cloud_outlined),
            title: const Text('Include in iCloud backup'),
            subtitle: Text(
              _inICloud!
                  ? 'Your transactions, wallets and settings go into this '
                      "iPhone's iCloud backup, so a restored phone has them. "
                      'iCloud backups are end-to-end encrypted only with '
                      'Advanced Data Protection turned on; without it, Apple '
                      'can read them.'
                  : 'Your data stays on this iPhone and is left out of '
                      'iCloud backups. A new or restored phone starts empty: '
                      'use Export database to move it.',
            ),
            isThreeLine: true,
            value: _inICloud!,
            onChanged: _setICloud,
          ),
      ],
    );
  }
}
