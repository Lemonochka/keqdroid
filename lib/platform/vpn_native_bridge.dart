import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../services/hotkey_service.dart';
import '../utils/system_accent.dart';

class VpnNativeBridge {
  VpnNativeBridge._();

  static const channel = MethodChannel('keqdis_vpn_channel');

  static bool get supportsNotificationLaunch => Platform.isAndroid;
  static bool get supportsDeepLinks => Platform.isAndroid || Platform.isWindows;
  static bool get supportsAutostartNotification => Platform.isWindows;
  static bool get supportsWindowVisibilityEvents => Platform.isWindows;
  static bool get supportsGlobalHotkeys => Platform.isWindows;

  static Future<void> Function(MethodCall call)? _launchHandler;
  static Future<void> Function()? _autostartHandler;
  static void Function(bool visible)? _windowVisibilityHandler;

  static Future<String?> getLaunchAction() async {
    if (!supportsNotificationLaunch) return null;
    return channel.invokeMethod<String>('getLaunchAction');
  }

  static Future<void> clearLaunchAction() async {
    if (!supportsNotificationLaunch) return;
    await channel.invokeMethod<void>('clearLaunchAction');
  }

  static Future<void> setWindowBackgroundColor(int argb) async {
    if (!Platform.isAndroid) return;
    try {
      await channel.invokeMethod<void>('setWindowBackgroundColor', {
        'color': argb,
      });
    } on PlatformException {
      // окно просто останется прежнего цвета
    }
  }

  static Future<String?> getPendingDeepLink() async {
    if (!supportsDeepLinks) return null;
    return channel.invokeMethod<String>('getPendingDeepLink');
  }

  static Future<Map<String, Object?>> getNativeInternals() async {
    if (!Platform.isAndroid) return const {};
    try {
      final info = await channel.invokeMapMethod<String, Object?>(
        'getNativeInternals',
      );
      return info ?? const {};
    } catch (_) {
      return const {};
    }
  }

  static Future<List<Map<Object?, Object?>>> getProcessExits() async {
    if (!Platform.isAndroid) return const [];
    try {
      final list = await channel.invokeListMethod<Object?>('getProcessExits');
      return [
        for (final item in list ?? const <Object?>[])
          if (item is Map) item.cast<Object?, Object?>(),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<SystemAccentCandidates> getSystemAccentCandidates() async {
    if (!Platform.isAndroid) return const SystemAccentCandidates.empty();
    try {
      final map = await channel.invokeMethod<Map<Object?, Object?>>(
        'getSystemAccentColor',
      );
      return SystemAccentCandidates.fromMap(map);
    } catch (_) {
      return const SystemAccentCandidates.empty();
    }
  }

  static final _systemAccentCtrl =
      StreamController<SystemAccentCandidates>.broadcast();

  static Stream<SystemAccentCandidates> get systemAccentChanges =>
      _systemAccentCtrl.stream;

  static bool get supportsSystemAccentEvents => Platform.isAndroid;

  static Future<({int port, String secret})?> getMihomoApi() async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await channel.invokeMethod<Map>('getMihomoApi');
      final port = result?['port'] as int? ?? 0;
      final secret = result?['secret'] as String? ?? '';
      if (port <= 0 || secret.isEmpty) return null;
      return (port: port, secret: secret);
    } catch (_) {
      return null;
    }
  }

  static Future<int?> dialFailures() async {
    if (!Platform.isAndroid) return null;
    try {
      return await channel.invokeMethod<int>('getDialFailures');
    } catch (_) {
      return null;
    }
  }

  static Future<({int count, int changes})?> physicalNetworks() async {
    if (!Platform.isAndroid) return null;
    try {
      final map = await channel.invokeMapMethod<String, Object?>(
        'getPhysicalNetworks',
      );
      final count = map?['count'];
      final changes = map?['changes'];
      if (count is! int || changes is! int || count < 0) return null;
      return (count: count, changes: changes);
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>> resolveConnectionOwners(
    List<Map<String, Object?>> connections,
  ) async {
    if (!Platform.isAndroid || connections.isEmpty) {
      return List.filled(connections.length, '');
    }
    try {
      final names = await channel.invokeListMethod<Object?>(
        'resolveConnectionOwners',
        {'connections': connections},
      );
      if (names == null) return List.filled(connections.length, '');
      return [for (final n in names) n?.toString() ?? ''];
    } catch (_) {
      return List.filled(connections.length, '');
    }
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

  static void registerWindowVisibilityHandler(
    void Function(bool visible)? handler,
  ) {
    _windowVisibilityHandler = handler;
    _syncMethodCallHandler();
  }

  static void _syncMethodCallHandler() {
    final needsHandler = supportsNotificationLaunch ||
        supportsDeepLinks ||
        supportsAutostartNotification ||
        supportsSystemAccentEvents ||
        supportsWindowVisibilityEvents;
    if (!needsHandler) {
      channel.setMethodCallHandler(null);
      return;
    }
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onAutostartConnect' && supportsAutostartNotification) {
        await _autostartHandler?.call();
        return;
      }
      if (call.method == 'onWindowVisibility' && supportsWindowVisibilityEvents) {
        final args = call.arguments;
        final visible = args is Map ? args['visible'] as bool? ?? true : true;
        _windowVisibilityHandler?.call(visible);
        return;
      }
      if (call.method == 'onSystemAccentChanged' && supportsSystemAccentEvents) {
        final args = call.arguments;
        _systemAccentCtrl.add(
          SystemAccentCandidates.fromMap(args is Map ? args : null),
        );
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

