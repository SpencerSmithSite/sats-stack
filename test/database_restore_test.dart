/// Settings → Data → Import, at the file level.
///
/// The import closes the database before copying the backup in. A failed copy
/// used to show a snackbar and carry on with the database still closed, so
/// every later query in the session threw — and the copy could have stopped
/// partway, leaving a torn file for the next launch to open.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';

void main() {
  late Directory dir;
  late File target;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('restore_test');
    target = File('${dir.path}/sats_stack.sqlite')
      ..writeAsStringSync('the user own data');
  });

  tearDown(() => dir.delete(recursive: true));

  test('a good backup replaces the database and keeps the original', () async {
    final source = File('${dir.path}/backup.sqlite')
      ..writeAsStringSync('the backup');

    final r = await replaceDatabaseFile(source: source, target: target);

    expect(r.outcome, RestoreOutcome.replaced);
    expect(target.readAsStringSync(), 'the backup');
    expect(File('${target.path}.bak').readAsStringSync(), 'the user own data');
  });

  test('a copy that fails partway puts the original back', () async {
    final source = File('${dir.path}/backup.sqlite')
      ..writeAsStringSync('the backup');

    // Half a file written over the database, then the disk fills. A source
    // that is simply missing throws before the target is touched, which is
    // what this used to test — and it passed with the restore step deleted.
    final r = await replaceDatabaseFile(
      source: source,
      target: target,
      copy: (from, to) async {
        File(to).writeAsStringSync('the bac');
        throw const FileSystemException('No space left on device');
      },
    );

    expect(r.outcome, RestoreOutcome.failedOriginalRestored);
    expect(r.error, isA<FileSystemException>());
    expect(target.readAsStringSync(), 'the user own data');
  });

  test(
    'with no database to keep, a failure says the original is lost',
    () async {
      target.deleteSync();
      final r = await replaceDatabaseFile(
        source: File('${dir.path}/gone.sqlite'),
        target: target,
      );
      expect(r.outcome, RestoreOutcome.failedOriginalLost);
    },
  );
}
