import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';

import '../core/app_logger.dart';
import '../platform/vpn_native_bridge.dart';

typedef MacosProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> args);

typedef MacosDetachedLauncher =
    Future<void> Function(String executable, List<String> args);

// Тихое обновление на macOS из уже проверенного по SHA256SUMS .dmg:
// монтирует образ с -nobrowse (без окна Finder), копирует .app через ditto
// рядом с установленным, отключает VPN, выходит и атомарно подменяет бандл.
class MacosDmgUpdater {
  MacosDmgUpdater._();

  static const appBundleName = 'keqdroid.app';
  static const executableName = 'keqdroid';

  @visibleForTesting
  static String Function() executablePath = () => Platform.resolvedExecutable;

  @visibleForTesting
  static MacosProcessRunner runProcess = (exe, args) => Process.run(exe, args);

  @visibleForTesting
  static MacosDetachedLauncher startDetached = (exe, args) async {
    await Process.start(exe, args, mode: ProcessStartMode.detached);
  };

  @visibleForTesting
  static Future<void> Function() cleanupBeforeExit = _defaultCleanupBeforeExit;

  @visibleForTesting
  static void Function(int code) exitProcess = exit;

  @visibleForTesting
  static Directory Function() tempDir = () => Directory.systemTemp;

  @visibleForTesting
  static int Function() currentPid = () => pid;

  static Future<void> _defaultCleanupBeforeExit() async {
    try {
      await trayManager.destroy();
    } catch (_) {}
    try {
      await VpnNativeBridge.channel.invokeMethod<void>('confirmAppTerminate');
    } catch (_) {}
    await AppLogger.instance.flush();
  }

  /// Resolves the running `.app` bundle path when it is a regular installed
  /// bundle that can safely be replaced in place (excludes mounted `/Volumes/`
  /// images, Gatekeeper `/AppTranslocation/`, and symlinked bundles).
  static String? currentAppBundlePath({String? resolvedExecutable}) {
    final exe = p.normalize(resolvedExecutable ?? executablePath());
    final macosDir = p.dirname(exe);
    if (p.basename(macosDir) != 'MacOS') return null;
    final contentsDir = p.dirname(macosDir);
    if (p.basename(contentsDir) != 'Contents') return null;
    final appBundle = p.dirname(contentsDir);
    if (!appBundle.toLowerCase().endsWith('.app')) return null;

    final posixPath = appBundle.replaceAll('\\', '/');
    if (posixPath.startsWith('/Volumes/') ||
        posixPath.contains('/AppTranslocation/')) {
      return null;
    }
    if (Link(appBundle).existsSync()) return null;
    if (!File(p.join(contentsDir, 'Info.plist')).existsSync()) return null;
    return appBundle;
  }

  static bool isWritableDir(String dir) {
    final probe = File(p.join(dir, '.keqdroid_write_probe_${currentPid()}'));
    try {
      probe.writeAsStringSync('');
      probe.deleteSync();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Returns the target `.app` bundle path if we have permissions to replace
  /// it silently without elevating, or `null` if we should fall back to
  /// opening the `.dmg` in Finder.
  static String? resolveWritableTarget({String? resolvedExecutable}) {
    final bundle = currentAppBundlePath(resolvedExecutable: resolvedExecutable);
    if (bundle == null) return null;
    final parentDir = p.dirname(bundle);
    final contentsDir = p.join(bundle, 'Contents');
    if (!isWritableDir(parentDir) || !isWritableDir(contentsDir)) {
      return null;
    }
    return bundle;
  }

  /// Finds the `.app` payload inside a mounted `.dmg` directory.
  @visibleForTesting
  static String? findAppBundleInMount(Directory mountDir) {
    final preferred = Directory(p.join(mountDir.path, appBundleName));
    if (_isValidAppBundle(preferred)) return preferred.path;

    final candidates = <Directory>[];
    for (final entity in mountDir.listSync(followLinks: false)) {
      if (entity is Directory &&
          entity.path.toLowerCase().endsWith('.app') &&
          !p.basename(entity.path).startsWith('.') &&
          _isValidAppBundle(entity)) {
        candidates.add(entity);
      }
    }
    if (candidates.length == 1) return candidates.single.path;
    return null;
  }

  static bool _isValidAppBundle(Directory bundle) {
    if (!bundle.existsSync() || Link(bundle.path).existsSync()) return false;
    final exe = File(p.join(bundle.path, 'Contents', 'MacOS', executableName));
    final plist = File(p.join(bundle.path, 'Contents', 'Info.plist'));
    return exe.existsSync() && plist.existsSync();
  }

  /// Applies a verified `.dmg` update in place and relaunches the app.
  ///
  /// Returns `false` if in-place replacement is not applicable (for example,
  /// running from a read-only `/Volumes/` image, Gatekeeper App Translocation,
  /// or a non-writable directory), so the caller can fall back to opening the
  /// `.dmg` normally.
  static Future<bool> applyDmgUpdate({
    required String dmgPath,
    Future<void> Function()? beforeRestart,
  }) async {
    if (!File(dmgPath).existsSync()) {
      throw StateError('Downloaded DMG not found: $dmgPath');
    }

    final targetApp = resolveWritableTarget();
    if (targetApp == null) {
      AppLogger.instance.info(
        'macOS in-place update unavailable for ${executablePath()}; '
        'falling back to opening DMG',
      );
      return false;
    }

    final parentDir = p.dirname(targetApp);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final stagedApp = p.join(parentDir, '.keqdroid_update_$stamp.app');
    final mountDir = await tempDir().createTemp('keqdroid_update_mnt_');
    var mounted = false;

    try {
      final attach = await runProcess('/usr/bin/hdiutil', [
        'attach',
        '-nobrowse',
        '-readonly',
        '-noverify',
        '-noautoopen',
        '-mountpoint',
        mountDir.path,
        dmgPath,
      ]);
      if (attach.exitCode != 0) {
        throw StateError(
          _tail(attach.stderr) ??
              'Failed to mount update disk image (exit ${attach.exitCode})',
        );
      }
      mounted = true;

      final sourceApp = findAppBundleInMount(mountDir);
      if (sourceApp == null) {
        throw StateError('Update disk image does not contain $appBundleName');
      }

      // ditto preserves symlinks inside Frameworks, Mach-O signatures, and xattrs.
      final copy = await runProcess('/usr/bin/ditto', [sourceApp, stagedApp]);
      if (copy.exitCode != 0 || !_isValidAppBundle(Directory(stagedApp))) {
        throw StateError(
          _tail(copy.stderr) ??
              'Failed to copy updated app bundle (exit ${copy.exitCode})',
        );
      }

      // проверяем всю вложенную подпись до снятия quarantine
      final signature = await runProcess('/usr/bin/codesign', [
        '--verify',
        '--deep',
        '--strict',
        '--verbose=2',
        stagedApp,
      ]);
      if (signature.exitCode != 0) {
        throw StateError(
          _tail(signature.stderr) ??
              _tail(signature.stdout) ??
              'Updated app bundle failed code signature verification '
                  '(exit ${signature.exitCode})',
        );
      }

      // Strip quarantine flag so Gatekeeper does not block or translocate relaunch.
      await runProcess('/usr/bin/xattr', [
        '-dr',
        'com.apple.quarantine',
        stagedApp,
      ]);
    } catch (_) {
      _deleteQuietly(Directory(stagedApp));
      rethrow;
    } finally {
      if (mounted) {
        final detach = await runProcess('/usr/bin/hdiutil', [
          'detach',
          mountDir.path,
          '-quiet',
        ]);
        if (detach.exitCode != 0) {
          await runProcess('/usr/bin/hdiutil', [
            'detach',
            mountDir.path,
            '-force',
            '-quiet',
          ]);
        }
      }
      _deleteQuietly(mountDir);
    }

    final scriptFile = File(
      p.join(tempDir().path, 'keqdroid_update_$stamp.sh'),
    );
    try {
      await beforeRestart?.call();
      await scriptFile.writeAsString(updaterScript(), flush: true);
      await startDetached('/bin/sh', [
        scriptFile.path,
        '${currentPid()}',
        stagedApp,
        targetApp,
      ]);
    } catch (_) {
      _deleteQuietly(Directory(stagedApp));
      _deleteQuietly(scriptFile);
      rethrow;
    }

    try {
      await File(dmgPath).delete();
    } catch (_) {}

    await cleanupBeforeExit();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    exitProcess(0);
    return true;
  }

  static void _deleteQuietly(FileSystemEntity entity) {
    try {
      if (entity.existsSync()) entity.deleteSync(recursive: true);
    } catch (_) {}
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

  @visibleForTesting
  static String updaterScript({bool relaunch = true}) =>
      '''#!/bin/sh
trap '' HUP
APPPID="\$1"
STAGED="\$2"
TARGET="\$3"
SCRIPT="\$0"
LOG="\${TMPDIR:-/tmp}/keqdroid_update.log"
BACKUP="\${TARGET}.old.\$\$"

log() {
  printf '%s  %s\\n' "\$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)" "\$1" >>"\$LOG" 2>/dev/null
}

log "=== macOS update: pid=\$APPPID staged=\$STAGED target=\$TARGET"

i=0
while [ "\$i" -lt 300 ]; do
  kill -0 "\$APPPID" 2>/dev/null || break
  sleep 0.2
  i=\$((i + 1))
done

if kill -0 "\$APPPID" 2>/dev/null; then
  log "app pid \$APPPID did not exit in time; aborting swap"
  rm -rf "\$STAGED" "\$SCRIPT" 2>/dev/null
  exit 1
fi
sleep 0.3

if [ ! -d "\$STAGED" ]; then
  log "staged bundle missing: \$STAGED"
  rm -f "\$SCRIPT" 2>/dev/null
  exit 1
fi

rm -rf "\$BACKUP" 2>/dev/null
if [ -e "\$TARGET" ]; then
  if ! mv "\$TARGET" "\$BACKUP" 2>>"\$LOG"; then
    log "failed to move current bundle to backup"
    rm -rf "\$STAGED" "\$SCRIPT" 2>/dev/null
    ${relaunch ? '/usr/bin/open -n "\$TARGET" >/dev/null 2>&1' : ':'}
    exit 1
  fi
fi

if mv "\$STAGED" "\$TARGET" 2>>"\$LOG"; then
  log "swapped updated bundle into \$TARGET"
  rm -rf "\$BACKUP" 2>/dev/null
else
  log "failed to move staged bundle into \$TARGET; rolling back"
  if [ -e "\$BACKUP" ]; then
    mv "\$BACKUP" "\$TARGET" 2>>"\$LOG"
  fi
  rm -rf "\$STAGED" 2>/dev/null
fi

/usr/bin/touch "\$TARGET" 2>/dev/null || true
${relaunch ? 'if /usr/bin/open -n "\$TARGET" >/dev/null 2>&1; then log "relaunched \$TARGET"; else log "relaunch failed"; fi' : 'log "relaunch skipped (test mode)"'}
rm -f "\$SCRIPT" 2>/dev/null
''';
}
