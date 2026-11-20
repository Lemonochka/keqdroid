import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import 'linux_appimage_updater.dart';

enum LinuxInstallKind { appImage, deb, rpm, pacman, portable, readOnly }

class LinuxInstall {
  LinuxInstall._();

  static Future<LinuxInstallKind>? _detected;

  static Future<LinuxInstallKind> detect() => _detected ??= classify(
    appImagePath: LinuxAppImageUpdater.currentAppImagePath(),
    executable: Platform.resolvedExecutable,
    owns: _owns,
    writable: isWritableDir,
  );

  // по владельцу файла: rpm ставят и на Debian
  @visibleForTesting
  static Future<LinuxInstallKind> classify({
    required String? appImagePath,
    required String executable,
    required Future<bool> Function(String tool, List<String> args) owns,
    required bool Function(String dir) writable,
  }) async {
    if (appImagePath != null) return LinuxInstallKind.appImage;
    if (await owns('dpkg-query', ['-S', executable])) {
      return LinuxInstallKind.deb;
    }
    if (await owns('rpm', ['-qf', executable])) return LinuxInstallKind.rpm;
    if (await owns('pacman', ['-Qo', executable])) {
      return LinuxInstallKind.pacman;
    }
    return writable(p.dirname(executable))
        ? LinuxInstallKind.portable
        : LinuxInstallKind.readOnly;
  }

  static Future<bool> _owns(String tool, List<String> args) async {
    try {
      return (await Process.run(tool, args)).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  static bool isWritableDir(String dir) {
    final probe = File(p.join(dir, '.keqdroid_write_probe_$pid'));
    try {
      probe.writeAsStringSync('');
      probe.deleteSync();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  // на образных системах (Silverblue и подобные) /usr только для чтения, rpm -U падает
  @visibleForTesting
  static bool Function() imageBasedSystem = () =>
      File('/run/ostree-booted').existsSync();

  @visibleForTesting
  static String? packageInstallBlocker(String package) =>
      package.endsWith('.rpm') && imageBasedSystem()
      ? 'This system is built from an image (Fedora Silverblue, Kinoite, '
            'Bazzite and the like), where packages are layered with '
            'rpm-ostree, not installed with rpm.'
      : null;

  static Future<String> saveToDownloads(
    String downloaded,
    String name, {
    bool executable = false,
  }) async {
    var dir = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    try {
      final r = await Process.run('xdg-user-dir', ['DOWNLOAD']);
      final out = '${r.stdout}'.trim();
      if (r.exitCode == 0 && out.isNotEmpty && Directory(out).existsSync()) {
        dir = out;
      }
    } on ProcessException {
      // нет xdg-user-dirs, остаётся домашний каталог
    }
    final target = p.join(dir, name.isEmpty ? p.basename(downloaded) : name);
    // /tmp и дом часто на разных разделах, rename туда не ходит
    await File(downloaded).copy(target);
    await File(downloaded).delete();
    if (executable) await Process.run('chmod', ['+x', target]);
    return target;
  }

  // apt-get доставит зависимости, а rpm есть и у dnf, и у zypper с одинаковыми флагами
  static Future<bool> installPackage(
    String package, {
    Future<void> Function()? beforeRestart,
  }) async {
    final blocker = packageInstallBlocker(package);
    if (blocker != null) {
      final saved = await saveToDownloads(package, p.basename(package));
      throw StateError('$blocker The new version is saved as $saved');
    }
    final command = package.endsWith('.deb')
        ? ['apt-get', 'install', '-y', package]
        : ['rpm', '-U', package];
    final ProcessResult result;
    try {
      result = await Process.run('pkexec', command);
    } on ProcessException {
      await OpenFilex.open(package);
      return false;
    }
    switch (result.exitCode) {
      case 0:
        break;
      case 126: // окно пароля закрыли
        return false;
      case 127:
        await OpenFilex.open(package);
        return false;
      default:
        throw StateError(
          _tail(result.stderr) ?? 'Package install failed (${result.exitCode})',
        );
    }

    await beforeRestart?.call();
    await launchAfterExit(_relaunchScript, [Platform.resolvedExecutable]);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    exit(0);
  }

  static Future<bool> applyPortable(
    String archive, {
    Future<void> Function()? beforeRestart,
  }) async {
    final appDir = p.dirname(Platform.resolvedExecutable);
    final staging = await Directory.systemTemp.createTemp('keqdroid_update_');
    try {
      final result = await Process.run('tar', [
        '-xzf',
        archive,
        '-C',
        staging.path,
      ]);
      if (result.exitCode != 0) {
        throw StateError(
          _tail(result.stderr) ?? 'Failed to extract the update archive',
        );
      }
      final payload = p.join(staging.path, 'keqdroid');
      if (!File(p.join(payload, 'keqdroid')).existsSync()) {
        throw StateError('Update archive does not contain keqdroid');
      }
      await launchAfterExit(_portableScript, [
        payload,
        appDir,
        staging.path,
        archive,
      ]);
    } catch (_) {
      try {
        await staging.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }

    await beforeRestart?.call();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    exit(0);
  }

  static String? _tail(Object? stderr) {
    final lines = '$stderr'
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;
    return lines.skip(lines.length > 3 ? lines.length - 3 : 0).join('\n');
  }

  static const _relaunchScript = r'''
EXE="$1"
log "=== package update installed, relaunching $EXE"
setsid "$EXE" >/dev/null 2>&1 < /dev/null &
''';

  // удаляем и кладём заново: в запущенный исполняемый файл Linux писать не даёт (Text file busy)
  static const _portableScript = r'''
SRC="$1"; DST="$2"; STAGING="$3"; ARCHIVE="$4"
log "=== portable update: $SRC -> $DST"
if cp -a --remove-destination "$SRC/." "$DST/" 2>>"$LOG"; then
  log "copied"
else
  log "copy FAILED"
fi
rm -rf "$STAGING" "$ARCHIVE" 2>/dev/null
setsid "$DST/keqdroid" >/dev/null 2>&1 < /dev/null &
''';
}

// setsid уводит процесс из нашей группы, чтобы exit(0) его не прихватил
Future<void> launchAfterExit(String body, List<String> args) async {
  final script = File(
    p.join(
      Directory.systemTemp.path,
      'keqdroid_update_${DateTime.now().millisecondsSinceEpoch}.sh',
    ),
  );
  await script.writeAsString('$_waitForApp\n$body');
  final shArgs = [script.path, '$pid', ...args];
  try {
    await Process.start('setsid', [
      'sh',
      ...shArgs,
    ], mode: ProcessStartMode.detached);
  } on ProcessException {
    await Process.start('sh', shArgs, mode: ProcessStartMode.detached);
  }
}

const _waitForApp = r'''
APPPID="$1"; shift
LOG="${TMPDIR:-/tmp}/keqdroid_update.log"
log() { printf '%s  %s\n' "$(date -Is 2>/dev/null)" "$1" >>"$LOG" 2>/dev/null; }
i=0
while [ "$i" -lt 120 ]; do
  kill -0 "$APPPID" 2>/dev/null || break
  sleep 1
  i=$((i+1))
done
sleep 1
''';
