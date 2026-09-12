import 'dart:io';

import 'package:flutter/services.dart';

import '../models/app_settings.dart';

/// Windows-only: трей, автозапуск, флаг --autostart.
class WindowsDesktopService {
  WindowsDesktopService._();

  static const _channel = MethodChannel('keqdis_vpn_channel');

  static Future<bool> isAutostartLaunch() async {
    if (!Platform.isWindows) return false;
    if (Platform.executableArguments.contains('--autostart')) return true;
    return await _channel.invokeMethod<bool>('isAutostartLaunch') ?? false;
  }

  static Future<void> applySettings(AppSettings settings) async {
    if (!Platform.isWindows) return;
    await _channel.invokeMethod<void>('setMinimizeToTray', {
      'enabled': settings.minimizeToTray,
    });
    // allowElevation здесь снят: это приведение системы к сохранённым
    // настройкам при запуске, и спрашивать UAC на каждом запуске нельзя.
    await applyLaunchAtStartup(
      enabled: settings.launchAtStartup,
      elevated: settings.launchAtStartupElevated,
    );
  }

  /// Приводит автозапуск Windows к заданному виду.
  ///
  /// [elevated] — стартовать сразу с правами администратора (задача
  /// планировщика вместо ключа Run). Создать или снести такую задачу может
  /// только администратор, поэтому смена этого режима требует [allowElevation]
  /// и показывает UAC — один раз, а не при каждом входе в систему.
  ///
  /// false — задачу не создали и не удалили (отказ от UAC, нет прав). Обычный
  /// автозапуск при этом уже выставлен, приложение стартовать будет.
  static Future<bool> applyLaunchAtStartup({
    required bool enabled,
    required bool elevated,
    bool allowElevation = false,
  }) async {
    if (!Platform.isWindows) return false;
    try {
      return await _channel.invokeMethod<bool>('setLaunchAtStartup', {
            'enabled': enabled,
            'elevated': elevated,
            'allowElevation': allowElevation,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> isLaunchAtStartupEnabled() async {
    if (!Platform.isWindows) return false;
    return await _channel.invokeMethod<bool>('isLaunchAtStartup') ?? false;
  }

  /// Есть ли задача планировщика, поднимающая именно этот exe.
  ///
  /// Спрашивается у системы, а не у настроек: задачу могли снести руками, а
  /// папку с приложением — перенести, и тогда сохранённый флаг врёт.
  static Future<bool> isLaunchAtStartupElevated() async {
    if (!Platform.isWindows) return false;
    try {
      return await _channel.invokeMethod<bool>('isLaunchAtStartupElevated') ??
          false;
    } on PlatformException {
      return false;
    }
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

  static Future<bool> restoreMainWindow() async {
    if (!Platform.isWindows) return false;
    return await _channel.invokeMethod<bool>('restoreMainWindow') ?? false;
  }

  /// Хоткей «показать/скрыть»: видимое окно прячется в трей, скрытое — наверх.
  static Future<bool> toggleMainWindow() async {
    if (!Platform.isWindows) return false;
    return await _channel.invokeMethod<bool>('toggleMainWindow') ?? false;
  }

  static Future<void> exitApp() async {
    if (!Platform.isWindows) return;
    await _channel.invokeMethod<void>('exitApp');
  }
}
