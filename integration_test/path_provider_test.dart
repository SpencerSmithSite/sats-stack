import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// Proves the app's folders resolve on this platform.
///
/// `path_provider` 2.6 on Apple platforms, and 2.3 on Android, reach the OS
/// through FFI built by native-asset hooks rather than through a plugin
/// channel, so a broken hook shows up only on a real engine. The database
/// lives in the support folder, so the symptom in the app would be the
/// "database could not be opened" screen at launch. Run with:
///
///   flutter test integration_test/path_provider_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the support and temporary folders resolve', (_) async {
    for (final dir in [
      await getApplicationSupportDirectory(),
      await getApplicationDocumentsDirectory(),
      await getTemporaryDirectory(),
    ]) {
      expect(dir.path, isNotEmpty);
      await dir.create(recursive: true);
      final probe = File('${dir.path}/.path_provider_probe');
      await probe.writeAsString('ok');
      expect(await probe.readAsString(), 'ok');
      await probe.delete();
    }
  });
}
