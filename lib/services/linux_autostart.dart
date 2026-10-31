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

  // Hyprland без systemd-сборки (caelestia на EndeavourOS), sway, river и niri вне своей сессии ярлык не исполнят: никто не поднимает
  // xdg-desktop-autostart.target. остаётся их собственный запуск при старте; строку ставим только там, иначе приложение стартовало бы дважды
  static const _startMarker = 'keqdroid autostart, added and removed by the app';

  static const _compositors = ['hyprland', 'sway', 'river', 'niri'];

  @visibleForTesting
  static String? homeOverride;

  static String _home() => homeOverride ?? Platform.environment['HOME'] ?? '';

  @visibleForTesting
  static String? Function() compositor = () {
    final env = Platform.environment;
    final desktop = (env['XDG_CURRENT_DESKTOP'] ?? '').toLowerCase();
    if (desktop.contains('hyprland') ||
        env.containsKey('HYPRLAND_INSTANCE_SIGNATURE')) {
      return 'hyprland';
    }
    // sway и niri без сессии XDG_CURRENT_DESKTOP не ставят, а сокет детям дают всегда
    if (desktop.contains('sway') || env.containsKey('SWAYSOCK')) return 'sway';
    if (desktop.contains('niri') || env.containsKey('NIRI_SOCKET')) {
      return 'niri';
    }
    if (desktop.contains('river')) return 'river';
    return null;
  };

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

  // порядок как у самих композиторов: пишем в тот файл, который они прочтут
  static List<File> _compositorConfigs(String wm) {
    final config = _configHome();
    return switch (wm) {
      'hyprland' => [
          // caelestia подключает свой пустой hypr-user.lua именно для пользовательских строк
          File(p.join(config, 'caelestia', 'hypr-user.lua')),
          File(p.join(config, 'hypr', 'hyprland.lua')),
          File(p.join(config, 'hypr', 'hyprland.conf')),
        ],
      'sway' => [
          File(p.join(_home(), '.sway', 'config')),
          File(p.join(config, 'sway', 'config')),
        ],
      'river' => [File(p.join(config, 'river', 'init'))],
      'niri' => [File(p.join(config, 'niri', 'config.kdl'))],
      _ => const [],
    };
  }

  @visibleForTesting
  static String startLines(String wm, String configPath, String target) {
    // апостроф без обратной косой: sway снимает её ещё до оболочки (unescape_string)
    final command = "'${target.replaceAll("'", "'\"'\"'")}' $flag";
    final escaped = command.replaceAll(r'\', r'\\');
    String quoted(String s) =>
        '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
    return switch (wm) {
      'hyprland' when configPath.endsWith('.lua') => '-- $_startMarker\n'
          'hl.on("hyprland.start", function() hl.exec_cmd(${quoted(command)}) end)\n',
      // hyprlang режет комментарий по решётке и подставляет $имя без всякого экранирования, поэтому $ рвём кавычками
      'hyprland' => '# $_startMarker\nexec-once = '
          '${escaped.replaceAll('#', '##').replaceAll(r'$', r"$''")}\n',
      'sway' =>
        '# $_startMarker\nexec ${escaped.replaceAll(r'$', r'$$')}\n',
      'river' => '# $_startMarker\n$command &\n',
      'niri' =>
        '// $_startMarker\nspawn-at-startup ${quoted(target)} "$flag"\n',
      _ => '',
    };
  }

  // init у river исполняемый файл на любом языке, строку оболочки ставим только в скрипт оболочки
  static bool _shellScript(String text) {
    if (!text.startsWith('#!')) return true;
    final words = text.split('\n').first.substring(2).trim().split(RegExp(r'\s+'));
    var program = p.posix.basename(words.first);
    if (program == 'env') {
      program = words.skip(1).firstWhere((w) => !w.startsWith('-'), orElse: () => '');
    }
    return const {'sh', 'bash', 'dash', 'zsh', 'ksh', 'mksh', 'fish'}
        .contains(program);
  }

  static String _withoutStartLines(String text) {
    final lines = text.split('\n');
    final out = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].contains(_startMarker)) {
        // строку запуска могли стереть руками, тогда под меткой уже чужая
        if (i + 1 < lines.length && lines[i + 1].contains(flag)) i++;
        continue;
      }
      out.add(lines[i]);
    }
    return out.join('\n');
  }

  static String _withStartLines(String wm, String text, String block) {
    // у river строку в конец не поставить: init часто кончается exec-ом генератора раскладки
    if (wm == 'river') {
      if (!text.startsWith('#!')) return block + text;
      final eol = text.indexOf('\n');
      if (eol < 0) return '$text\n$block';
      return text.substring(0, eol + 1) + block + text.substring(eol + 1);
    }
    final base = text.isNotEmpty && !text.endsWith('\n') ? '$text\n' : text;
    return base + block;
  }

  static Future<bool> _syncStartLines(String wm, bool wanted) async {
    var changed = false;
    var placed = false;
    for (final file in _compositorConfigs(wm)) {
      if (!file.existsSync()) continue;
      final text = await file.readAsString();
      var next = _withoutStartLines(text);
      if (wanted && !placed) {
        placed = true;
        if (wm != 'river' || _shellScript(next)) {
          next = _withStartLines(
              wm, next, startLines(wm, file.path, _target()));
        }
      }
      if (next != text) {
        await file.writeAsString(next);
        changed = true;
      }
    }
    return changed;
  }

  // вне своего композитора чужой конфиг не трогаем: иначе вход в GNOME снимал бы строку, нужную следующему входу в Hyprland
  static Future<void> _syncCompositorStart({required bool enabled}) async {
    if (!enabled) {
      for (final wm in _compositors) {
        await _syncStartLines(wm, false);
      }
      return;
    }
    final wm = compositor();
    if (wm == null) return;
    await _syncStartLines(wm, !await desktopRunsAutostart());
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
        await _syncCompositorStart(enabled: false);
        await reloadUserUnits();
        return true;
      }
      if (file.existsSync() && !isEnabled()) return false;
      await file.parent.create(recursive: true);
      await file.writeAsString(contentFor(_target()));
      await _syncHyprlandDropIn(true);
      await _syncCompositorStart(enabled: true);
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
      await _syncCompositorStart(enabled: enabled);
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
