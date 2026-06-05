import 'dart:io';

import 'package:flutter/services.dart';

/// android: действия из уведомления; windows — dart tunnel backend
class VpnNativeBridge {
  VpnNativeBridge._();

  static const channel = MethodChannel('keqdis_vpn_channel');

  static bool get supportsNotificationLaunch => Platform.isAndroid;

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
    if (!supportsNotificationLaunch) {
      channel.setMethodCallHandler(null);
      return;
    }
    channel.setMethodCallHandler(handler);
  }
}
