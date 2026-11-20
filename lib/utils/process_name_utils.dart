import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;

// подмена для тестов сплита: список там виндовый, а гоняются они и на Linux-раннере CI
@visibleForTesting
bool? debugWindowsProcessRules;

bool windowsProcessRules(bool? windows) =>
    windows ?? debugWindowsProcessRules ?? Platform.isWindows;

// путь пишем только когда его указали руками: отметка в списке пишет имя, чтобы программа,
// переехавшая в новую папку, не выпадала из сплита
bool isProcessPathEntry(String raw) => raw.contains(r'\') || raw.contains('/');

String normalizeProcessPath(String raw, {bool? windows}) {
  final s = raw.trim().replaceAll('"', '');
  return windowsProcessRules(windows) ? s.replaceAll('/', r'\') : s;
}

// регистр сохраняем: на Linux ядро сравнивает имя точно
// .exe только на Windows, на Linux его снимаем: старая версия дописывала его везде
String normalizeProcessName(String raw, {bool? windows}) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  s = s.replaceAll('"', '');
  final cut = math.max(s.lastIndexOf(r'\'), s.lastIndexOf('/'));
  if (cut >= 0) {
    // по обоим разделителям: имя приезжает с чужой платформы через бэкап, а p.basename на Linux обратную косую не режет
    s = s.substring(cut + 1);
  }
  final hasExe = s.toLowerCase().endsWith('.exe');
  if (windowsProcessRules(windows)) {
    if (!hasExe) s = '$s.exe';
  } else if (hasExe) {
    s = s.substring(0, s.length - 4);
  }
  return s;
}

// всё, кроме латиницы и цифр, кодом \xNN: так понимает regexp2 у mihomo, а запятые и скобки он тогда не режет
String processRegexLiteral(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    final isAsciiAlnum =
        (rune >= 0x30 && rune <= 0x39) ||
        (rune >= 0x41 && rune <= 0x5a) ||
        (rune >= 0x61 && rune <= 0x7a);
    if (isAsciiAlnum || rune > 0x7f) {
      out.writeCharCode(rune);
    } else {
      out.write('\\x${rune.toRadixString(16).padLeft(2, '0')}');
    }
  }
  return out.toString();
}

String processPathPattern(String path) =>
    path.split(RegExp(r'[\\/]')).map(processRegexLiteral).join(r'[\x5c/]');
