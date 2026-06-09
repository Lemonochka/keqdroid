import 'dart:io';

import '../services/desktop_background_service.dart';
import '../services/windows_desktop_service.dart';

/// Platform init before runApp (Windows desktop shell).
class PlatformBootstrap {
  static Future<void> initialize() async {
    if (Platform.isWindows) {
      await WindowsDesktopService.initCoreProcessGuard();
      await DesktopBackgroundService.init();
    }
  }

  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}
