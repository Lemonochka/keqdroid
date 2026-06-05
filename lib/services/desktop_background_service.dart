import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../core/app_logger.dart';
import 'storage_service.dart';
import 'subscription_service.dart';

/// периодический апдейт подписок на desktop (workmanager только на android)
class DesktopBackgroundService {
  static Timer? _periodicTimer;
  static bool _running = false;

  static Future<void> init() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => unawaited(runDueUpdates()),
    );

    // first check soon after startup, like workmanager initialDelay
    Future<void>.delayed(
      const Duration(minutes: 2),
      () => unawaited(runDueUpdates()),
    );
  }

  static void dispose() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// call on app resume to refresh subscriptions that are due
  static Future<void> onAppResumed() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    await runDueUpdates();
  }

  /// manual trigger (e.g. from settings or subscriptions screen)
  static Future<void> runDueUpdates() async {
    if (_running) return;
    _running = true;
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final storage = await StorageService.init();
      final service = SubscriptionService(storage);
      final due = await service.getDueForUpdate(
        defaultInterval: const Duration(hours: 1),
      );
      if (due.isEmpty) return;

      final results = await Future.wait(
        due.map(service.updateSubscription),
        eagerError: false,
      );

      final ok = results.where((r) => r.success).length;
      final failed = results.length - ok;
      AppLogger.instance.info(
        'Desktop background subscription refresh: $ok ok, $failed failed',
      );
    } catch (e, st) {
      AppLogger.instance.error(
        'Desktop subscription refresh failed',
        error: e,
        stackTrace: st,
      );
    } finally {
      _running = false;
    }
  }
}
