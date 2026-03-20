import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

abstract final class PlatformUtils {
  static bool get isDesktop =>
      !kIsWeb &&
      (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  static bool get isMobile =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);
}
