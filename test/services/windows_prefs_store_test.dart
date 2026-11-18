import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/windows_prefs_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

// файл тот же, что писал SharedPreferencesWindows: после обновления приложение должно увидеть свои настройки
void main() {
  late Directory dir;
  File prefsFile() =>
      File('${dir.path}${Platform.pathSeparator}${WindowsPrefsStore.fileName}');
  Map<String, Object?> onDisk() =>
      (json.decode(prefsFile().readAsStringSync()) as Map).cast<String, Object?>();
  WindowsPrefsStore store() => WindowsPrefsStore(directory: () async => dir);

  setUp(() => dir = Directory.systemTemp.createTempSync('kq_prefs'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('читает файл плагина и отдаёт только свои ключи', () async {
    prefsFile().writeAsStringSync(json.encode({
      'flutter.keqdis_active_server': 's1',
      'flutter.keqdis_list': ['a', 'b'],
      'other.key': 1,
    }));

    final all = await store().getAll();

    expect(all, {
      'flutter.keqdis_active_server': 's1',
      'flutter.keqdis_list': ['a', 'b'],
    });
  });

  test('пишет весь набор тем же JSON и не оставляет временный файл', () async {
    prefsFile().writeAsStringSync(json.encode({'flutter.a': 1}));
    final s = store();

    expect(await s.setValue('String', 'flutter.b', 'x'), isTrue);

    expect(onDisk(), {'flutter.a': 1, 'flutter.b': 'x'});
    expect(File('${prefsFile().path}.tmp').existsSync(), isFalse);
  });

  test('частые изменения склеиваются, в файле последнее', () async {
    final s = store();
    final writes = [
      for (var i = 0; i < 50; i++) s.setValue('Int', 'flutter.n', i),
      s.setValue('Bool', 'flutter.flag', true),
    ];
    final results = await Future.wait(writes);

    expect(results, everyElement(isTrue));
    expect(onDisk(), {'flutter.n': 49, 'flutter.flag': true});
  });

  test('удаление и очистка по префиксу', () async {
    prefsFile().writeAsStringSync(json.encode({
      'flutter.a': 1,
      'flutter.b': 2,
      'other.c': 3,
    }));
    final s = store();

    await s.remove('flutter.a');
    expect(onDisk(), {'flutter.b': 2, 'other.c': 3});

    await s.clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')),
    );
    expect(onDisk(), {'other.c': 3});
  });

  test('flushInstance ждёт записи, начатой без await', () async {
    final s = store();
    SharedPreferencesStorePlatform.instance = s;

    final pending = s.setValue('String', 'flutter.last', 'exit');
    await WindowsPrefsStore.flushInstance();

    expect(onDisk()['flutter.last'], 'exit');
    await pending;
  });

  test('SharedPreferences видит свои значения и после перезапуска', () async {
    SharedPreferencesStorePlatform.instance = store();
    SharedPreferences.resetStatic();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('keqdis_active_server', 's7');
    await prefs.setStringList('keqdis_ids', ['x', 'y']);

    SharedPreferencesStorePlatform.instance = store();
    SharedPreferences.resetStatic();
    final again = await SharedPreferences.getInstance();

    expect(again.getString('keqdis_active_server'), 's7');
    expect(again.getStringList('keqdis_ids'), ['x', 'y']);
    SharedPreferences.resetStatic();
  });
}
