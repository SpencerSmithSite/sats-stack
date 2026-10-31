import 'dart:io';

import 'package:flutter/material.dart';

import '../core/database/database.dart';
import '../shared/theme/app_theme.dart';

/// Shown instead of the app when its database cannot be opened.
///
/// A database that failed to open threw inside `main()`, before anything was
/// drawn, so the app could not launch at all — and the user's previous data,
/// kept as a `.bak` by the last restore, was unreachable (audit D-5). This
/// says what happened and, when that copy exists, puts it back.
class DatabaseRecoveryApp extends StatelessWidget {
  const DatabaseRecoveryApp({
    super.key,
    required this.database,
    required this.error,
  });

  final File database;
  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: _RecoveryScreen(database: database, error: error),
    );
  }
}

class _RecoveryScreen extends StatefulWidget {
  const _RecoveryScreen({required this.database, required this.error});

  final File database;
  final Object error;

  @override
  State<_RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<_RecoveryScreen> {
  late final bool _hasBackup = restoreBackupFor(widget.database).existsSync();
  bool _putBack = false;
  String? _failure;

  /// Copies the `.bak` over the database. Any journal left beside the broken
  /// file goes first: sqlite would otherwise replay it onto the restored one.
  Future<void> _restore() async {
    try {
      for (final suffix in ['-journal', '-wal', '-shm']) {
        final leftover = File('${widget.database.path}$suffix');
        if (leftover.existsSync()) await leftover.delete();
      }
      await restoreBackupFor(widget.database).copy(widget.database.path);
      await discardRestoreBackup(widget.database);
      if (mounted) setState(() => _putBack = true);
    } catch (e) {
      if (mounted) setState(() => _failure = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.storage_outlined, size: 40),
              const SizedBox(height: 16),
              Text(
                _putBack
                    ? 'Your previous data is back'
                    : 'Sats Stack could not open its data',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              if (_putBack)
                const Text('Quit and reopen Sats Stack to use it.')
              else ...[
                Text(
                  _hasBackup
                      ? 'This usually follows restoring a damaged backup. The '
                          'data you had before that restore is still here, '
                          'and can be put back.'
                      : 'Nothing has been deleted. The database is at the '
                          'path below; keep a copy of it before reinstalling.',
                ),
                const SizedBox(height: 12),
                SelectableText(
                  '${widget.database.path}\n\n${widget.error}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (_failure != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Could not put it back: $_failure',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (_hasBackup && !_putBack)
                FilledButton(
                  onPressed: _restore,
                  child: const Text('Put back the previous data'),
                ),
              if (_putBack || !_hasBackup)
                FilledButton(
                  onPressed: () => exit(0),
                  child: const Text('Quit'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
