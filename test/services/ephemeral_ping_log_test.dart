import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/ephemeral_xray_ping.dart';

void main() {
  group('лог временного ядра', () {
    test('раскраска не уезжает в текст ошибки', () {
      // Ядро красит уровень сообщения даже когда пишет в трубу, а не в
      // терминал: без чистки пользователь видел бы в ошибке управляющие
      // последовательности вместо слова FATAL.
      expect(
        stripAnsi('\x1B[31mFATAL\x1B[0m[0000] decode config: bad port'),
        'FATAL[0000] decode config: bad port',
      );
    });

    test('обычный текст не трогаем', () {
      expect(stripAnsi('keqrnel started'), 'keqrnel started');
      expect(stripAnsi(''), '');
    });
  });
}
