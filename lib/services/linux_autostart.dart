import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../core/app_logger.dart';
import 'linux_appimage_updater.dart';
import 'linux_desktop_entry.dart';

class LinuxAutostart {
  LinuxAutostart._();

  static const flag = '--autostart';
  static const _fileName = 'keqdroid.desktop';

  static const _marker = 'X-KeqDroid-Autostart=true';

  @visibleForTesting
  static String? configHomeOverride;

  // менеджер systemd пользователя может пережить выход из сессии, и без reload следующий вход новых файлов не увидит
  @visibleForTesting
  static Future<void> Function() reloadUserUnits = () async {
    try {
      await Process.run('systemctl', ['--user', 'daemon-reload']);
    } catch (_) {}
  };

  // Hyprland без uwsm (так у caelestia) ~/.config/autostart не читает и поднимает только hyprland-session.target.
  // цепляем к ней службу, которую systemd-xdg-autostart-generator делает из ярлыка: под uwsm и в GNOME/KDE запуск остаётся один
  static const _generatedUnit = 'app-keqdroid@autostart.service';

  static String _configHome() {
    final override = configHomeOverride;
    if (override != null) return override;
    final home = Platform.environment['HOME'] ?? '';
    return Platform.environment['XDG_CONFIG_HOME'] ?? p.join(home, '.config');
  }

  static File _file() => File(p.join(_configHome(), 'autostart', _fileName));

  static File _hyprlandDropIn() => File(p.join(_configHome(), 'systemd', 'user',
      'hyprland-session.target.d', 'keqdroid.conf'));

  static Future<bool> _syncHyprlandDropIn(bool wanted) async {
    final file = _hyprlandDropIn();
    if (!wanted) {
      if (!file.existsSync()) return false;
      await file.delete();
      return true;
    }
    const content = '[Unit]\nWants=$_generatedUnit\n';
    if (file.existsSync() && await file.readAsString() == content) return false;
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return true;
  }

  // сам AppImage: бинарь во временном монте исчезает вместе с процессом
  static String _target() =>
      LinuxAppImageUpdater.currentAppImagePath() ?? Platform.resolvedExecutable;

  static bool isEnabled() {
    try {
      final file = _file();
      return file.existsSync() && file.readAsStringSync().contains(_marker);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> setEnabled(bool enabled) async {
    try {
      final file = _file();
      if (!enabled) {
        if (isEnabled()) await file.delete();
        await _syncHyprlandDropIn(false);
        await reloadUserUnits();
        return true;
      }
      if (file.existsSync() && !isEnabled()) return false;
      await file.parent.create(recursive: true);
      await file.writeAsString(contentFor(_target()));
      await _syncHyprlandDropIn(true);
      await reloadUserUnits();
      return true;
    } catch (e, st) {
      AppLogger.instance.warn(
        'Could not change Linux autostart',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  static Future<void> refresh() async {
    final enabled = isEnabled();
    try {
      var changed = false;
      if (enabled) {
        final content = contentFor(_target());
        if (await _file().readAsString() != content) {
          await _file().writeAsString(content);
          changed = true;
        }
      }
      if (await _syncHyprlandDropIn(enabled)) changed = true;
      if (changed) await reloadUserUnits();
    } catch (_) {}
  }

  // раннер аргументы в Dart не передаёт, читаем /proc/self/cmdline
  static bool launchedAtLogin() {
    try {
      final raw = File('/proc/self/cmdline').readAsStringSync();
      return raw.split('\u0000').contains(flag);
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static String contentFor(String target) => [
        '[Desktop Entry]',
        'Type=Application',
        'Name=KeqDroid',
        'Exec=${LinuxDesktopEntry.execArgument(target)} $flag',
        'Icon=keqdroid',
        'Terminal=false',
        'X-GNOME-Autostart-enabled=true',
        _marker,
        '',
      ].join('\n');
}
