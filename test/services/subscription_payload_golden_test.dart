import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/subscription_service.dart';

/// Корпус форм payload'а: вход → список конфигов, побайтово.
///
/// Предохранитель под Q-D4 (вынос ~1080 строк парсера тела в свой модуль).
/// Существующие тесты в `subscription_service_test.dart` проверяют свойства
/// («имя с пробелами уцелело», «заглушка провайдера отвергнута»); здесь
/// фиксируется весь список на выходе целиком, включая порядок — при переносе
/// парсера меняться не должно ничто.
///
/// Панели отдают подписку в дюжине несовместимых форм, и порядок кандидатов в
/// разборе отражает реальный опыт, а не стройность. Корпус нужен, чтобы этот
/// опыт нельзя было случайно потерять при перестановке кода.
///
/// Перегенерация ожидаемых результатов:
///
/// ```
/// UPDATE_GOLDEN=1 flutter test test/services/subscription_payload_golden_test.dart
/// ```
///
/// **Входы правятся руками, выходы — только перегенерацией.** Если
/// перегенерация изменила `.expected.txt`, это и есть изменение поведения
/// парсера: дифф читается глазами, а не принимается на веру.
const _dir = 'test/fixtures/subscription_payloads';

/// Ничего настоящего: URL подписки — секрет, и в фикстурах ему не место.
/// Все адреса из TEST-NET-2/3, UUID нулевой, пароли буквальные `password`.
void main() {
  group('golden: формы payload как есть', () {
    _golden('plain-uri-list');
    _golden('json-proxy-array');
    _golden('clash-yaml');
    _golden('html-pre');
    _golden('html-js-var');
    _golden('xray-json-object');
    _golden('xray-json-array');
    _golden('mixed-links-and-config');
    _golden('fragment-with-spaces');
    _golden('wss-in-html');
  });

  group('golden: base64-обёртки', () {
    // Обёртки выводятся из `plain-uri-list`, а не лежат отдельными файлами:
    // base64-блоб в фикстуре ревьюеру не говорит ничего, а так гарантировано,
    // что раскодированное содержимое совпадает с обычным случаем — то есть
    // тест проверяет саму обёртку, а не «ещё один набор ссылок».
    final plain = File('$_dir/plain-uri-list.txt').readAsStringSync();
    final once = base64.encode(utf8.encode(plain));

    _goldenOf('base64-single', once);
    _goldenOf('base64-double', base64.encode(utf8.encode(once)));
    _goldenOf(
      'base64-urlsafe-nopad',
      base64Url.encode(utf8.encode(plain)).replaceAll('=', ''),
    );
  });

  group('golden: payload без серверов', () {
    // Служебные ноды вместо конфигов: подписка жива, но отдавать нечего.
    // Парсер обязан бросить FormatException с внятным текстом — по нему
    // ветвится UI, поэтому текст фиксируется тоже.
    //
    // Заглушки узнаются по двум независимым признакам: null-route эндпоинт
    // (`0.0.0.0` с портом ≤ 1) и маркеры в имени. Достаточно одной строки без
    // обоих признаков, чтобы весь payload сошёл за рабочий, — поэтому в
    // фикстурах маркер есть у каждой строки.
    _goldenError('metadata-stub');
    _goldenError('hwid-stub');
  });
}

/// Кейс с входом в файле `<name>.txt`.
void _golden(String name) =>
    _goldenOf(name, File('$_dir/$name.txt').readAsStringSync());

/// Кейс с входом, собранным в тесте.
void _goldenOf(String name, String input) {
  test(name, () {
    final result = SubscriptionService.parseBodyForTest(input);
    _compare('$_dir/$name.expected.txt', result.join('\n'));
  });
}

/// Кейс, где парсер обязан отказаться: фиксируется текст исключения.
void _goldenError(String name) {
  test(name, () {
    final input = File('$_dir/$name.txt').readAsStringSync();
    String message;
    try {
      final result = SubscriptionService.parseBodyForTest(input);
      fail('ожидался FormatException, а разбор вернул ${result.length} конфигов');
    } on FormatException catch (e) {
      message = e.message;
    }
    _compare('$_dir/$name.error.txt', message);
  });
}

void _compare(String path, String actual) {
  final file = File(path);

  if (Platform.environment['UPDATE_GOLDEN'] == '1') {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('$actual\n');
    return;
  }

  expect(
    file.existsSync(),
    isTrue,
    reason: 'нет фикстуры $path — сними её: UPDATE_GOLDEN=1 flutter test',
  );
  final expected =
      file.readAsStringSync().replaceAll('\r\n', '\n').trimRight();
  expect(actual.replaceAll('\r\n', '\n').trimRight(), expected);
}
