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

  // Hyprland без systemd-сборки цели не имеет вовсе (так у caelestia на EndeavourOS), и без uwsm ярлык не исполнит никто.
  // остаётся его собственный запуск при старте; строку ставим только там, иначе приложение стартовало бы дважды
  static const _hyprMarker = 'keqdroid autostart, added and removed by the app';

  @visibleForTesting
  static bool Function() hyprlandSession = () =>
      (Platform.environment['XDG_CURRENT_DESKTOP'] ?? '')
          .toLowerCase()
          .contains('hyprland');

  @visibleForTesting
  static Future<bool> Function() desktopRunsAutostart = () async {
    for (final unit in const [
      'xdg-desktop-autostart.target',
      'hyprland-session.target',
    ]) {
      try {
        final r = await Process.run(
            'systemctl', ['--user', 'is-active', '--quiet', unit]);
        if (r.exitCode == 0) return true;
      } catch (_) {}
    }
    return false;
  };

  // caelestia подключает свой пустой hypr-user.lua именно для пользовательских строк
  static List<File> _hyprlandConfigs() {
    final home = _configHome();
    return [
      File(p.join(home, 'caelestia', 'hypr-user.lua')),
      File(p.join(home, 'hypr', 'hyprland.lua')),
      File(p.join(home, 'hypr', 'hyprland.conf')),
    ];
  }

  @visibleForTesting
  static String hyprlandLines(String target, {required bool lua}) {
    final command = "'${target.replaceAll("'", r"'\''")}' $flag";
    if (lua) {
      final literal =
          command.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      return '-- $_hyprMarker\n'
          'hl.on("hyprland.start", function() hl.exec_cmd("$literal") end)\n';
    }
    // в hyprlang решётка начинает комментарий, буквальная пишется двойной
    return '# $_hyprMarker\nexec-once = ${command.replaceAll('#', '##')}\n';
  }

  static String _withoutHyprlandLines(String text) {
    final lines = text.split('\n');
    final out = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].contains(_hyprMarker)) {
        // строку запуска могли стереть руками, тогда под меткой уже чужая
        if (i + 1 < lines.length && lines[i + 1].contains(flag)) i++;
        continue;
      }
      out.add(lines[i]);
    }
    return out.join('\n');
  }

  static Future<bool> _syncHyprlandConfig(bool wanted) async {
    var changed = false;
    File? into;
    for (final file in _hyprlandConfigs()) {
      if (!file.existsSync()) continue;
      into ??= file;
      final text = await file.readAsString();
      var next = _withoutHyprlandLines(text);
      if (wanted && identical(file, into)) {
        if (next.isNotEmpty && !next.endsWith('\n')) next += '\n';
        next += hyprlandLines(_target(), lua: file.path.endsWith('.lua'));
      }
      if (next != text) {
        await file.writeAsString(next);
        changed = true;
      }
    }
    return changed;
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
        await _syncHyprlandConfig(false);
        await reloadUserUnits();
        return true;
      }
      if (file.existsSync() && !isEnabled()) return false;
      await file.parent.create(recursive: true);
      await file.writeAsString(contentFor(_target()));
      await _syncHyprlandDropIn(true);
      if (hyprlandSession()) {
        await _syncHyprlandConfig(!await desktopRunsAutostart());
      }
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
      // вне Hyprland конфиг не трогаем: иначе вход в GNOME снимал бы строку, нужную следующему входу в Hyprland
      if (!enabled) {
        await _syncHyprlandConfig(false);
      } else if (hyprlandSession()) {
        await _syncHyprlandConfig(!await desktopRunsAutostart());
      }
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
