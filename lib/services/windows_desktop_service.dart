import 'dart:io';

import 'package:flutter/services.dart';

import '../models/app_settings.dart';

/// Windows-only: трей, автозапуск, флаг --autostart.
class WindowsDesktopService {
  WindowsDesktopService._();

  static const _channel = MethodChannel('keqdis_vpn_channel');

  static bool get isAutostartLaunch =>
      Platform.isWindows &&
      Platform.executableArguments.contains('--autostart');

  static Future<void> applySettings(AppSettings settings) async {
    if (!Platform.isWindows) return;
    await _channel.invokeMethod<void>('setMinimizeToTray', {
      'enabled': settings.minimizeToTray,
    });
    await _channel.invokeMethod<void>('setLaunchAtStartup', {
      'enabled': settings.launchAtStartup,
    });
  }

  static Future<bool> isLaunchAtStartupEnabled() async {
    if (!Platform.isWindows) return false;
    return await _channel.invokeMethod<bool>('isLaunchAtStartup') ?? false;
  }

  static Future<bool> isProcessElevated() async {
    if (!Platform.isWindows) return false;
    return await _channel.invokeMethod<bool>('requestTunnelPermission') ??
        false;
  }

  /// UAC-диалог и новый процесс с правами администратора; текущий завершается.
  static Future<bool> restartAsAdministrator() async {
    if (!Platform.isWindows) return false;
    try {
      await _channel.invokeMethod<void>('restartAsAdministrator');
      return true;
    } on PlatformException {
      return false;
    }
  }

  /// Убивает осиротевшие xray/sing-box после аварийного выхода и создаёт job object.
  static Future<void> initCoreProcessGuard() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<void>('initCoreProcessGuard');
    } on PlatformException {
      // Non-fatal: tunnel may still work if ports are free.
    }
  }

  /// Эфемерный xray (ping/speed): при падении приложения процесс завершится вместе с ним.
  static Future<void> attachCoreProcess(int pid) async {
    if (!Platform.isWindows || pid <= 0) return;
    try {
      await _channel.invokeMethod<void>('attachCoreProcess', {'pid': pid});
    } on PlatformException {
      // Best-effort.
    }
  }

  /// VPN-сессия: pid-файл для очистки при следующем запуске + job object.
  static Future<void> registerSessionCoreProcesses({
    required int xrayPid,
    int singboxPid = 0,
  }) async {
    if (!Platform.isWindows || xrayPid <= 0) return;
    try {
      await _channel.invokeMethod<void>('registerSessionCoreProcesses', {
        'xrayPid': xrayPid,
        'singboxPid': singboxPid,
      });
    } on PlatformException {
      // Best-effort.
    }
  }

  static Future<void> clearSessionCoreProcesses() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<void>('clearSessionCoreProcesses');
    } on PlatformException {
      // Best-effort.
    }
  }
}
