import 'dart:io';

import 'package:flutter/services.dart';

import '../services/hotkey_service.dart';

/// android: действия из уведомления; windows: автоподключение, меню трея и хоткеи
class VpnNativeBridge {
  VpnNativeBridge._();

  static const channel = MethodChannel('keqdis_vpn_channel');

  static bool get supportsNotificationLaunch => Platform.isAndroid;
  static bool get supportsDeepLinks => Platform.isAndroid;
  static bool get supportsAutostartNotification => Platform.isWindows;
  static bool get supportsTrayMenu => Platform.isWindows;
  static bool get supportsGlobalHotkeys => Platform.isWindows;

  static Future<void> Function(MethodCall call)? _launchHandler;
  static Future<void> Function()? _autostartHandler;
  static Future<void> Function(MethodCall call)? _trayMenuHandler;
  static Future<void> Function()? _trayMenuCloseHandler;
  static void Function(bool visible)? _windowVisibilityHandler;

  static Future<String?> getLaunchAction() async {
    if (!supportsNotificationLaunch) return null;
    return channel.invokeMethod<String>('getLaunchAction');
  }

  static Future<void> clearLaunchAction() async {
    if (!supportsNotificationLaunch) return;
    await channel.invokeMethod<void>('clearLaunchAction');
  }

  /// Ссылка vless://…, с которой систему попросили открыть приложение
  /// (холодный старт). Одноразовая: натив отдаёт и забывает её.
  static Future<String?> getPendingDeepLink() async {
    if (!supportsDeepLinks) return null;
    return channel.invokeMethod<String>('getPendingDeepLink');
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

  static void registerTrayMenuHandler(
    Future<void> Function(MethodCall call)? handler,
  ) {
    _trayMenuHandler = handler;
    _syncMethodCallHandler();
  }

  static void registerTrayMenuCloseHandler(
    Future<void> Function()? handler,
  ) {
    _trayMenuCloseHandler = handler;
    _syncMethodCallHandler();
  }

  /// Windows: окно скрыто в трей / восстановлено (нативный `onWindowVisibility`).
  static void registerWindowVisibilityHandler(
    void Function(bool visible)? handler,
  ) {
    _windowVisibilityHandler = handler;
    _syncMethodCallHandler();
  }

  static void _syncMethodCallHandler() {
    final needsHandler = supportsNotificationLaunch ||
        supportsAutostartNotification ||
        supportsTrayMenu;
    if (!needsHandler) {
      channel.setMethodCallHandler(null);
      return;
    }
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onAutostartConnect' && supportsAutostartNotification) {
        await _autostartHandler?.call();
        return;
      }
      if (call.method == 'onTrayMenuOpen' && supportsTrayMenu) {
        await _trayMenuHandler?.call(call);
        return;
      }
      if (call.method == 'onTrayMenuClose' && supportsTrayMenu) {
        await _trayMenuCloseHandler?.call();
        return;
      }
      if (call.method == 'onWindowVisibility' && supportsTrayMenu) {
        final args = call.arguments;
        final visible = args is Map ? args['visible'] as bool? ?? true : true;
        _windowVisibilityHandler?.call(visible);
        return;
      }
      if (call.method == 'onHotkeyPressed' && supportsGlobalHotkeys) {
        final args = call.arguments;
        HotkeyService.dispatchAction(
          args is Map ? args['action'] as String? : null,
        );
        return;
      }
      await _launchHandler?.call(call);
    });
  }
}

