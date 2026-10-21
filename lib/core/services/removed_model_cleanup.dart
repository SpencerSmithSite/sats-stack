/// Frees the disk space taken by the removed downloadable-model backend.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Deletes model weights an earlier build downloaded.
///
/// The downloadable-model backend was removed on 2026-10-20 with the
/// discontinued `flutter_gemma` package. Its models were 0.6–5 GB each, and
/// with the backend gone no screen could delete them — they would sit in the
/// app's storage for good. This removes them, and only them: the database
/// lives in the same Documents folder, so matching is by exact file name, and
/// the one directory removed wholesale is the package's own.
abstract final class RemovedModelCleanup {
  /// Every model file the removed catalogue could download.
  static const modelFileNames = [
    'qwen3_0_6b_mixed_int4.litertlm',
    'Qwen3_1.7B.litertlm',
    'qwen3_4b_instruct_2507_mixed_int4.litertlm',
    'qwen3_8b_mixed_int4.litertlm',
  ];

  /// Runs against this device's real directories. Never throws: a cleanup
  /// that fails must not stop the app starting.
  static Future<void> runHere() async {
    try {
      await run(
        documents: await getApplicationDocumentsDirectory(),
        support: await getApplicationSupportDirectory(),
      );
    } catch (_) {}
  }

  /// Deletes the weights from where `flutter_gemma` kept them: Documents on
  /// iOS and Android (and on macOS before its 0.15.1), and a `flutter_gemma`
  /// folder in Application Support on macOS. A model file's partial download
  /// (`<name>.part`, `<name>.tmp`) goes with it. Returns the bytes freed.
  static Future<int> run({
    required Directory documents,
    required Directory support,
  }) async {
    var freed = 0;

    if (await documents.exists()) {
      await for (final entity in documents.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        final isModel = modelFileNames.any(
          (m) => name == m || name.startsWith('$m.'),
        );
        if (!isModel) continue;
        freed += await entity.length();
        await entity.delete();
      }
    }

    final packageDir = Directory(p.join(support.path, 'flutter_gemma'));
    if (await packageDir.exists()) {
      await for (final entity in packageDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) freed += await entity.length();
      }
      await packageDir.delete(recursive: true);
    }

    return freed;
  }
}
