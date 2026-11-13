import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/update_service.dart';

// скачанное обновление после установки не нужно никому, а копилось по файлу на версию
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('update_leftovers_test');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  File file(String name, {Duration age = Duration.zero}) {
    final f = File('${temp.path}/$name')..writeAsStringSync('x');
    f.setLastModifiedSync(DateTime.now().subtract(age));
    return f;
  }

  test('старые файлы обновлений удаляются, свежие и чужие остаются', () async {
    final apk = file('keqdroid_update_v0.36.2.apk', age: const Duration(days: 2));
    final zip = file('keqdroid_update_v0.36.1.zip', age: const Duration(hours: 1));
    final script =
        file('keqdroid_update_1763000000000.sh', age: const Duration(days: 1));
    final fresh = file('keqdroid_update_v0.36.3.apk',
        age: const Duration(minutes: 2));
    final log = file('keqdroid_update.log', age: const Duration(days: 5));
    final foreign = file('other_app_update.zip', age: const Duration(days: 5));

    await UpdateService.sweepLeftovers(dir: temp);

    expect(apk.existsSync(), isFalse);
    expect(zip.existsSync(), isFalse);
    expect(script.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue, reason: 'его может держать установщик');
    expect(log.existsSync(), isTrue, reason: 'журнал обновления на Linux');
    expect(foreign.existsSync(), isTrue);
  });

  test('распакованный каталог обновления на Linux уходит целиком', () async {
    final staging = Directory('${temp.path}/keqdroid_update_abc123')
      ..createSync();
    File('${staging.path}/keqdroid').writeAsStringSync('binary');
    final other = Directory('${temp.path}/staging_1763000000000')..createSync();

    await UpdateService.sweepLeftovers(
      dir: temp,
      now: DateTime.now().add(const Duration(hours: 1)),
    );

    expect(staging.existsSync(), isFalse);
    expect(other.existsSync(), isTrue);
  });

  test('нет каталога: уборка молча ничего не делает', () async {
    await expectLater(
      UpdateService.sweepLeftovers(dir: Directory('${temp.path}/missing')),
      completes,
    );
  });
}
