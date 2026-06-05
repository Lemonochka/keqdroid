import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../core/app_logger.dart';
import '../services/background_service.dart';
import '../services/desktop_background_service.dart';
import '../services/notification_service.dart';

/// платформенный init до runApp
class PlatformBootstrap {
  static Future<void> initialize() async {
    if (Platform.isAndroid) {
      try {
        await Firebase.initializeApp();
      } catch (e, st) {
        AppLogger.instance.warn(
          'Firebase is not configured. Crash reporting is disabled.',
          error: e,
          stackTrace: st,
        );
      }
      await BackgroundService.init();
      await BackgroundService.registerPeriodicTask();
      await NotificationService.init();
      return;
    }

    if (Platform.isWindows) {
      try {
        await Firebase.initializeApp();
      } catch (_) {
        // Desktop may ship without Firebase options.
      }
      await DesktopBackgroundService.init();
      return;
    }

    if (!kIsWeb) {
      try {
        await Firebase.initializeApp();
      } catch (_) {}
    }
  }

  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}
