import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/core/app_logger.dart';

// файл лога единственный след поломки: developer.log в релизе не видно нигде
void main() {
  late Directory dir;

  File log() => File('${dir.path}${Platform.pathSeparator}app.log');
  File rotated() => File('${log().path}.1');

  setUp(() {
    dir = Directory.systemTemp.createTempSync('app_logger');
    AppLogger.instance.enableFileLogIn(dir);
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('пишет строку на диск и маскирует секреты', () async {
    AppLogger.instance.error(
      'Subscription failed',
      error: 'https://panel.example/sub/abcdefghijklmnop0123',
    );
    await AppLogger.instance.flush();

    final text = log().readAsStringSync();
    expect(text, contains('[ERROR] Subscription failed'));
    expect(text, contains('***'));
    expect(text, isNot(contains('abcdefghijklmnop0123')));
  });

  test('на старте уводит переросший лог в app.log.1', () async {
    log().writeAsStringSync('x' * (256 * 1024 + 1));

    AppLogger.instance.enableFileLogIn(dir);
    AppLogger.instance.info('after rotation');
    await AppLogger.instance.flush();

    expect(rotated().lengthSync(), 256 * 1024 + 1);
    expect(log().readAsStringSync(), contains('after rotation'));
  });

  test('журнал читается вместе с прошлой половиной, старое первым', () async {
    rotated().writeAsStringSync('older line\n');
    AppLogger.instance.info('newer line');

    final text = await AppLogger.instance.readFileLog();
    expect(text.indexOf('older line'), lessThan(text.indexOf('newer line')));
  });

  test('из длинного журнала читается хвост', () async {
    AppLogger.instance.info('head ${'x' * 100}');
    AppLogger.instance.info('tail');

    final text = await AppLogger.instance.readFileLog(maxChars: 50);
    expect(text.length, 50);
    expect(text, contains('tail'));
    expect(text, isNot(contains('head')));
  });

  test('недоступный файл логгер переживает молча', () async {
    dir.deleteSync(recursive: true);

    expect(() => AppLogger.instance.warn('no disk'), returnsNormally);
    await AppLogger.instance.flush();
  });

  // на ПК с Defender синхронная строка держала поток интерфейса 7-460 мс
  test('строка уходит на диск не в вызове, а следом, по порядку', () async {
    AppLogger.instance.info('first');
    AppLogger.instance.info('second');
    expect(
      log().existsSync() ? log().readAsStringSync() : '',
      isNot(contains('first')),
    );

    await AppLogger.instance.flush();
    final text = log().readAsStringSync();
    expect(text.indexOf('first'), lessThan(text.indexOf('second')));
  });
}
