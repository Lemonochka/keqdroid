import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/tunnel/core_capabilities.dart';

/// Поставляемые ядра ОБЯЗАНЫ уметь gVisor.
///
/// Умолчание стека TUN — `gvisor`; ядро, собранное без `-tags with_gvisor`,
/// на нём не ругается в конфиге, а падает при старте («gVisor is not included
/// in this build»). То есть ядро без тега = у всех, всегда, «TUN не
/// поднялся, exit code 1». Приложение это переживёт (стек понизится до
/// `system`, см. tun_stack_fallback_test), но system на Windows зависит от
/// правила фаервола — то есть работает хуже. CI keqrnel собирает через
/// `go build ./...`, без тега: подложить такой бинарь в assets проще простого,
/// поэтому проверяем сам файл.
///
/// Для mihomo на Android запаса прочности нет вовсе: там gvisor не умолчание,
/// а единственный вариант — свой TCP/IP внутри процесса ядра, потому что
/// понижаться некуда (`system` на fd от VpnService не работает без root).
void main() {
  setUp(CoreCapabilities.resetCacheForTests);

  for (final path in const [
    'assets/bin/windows/keqrnel.exe',
    'assets/bin/linux/keqrnel',
    'assets/bin/windows/mihomo.exe',
    'assets/bin/linux/mihomo',
    'android/app/src/main/jniLibs/arm64-v8a/libmihomo.so',
  ]) {
    test('$path собран с gVisor', () async {
      if (!File(path).existsSync()) {
        markTestSkipped('$path не поставляется в этой копии');
        return;
      }
      expect(
        await CoreCapabilities.hasGvisor(path),
        isTrue,
        reason: 'пересобери ядро с `-tags with_gvisor`',
      );
    });
  }

  test('не Go-бинарь — «выяснить не удалось», а не «нет»', () async {
    expect(await CoreCapabilities.hasGvisor('pubspec.yaml'), isNull);
    expect(await CoreCapabilities.hasGvisor('нет-такого-файла'), isNull);
    expect(await CoreCapabilities.hasGvisor(null), isNull);
    expect(await CoreCapabilities.hasGvisor(''), isNull);
  });

  // Вердикт mihomo о собственном туннеле сервис читает из лога по двум
  // строкам — других признаков ядро не отдаёт: открытый SOCKS-порт ещё не
  // значит, что mihomo взял туннель. Переименуй апстрим любую
  // из них — и проверка молча перестанет ловить отказ: «подключено» при
  // мёртвой сети, ровно то, ради чего она заведена. Поэтому сверяем константы
  // сервиса с форматными строками внутри самого бинаря, а не друг с другом.
  group('строки вердикта TUN совпадают с бинарём mihomo', () {
    const service =
        'android/app/src/main/kotlin/com/keqdroid/keqdroid/KeqdisVpnService.kt';
    const core = 'android/app/src/main/jniLibs/arm64-v8a/libmihomo.so';

    for (final name in const ['MIHOMO_TUN_READY', 'MIHOMO_TUN_FAILED']) {
      test(name, () {
        if (!File(core).existsSync()) {
          markTestSkipped('$core не поставляется в этой копии');
          return;
        }
        final literal = _kotlinConst(File(service).readAsStringSync(), name);
        expect(
          literal,
          isNotNull,
          reason: 'константа $name пропала из KeqdisVpnService',
        );
        expect(
          _binaryContains(File(core).readAsBytesSync(), literal!),
          isTrue,
          reason:
              'в libmihomo.so нет строки «$literal» — ядро обновилось и пишет '
              'вердикт о TUN иначе; проверь listener/listener.go: ReCreateTun',
        );
      });
    }
  });
}

/// Значение `const val <name> = "..."` из исходника на Kotlin.
String? _kotlinConst(String source, String name) => RegExp(
  'const\\s+val\\s+$name\\s*=\\s*"([^"]*)"',
).firstMatch(source)?.group(1);

/// Поиск ASCII-подстроки в бинаре — побайтно, без разворачивания 50 МБ в
/// строку Dart (это UTF-16, то есть вдвое больше памяти на ровном месте).
bool _binaryContains(Uint8List haystack, String needle) {
  final pattern = needle.codeUnits;
  final first = pattern.first;
  final last = haystack.length - pattern.length;
  outer:
  for (var i = 0; i <= last; i++) {
    if (haystack[i] != first) continue;
    for (var j = 1; j < pattern.length; j++) {
      if (haystack[i + j] != pattern[j]) continue outer;
    }
    return true;
  }
  return false;
}
