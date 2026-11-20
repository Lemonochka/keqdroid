import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../core/app_logger.dart';
import '../utils/local_vpn_proxy.dart';
import 'storage_service.dart';
import 'subscription_service.dart';

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

    Future<void>.delayed(
      const Duration(minutes: 2),
      () => unawaited(runDueUpdates()),
    );
  }

  static void dispose() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  static Future<void> onAppResumed() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    await runDueUpdates();
  }

  static Future<void> runDueUpdates() async {
    if (_running) return;
    _running = true;
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final storage = await StorageService.init();
      // состояния VPN тут нет, порт сессии берём с диска
      final proxyPort = await resolveLocalProxyForBackground(
        storage.getActiveLocalHttpPort(),
      );
      final service = SubscriptionService(storage, localProxyPort: proxyPort);
      final due = await service.getDueForUpdate(
        defaultInterval: const Duration(hours: 1),
      );
      if (due.isEmpty) return;

      final results = <UpdateResult>[];
      for (var i = 0; i < due.length; i += 3) {
        final batch = due.skip(i).take(3).toList();
        results.addAll(
          await Future.wait(
            batch.map(service.updateSubscription),
            eagerError: false,
          ),
        );
      }

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
