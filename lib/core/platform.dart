import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Безопасные проверки платформы (dart:io Platform нельзя трогать в веб-версии).
class Plat {
  static bool get web => kIsWeb;
  static bool get windows => !kIsWeb && Platform.isWindows;
  static bool get macos => !kIsWeb && Platform.isMacOS;
  static bool get linux => !kIsWeb && Platform.isLinux;
  static bool get android => !kIsWeb && Platform.isAndroid;
  static bool get ios => !kIsWeb && Platform.isIOS;
  static bool get desktop => windows || macos || linux;
  static bool get mobile => android || ios;
}
