import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/prefs_recovery.dart';

/// Разбор реальной поломки: после принудительного обновления Windows файл
/// настроек оказался нужной длины, но целиком из нулей. json.decode падает на
/// первом символе, исключение прилетает до runApp — и приложение остаётся
/// процессом без окна. Здесь проверяется, что до плагина такой файл не доедет.
void main() {
  late Directory dir;

  File prefs() => File('${dir.path}${Platform.pathSeparator}'
      'shared_preferences.json');
  File backup() => File('${dir.path}${Platform.pathSeparator}'
      'shared_preferences.backup.json');
  File corrupt() => File('${dir.path}${Platform.pathSeparator}'
      'shared_preferences.corrupt.json');

  const goodJson = '{"flutter.keqdis_settings":"{}"}';
  const otherJson = '{"flutter.keqdis_servers_v2":"[]"}';

  setUp(() => dir = Directory.systemTemp.createTempSync('prefs_recovery'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('целый файл не трогает и кладёт рядом бэкап', () {
    prefs().writeAsStringSync(goodJson);

    PrefsRecovery.repairIn(dir);

    expect(prefs().readAsStringSync(), goodJson);
    expect(backup().readAsStringSync(), goodJson);
    expect(corrupt().existsSync(), isFalse);
  });

  test('файл из нулей поднимается из бэкапа, битый остаётся на разбор', () {
    prefs().writeAsBytesSync(List<int>.filled(6248, 0));
    backup().writeAsStringSync(otherJson);

    PrefsRecovery.repairIn(dir);

    expect(prefs().readAsStringSync(), otherJson);
    expect(corrupt().lengthSync(), 6248);
  });

  test('битый файл без бэкапа просто убирается — старт с чистых настроек', () {
    prefs().writeAsStringSync('{"flutter.keqdis_servers_v2":"[{');

    PrefsRecovery.repairIn(dir);

    expect(prefs().existsSync(), isFalse);
    expect(corrupt().existsSync(), isTrue);
  });

  test('пустой файл — тот же обрыв записи: поднимаем бэкап', () {
    prefs().writeAsBytesSync(<int>[]);
    backup().writeAsStringSync(goodJson);

    PrefsRecovery.repairIn(dir);

    expect(prefs().readAsStringSync(), goodJson);
    // Нулевой длины копию хранить незачем — разбирать в ней нечего.
    expect(corrupt().existsSync(), isFalse);
  });

  test('нечитаемый как UTF-8 файл считается битым', () {
    prefs().writeAsBytesSync(<int>[0xD0, 0x52, 0xFF, 0xFE, 0x00, 0x9A]);
    backup().writeAsStringSync(goodJson);

    PrefsRecovery.repairIn(dir);

    expect(prefs().readAsStringSync(), goodJson);
  });

  test('валидный JSON, но не объект — тоже не то, что читает плагин', () {
    prefs().writeAsStringSync('[]');
    backup().writeAsStringSync(goodJson);

    PrefsRecovery.repairIn(dir);

    expect(prefs().readAsStringSync(), goodJson);
  });

  test('битый файл и битый бэкап — остаёмся без настроек, но стартуем', () {
    prefs().writeAsBytesSync(List<int>.filled(64, 0));
    backup().writeAsBytesSync(List<int>.filled(64, 0));

    PrefsRecovery.repairIn(dir);

    expect(prefs().existsSync(), isFalse);
  });

  test('файла нет — бэкап не поднимаем: это первый запуск или сброс руками', () {
    backup().writeAsStringSync(goodJson);

    PrefsRecovery.repairIn(dir);

    expect(prefs().existsSync(), isFalse);
    expect(backup().readAsStringSync(), goodJson);
  });
}
