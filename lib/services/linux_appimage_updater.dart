import 'dart:io';

import '../core/app_logger.dart';
import 'linux_install.dart';

class LinuxAppImageUpdater {
  LinuxAppImageUpdater._();

  static String? currentAppImagePath() {
    final path = Platform.environment['APPIMAGE'];
    if (path == null || path.isEmpty) return null;
    return File(path).existsSync() ? path : null;
  }

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

    await launchAfterExit(_script, [newAppImage, targetAppImage]);

    await beforeRestart?.call();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await AppLogger.instance.flush();
    exit(0);
  }

  static const _script = r'''
NEW="$1"; TARGET="$2"
log "=== appimage update: new=$NEW target=$TARGET"

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
