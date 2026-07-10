import 'dart:io';

import 'package:path/path.dart' as p;

/// In-place update for the Linux AppImage build.
///
/// Only meaningful when the app is *running as an AppImage*: the AppImage
/// runtime exports `APPIMAGE` = absolute path of the `.AppImage` the user
/// launched. We overwrite that file with the freshly downloaded (and already
/// SHA-256-verified by [UpdateService]) one and relaunch. `.deb`/`.tar.gz`
/// installs, or a dev/extracted run, have no `APPIMAGE` — the caller must fall
/// back to opening the download in the browser instead of silently failing.
class LinuxAppImageUpdater {
  LinuxAppImageUpdater._();

  /// Absolute path of the currently running AppImage, or `null` when the app
  /// was not launched as one (dev build, extracted tree, deb install).
  static String? currentAppImagePath() {
    final path = Platform.environment['APPIMAGE'];
    if (path == null || path.isEmpty) return null;
    return File(path).existsSync() ? path : null;
  }

  /// Replaces the running AppImage [targetAppImage] with [newAppImage] and
  /// relaunches it after this process exits. Returns `true` — the app is
  /// exiting to apply the update (mirrors [WindowsZipUpdater]'s contract).
  static Future<bool> applyInPlace({
    required String newAppImage,
    required String targetAppImage,
    Future<void> Function()? beforeRestart,
  }) async {
    if (!Platform.isLinux) {
      throw StateError('LinuxAppImageUpdater is Linux-only');
    }
    if (!await File(newAppImage).exists()) {
      throw StateError('Downloaded AppImage not found');
    }

    final scriptPath = p.join(
      Directory.systemTemp.path,
      'keqdroid_apply_update_${DateTime.now().millisecondsSinceEpoch}.sh',
    );
    await File(scriptPath).writeAsString(_script);
    try {
      await Process.run('chmod', ['0755', scriptPath]);
    } catch (_) {}

    await _launchDetached(scriptPath, [
      '$pid',
      newAppImage,
      targetAppImage,
    ]);

    await beforeRestart?.call();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    exit(0);
  }

  /// Spawns the updater outside our process group (`setsid`) so it survives the
  /// `exit(0)` below; falls back to a plain detached `sh` where setsid is
  /// missing (some minimal distros).
  static Future<void> _launchDetached(String script, List<String> args) async {
    try {
      await Process.start(
        'setsid',
        ['sh', script, ...args],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      await Process.start(
        'sh',
        [script, ...args],
        mode: ProcessStartMode.detached,
      );
    }
  }

  // Waits for the app (its PID) to exit, atomically replaces the AppImage with
  // the downloaded one (same-dir `mv`, `cp` fallback), keeps the exec bit, and
  // relaunches.
  static const _script = r'''
APPPID="$1"; NEW="$2"; TARGET="$3"
LOG="${TMPDIR:-/tmp}/keqdroid_update.log"
log() { printf '%s  %s\n' "$(date -Is 2>/dev/null)" "$1" >>"$LOG" 2>/dev/null; }
log "=== appimage update: pid=$APPPID new=$NEW target=$TARGET"

i=0
while [ "$i" -lt 120 ]; do
  kill -0 "$APPPID" 2>/dev/null || break
  sleep 1
  i=$((i+1))
done
sleep 1

chmod +x "$NEW" 2>/dev/null
if ! mv -f "$NEW" "$TARGET" 2>>"$LOG"; then
  cp -f "$NEW" "$TARGET" 2>>"$LOG" || log "replace FAILED"
  rm -f "$NEW" 2>/dev/null
fi
chmod +x "$TARGET" 2>/dev/null
log "replaced, relaunching $TARGET"

setsid "$TARGET" >/dev/null 2>&1 < /dev/null &
log "done"
''';
}
