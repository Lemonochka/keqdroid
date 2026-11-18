import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

// схемы ярлыка из LinuxDesktopEntry.mimeTypes и tool/package_linux.sh
class LinuxDeepLinks {
  LinuxDeepLinks._();

  static const _schemes = {'keqdroid', 'keqdis'};

  static String? _pending;

  static void Function()? onArrived;

  // первый элемент /proc/self/cmdline сам бинарь
  static String? fromCommandLine(List<String> cmdline) {
    for (final raw in cmdline.skip(1)) {
      final arg = raw.trim();
      final colon = arg.indexOf(':');
      if (colon <= 0) continue;
      if (_schemes.contains(arg.substring(0, colon).toLowerCase())) return arg;
    }
    return null;
  }

  static String? launchLink() => fromCommandLine(commandLine());

  // раннер аргументы в Dart не передаёт, как и для --autostart в LinuxAutostart
  @visibleForTesting
  static List<String> Function() commandLine = () {
    try {
      return File('/proc/self/cmdline').readAsStringSync().split('\u0000');
    } catch (_) {
      return const [];
    }
  };

  static void captureLaunchLink() {
    _pending ??= launchLink();
  }

  static void deliver(String url) {
    _pending = url;
    onArrived?.call();
  }

  // одноразово, как getPendingDeepLink на Windows: вкладка серверов спрашивает при каждой пересборке
  static String? takePending() {
    final url = _pending;
    _pending = null;
    return url;
  }

  @visibleForTesting
  static void reset() {
    _pending = null;
    onArrived = null;
  }
}
