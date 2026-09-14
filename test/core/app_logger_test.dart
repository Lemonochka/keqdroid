import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/core/app_logger.dart';

/// На десктопе файл лога — единственный след поломки: Crashlytics только под
/// Android, а developer.log в релизе не видно нигде.
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

  test('пишет строку на диск и маскирует секреты', () {
    AppLogger.instance.error(
      'Subscription failed',
      error: 'https://panel.example/sub/abcdefghijklmnop0123',
    );

    final text = log().readAsStringSync();
    expect(text, contains('[ERROR] Subscription failed'));
    expect(text, contains('***'));
    expect(text, isNot(contains('abcdefghijklmnop0123')));
  });

  test('на старте уводит переросший лог в app.log.1', () {
    log().writeAsStringSync('x' * (256 * 1024 + 1));

    AppLogger.instance.enableFileLogIn(dir);
    AppLogger.instance.info('after rotation');

    expect(rotated().lengthSync(), 256 * 1024 + 1);
    expect(log().readAsStringSync(), contains('after rotation'));
  });

  test('недоступный файл логгер переживает молча', () {
    dir.deleteSync(recursive: true);

    expect(() => AppLogger.instance.warn('no disk'), returnsNormally);
  });
}
