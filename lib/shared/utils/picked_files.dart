import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Deletes [path] if it is the app's own copy of a picked file, and never
/// otherwise.
///
/// On a phone, the file and image pickers copy what the user chose — a whole
/// bank statement, a photo of one — into the app's temporary or cache folder,
/// and nothing deleted the copy: it stayed on disk after the import, outside
/// the database "Reset all data" clears (audit A-7). On a desktop the picker
/// hands back the user's own file instead, which must not be touched — so
/// only a path inside one of [tempDirs] (by default the app's temporary and
/// cache folders) is deleted.
Future<void> discardPickedCopy(String path, {List<String>? tempDirs}) async {
  // Only phones' pickers copy; elsewhere the temporary folder can be a shared
  // /tmp the user picked from.
  if (tempDirs == null && !Platform.isIOS && !Platform.isAndroid) return;
  try {
    final dirs =
        tempDirs ??
        [Directory.systemTemp.path, (await getTemporaryDirectory()).path];
    if (!dirs.any((dir) => p.isWithin(dir, path))) return;
    final file = File(path);
    if (file.existsSync()) await file.delete();
  } catch (_) {
    // Best effort: a copy that cannot be deleted now is in a folder the
    // system clears on its own.
  }
}
