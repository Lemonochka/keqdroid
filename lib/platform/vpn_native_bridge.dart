import 'dart:io';

import 'package:flutter/services.dart';

/// android: действия из уведомления; windows: автоподключение при автозапуске
class VpnNativeBridge {
  VpnNativeBridge._();

  static const channel = MethodChannel('keqdis_vpn_channel');

  static bool get supportsNotificationLaunch => Platform.isAndroid;
  static bool get supportsAutostartNotification => Platform.isWindows;

  static Future<void> Function(MethodCall call)? _launchHandler;
  static Future<void> Function()? _autostartHandler;

  static Future<String?> getLaunchAction() async {
    if (!supportsNotificationLaunch) return null;
    return channel.invokeMethod<String>('getLaunchAction');
  }

  static Future<void> clearLaunchAction() async {
    if (!supportsNotificationLaunch) return;
    await channel.invokeMethod<void>('clearLaunchAction');
  }

  static void registerLaunchHandler(
    Future<void> Function(MethodCall call)? handler,
  ) {
    _launchHandler = handler;
    _syncMethodCallHandler();
  }

  static void registerAutostartHandler(
    Future<void> Function()? handler,
  ) {
    _autostartHandler = handler;
    _syncMethodCallHandler();
  }

  static void _syncMethodCallHandler() {
    if (!supportsNotificationLaunch && !supportsAutostartNotification) {
      channel.setMethodCallHandler(null);
      return;
    }
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onAutostartConnect' && supportsAutostartNotification) {
        await _autostartHandler?.call();
        return;
      }
      await _launchHandler?.call(call);
    });
  }
}
