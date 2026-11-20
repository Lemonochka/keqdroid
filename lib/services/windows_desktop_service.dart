import 'dart:io';

import 'package:flutter/services.dart';

import '../core/app_logger.dart';
import '../models/app_settings.dart';
import 'windows_prefs_store.dart';
import 'windows_tun_service.dart';

class WindowsDesktopService {
  WindowsDesktopService._();

  static const _channel = MethodChannel('keqdroid_vpn_channel');

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
    // раннер решает до первого кадра, а настройки Dart к тому времени ещё не прочитаны
    await _channel.invokeMethod<void>('setAutostartInTray', {
      'enabled': settings.autostartInTray,
    });
    // без UAC: это приведение системы к настройкам на каждом запуске
    await applyLaunchAtStartup(
      enabled: settings.launchAtStartup,
      elevated: settings.launchAtStartupElevated,
    );
  }

  static Future<bool> applyLaunchAtStartup({
    required bool enabled,
    required bool elevated,
    bool allowElevation = false,
    // снять выключатель Диспетчера задач, только по нажатию пользователя
    bool approve = false,
  }) async {
    if (!Platform.isWindows) return false;
    try {
      return await _channel.invokeMethod<bool>('setLaunchAtStartup', {
            'enabled': enabled,
            'elevated': elevated,
            'allowElevation': allowElevation,
            'approve': approve,
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

  static Future<bool> isLaunchAtStartupBlocked() async {
    if (!Platform.isWindows) return false;
    try {
      return await _channel.invokeMethod<bool>('isLaunchAtStartupBlocked') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  // спрашиваем систему: задачу могли снести руками или перенести папку
  static Future<bool> isLaunchAtStartupElevated() async {
    if (!Platform.isWindows) return false;
    try {
      return await _channel.invokeMethod<bool>('isLaunchAtStartupElevated') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  // приложение, запущенное старой задачей, уже с правами: и служба для TUN, и снятие задачи проходят без окна UAC.
  // без службы задачу не трогаем, иначе после следующего входа TUN не поднимется
  static Future<bool> retireElevatedAutostart({required bool tun}) async {
    if (!Platform.isWindows) return false;
    if (!await isProcessElevated() || !await isLaunchAtStartupElevated()) {
      return false;
    }
    if (tun && await WindowsTunService.state() != TunServiceState.ready) {
      final installed = await WindowsTunService.install();
      if (!installed.ok ||
          await WindowsTunService.state() != TunServiceState.ready) {
        return false;
      }
    }
    return applyLaunchAtStartup(
      enabled: true,
      elevated: false,
      allowElevation: true,
    );
  }

  static Future<bool> isProcessElevated() async {
    if (!Platform.isWindows) return false;
    return await _channel.invokeMethod<bool>('requestTunnelPermission') ??
        false;
  }

  static Future<bool> restartAsAdministrator() async {
    if (!Platform.isWindows) return false;
    try {
      await _flushBeforeNativeExit();
      await _channel.invokeMethod<void>('restartAsAdministrator');
      return true;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> initCoreProcessGuard() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<void>('initCoreProcessGuard');
    } on PlatformException {
      // не смертельно, порты могут быть свободны
    }
  }

  static Future<void> attachCoreProcess(int pid) async {
    if (!Platform.isWindows || pid <= 0) return;
    try {
      await _channel.invokeMethod<void>('attachCoreProcess', {'pid': pid});
    } on PlatformException {
      // не вышло, не страшно
    }
  }

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
      // не вышло, не страшно
    }
  }

  static Future<List<String>> removeStaleTunAdapters(
    List<String> instanceIds,
  ) async {
    if (!Platform.isWindows) return const [];
    try {
      final removed = await _channel.invokeListMethod<String>(
        'removeStaleTunAdapters',
        {'instanceIds': instanceIds},
      );
      return removed ?? const [];
    } on PlatformException {
      return const [];
    }
  }

  static Future<void> clearSessionCoreProcesses() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<void>('clearSessionCoreProcesses');
    } on PlatformException {
      // не вышло, не страшно
    }
  }

  static Future<String?> tunBypassInterface({
    required int tunIndex,
    required bool mihomoRule,
  }) async {
    if (!Platform.isWindows || tunIndex <= 0) return null;
    try {
      final alias = await _channel.invokeMethod<String>('getTunBypassInterface', {
        'tunIndex': tunIndex,
        'rule': mihomoRule ? 'mihomo' : 'xray',
      });
      return alias == null || alias.isEmpty ? null : alias;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<bool> isHiddenInTray() async {
    if (!Platform.isWindows) return false;
    try {
      return await _channel.invokeMethod<bool>('isHiddenInTray') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> restoreMainWindow() async {
    if (!Platform.isWindows) return false;
    return await _channel.invokeMethod<bool>('restoreMainWindow') ?? false;
  }

  static Future<bool> toggleMainWindow() async {
    if (!Platform.isWindows) return false;
    return await _channel.invokeMethod<bool>('toggleMainWindow') ?? false;
  }

  static Future<void> exitApp() async {
    if (!Platform.isWindows) return;
    await _flushBeforeNativeExit();
    await _channel.invokeMethod<void>('exitApp');
  }

  // настройки и журнал пишутся не в потоке интерфейса, а нативный выход гасит процесс сразу
  static Future<void> _flushBeforeNativeExit() async {
    await WindowsPrefsStore.flushInstance();
    await AppLogger.instance.flush();
  }
}
