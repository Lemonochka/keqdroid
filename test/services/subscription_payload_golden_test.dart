import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/subscription_body_parser.dart';

// Корпус форм payload'а: вход → список конфигов, побайтово.
//
// Предохранитель subscription_body_parser.dart. Существующие тесты в
// subscription_service_test.dart проверяют свойства (имя с пробелами
// уцелело, заглушка провайдера отвергнута); здесь фиксируется весь список на
// выходе целиком, включая порядок: при перестановке кода парсера меняться не
// должно ничто.
//
// Вместе с разбором тела фиксируется и остальное, что парсер отдаёт сервису:
// разбор HTML-страницы, ссылки на подписку в HTML, трафик и срок из имён
// серверов, раскладка Clash по узлам и сводка пропущенных узлов.
//
// Панели отдают подписку в дюжине несовместимых форм, и порядок кандидатов в
// разборе отражает реальный опыт, а не стройность. Корпус нужен, чтобы этот
// опыт нельзя было случайно потерять при перестановке кода.
//
// Перегенерация ожидаемых результатов:
//
// UPDATE_GOLDEN=1 flutter test test/services/subscription_payload_golden_test.dart
//
// Входы правятся руками, выходы только перегенерацией. Если
// перегенерация изменила .expected.txt, это и есть изменение поведения
// парсера: дифф читается глазами, а не принимается на веру.
const _dir = 'test/fixtures/subscription_payloads';

// Ничего настоящего: URL подписки секретен, и в фикстурах ему не место.
// Все адреса из TEST-NET-2/3, UUID нулевой, пароли буквально password.
void main() {
  group('golden: формы payload как есть', () {
    _golden('plain-uri-list');
    _golden('json-proxy-array');
    _golden('clash-yaml');
    _golden('clash-yaml-anchors');
    // WARP из файла: AWG и MASQUE ссылкой не записать, каждый узел исполняет mihomo
    _golden('clash-yaml-warp');
    // мусорный адрес в публичном списке ронял Uri и вместе с ним всю подписку
    _golden('clash-yaml-broken-node');
    // как docs/example/conf.md mihomo: узлы в провайдере, рядом локальный direct
    _golden('clash-providers-direct');
    _golden('clash-wireguard-peers');
    // Uri не берёт @ # / ? [ ] в userInfo: trojan с таким паролем падал вместе со всей подпиской
    _golden('clash-yaml-password-chars');
    // шаблон с группами: серверами остаются узлы, сам шаблон хранится рядом (clash_template.dart)
    _golden('clash-template-groups');
    // каждый тип узла и каждая вложенная карта opts, которую разбор переводит в ссылку
    _golden('clash-yaml-all-types');
    // таб в отступе YAML не пропускает, узлы достаёт построчный разбор
    _golden('clash-yaml-tabs');
    _golden('clash-yaml-tabs-tail');
    _golden('html-pre');
    _golden('html-js-var');
    // &#58;, &#x3a; и : вместо двоеточия в схеме
    _golden('html-entities');
    _golden('xray-json-object');
    // комментарии // /* */ и # xray читает сам, а внутри строк они не комментарии
    _golden('xray-json-comments');
    _golden('xray-json-array');
    // ключи из выгрузок других клиентов: address, add, ps, passwd, vmess без type
    _golden('json-proxy-aliases');
    // до 20.11.2026 null в JSON обрывал обход на первом же узле, и второй терялся
    _golden('json-proxy-null-field');
    _golden('mixed-links-and-config');
    _golden('fragment-with-spaces');
    _golden('wss-in-html');
    // тело по документации Happ: строки #profile-* и ссылка happ://routing серверами не становятся
    _golden('happ-routing-in-body');
    _golden('singbox-outbounds');
    // WARP в обоих видах (endpoints с 1.11 и старый аутбаунд), socks и http: ссылки нет только у WireGuard и http
    _golden('singbox-wireguard');
    // служебные строки с трафиком и сроком отсеиваются, настоящий сервер остаётся
    _golden('meta-in-remarks');
  });

  group('golden: входы, собранные в тесте', () {
    final plain = _read('plain-uri-list');
    final xray = _xrayLine();

    // готовый конфиг xray строкой base64 рядом с обычной ссылкой
    _goldenOf(
      'xray-json-base64-line',
      '${LineSplitter.split(plain).first}\n${base64.encode(utf8.encode(xray))}',
    );
    // список ссылок base64 в поле JSON: его находит обход структуры
    _goldenOf(
      'json-base64-field',
      jsonEncode({'name': 'Panel', 'data': base64.encode(utf8.encode(plain))}),
    );
    // до 20.11.2026 строки узлов переполняли очередь обхода, и из ста узлов доходило 25
    _goldenOf(
      'json-many-proxies',
      jsonEncode([
        for (var i = 0; i < 100; i++)
          {
            'name': 'Many $i',
            'type': 'trojan',
            'server': '203.0.113.${i + 1}',
            'port': 10000 + i,
            'password': 'password$i',
            'sni': 'many$i.example',
          },
      ]),
    );
  });

  group('golden: base64-обёртки', () {
    // Обёртки выводятся из plain-uri-list, а не лежат отдельными файлами:
    // base64-блоб в фикстуре ревьюеру не говорит ничего, а так гарантировано,
    // что раскодированное содержимое совпадает с обычным случаем, то есть
    // тест проверяет саму обёртку, а не ещё один набор ссылок.
    final plain = _read('plain-uri-list');
    final once = base64.encode(utf8.encode(plain));

    _goldenOf('base64-single', once);
    _goldenOf('base64-double', base64.encode(utf8.encode(once)));
    _goldenOf(
      'base64-urlsafe-nopad',
      base64Url.encode(utf8.encode(plain)).replaceAll('=', ''),
    );
  });

  group('golden: тело больше 1 МиБ', () {
    // регулярки и base64 по такому телу роняли стек в AOT, поэтому разбор
    // идёт без вариантов текста: JSON xray и sing-box, затем только Clash
    final comments = '# ${'x' * 1000}\n' * 1100;
    final filler = 'x' * (1 << 20);

    _goldenOf('large-clash-yaml', '${_read('clash-yaml')}\n$comments');
    _goldenOf(
      'large-clash-providers',
      '${_read('clash-providers-direct')}\n$comments',
    );
    _goldenOf(
      'large-xray-json-array',
      jsonEncode([...jsonDecode(_read('xray-json-array')) as List, filler]),
    );
    _goldenOf(
      'large-singbox',
      jsonEncode({
        ...jsonDecode(_read('singbox-outbounds')) as Map<String, dynamic>,
        'padding': filler,
      }),
    );
    // простой список такого размера не разбирается вовсе
    _goldenErrorOf(
      'large-plain-list',
      List.filled(1700, _read('plain-uri-list')).join('\n'),
    );
  });

  group('golden: payload без серверов', () {
    // Служебные ноды вместо конфигов: подписка жива, но отдавать нечего.
    // Парсер обязан бросить FormatException с внятным текстом: по нему
    // ветвится UI, поэтому текст фиксируется тоже.
    //
    // Заглушки узнаются по двум независимым признакам: null-route эндпоинт
    // (0.0.0.0 с портом ≤ 1) и маркеры в имени. Достаточно одной строки без
    // обоих признаков, чтобы весь payload сошёл за рабочий, поэтому в
    // фикстурах маркер есть у каждой строки.
    _goldenError('metadata-stub');
    _goldenError('hwid-stub');
    _goldenError('expired-stub');
    _goldenError('no-hosts-stub');
    _goldenError('remnawave-stub');
    // имена служебные, а адреса настоящие: заглушкой провайдера это не считается
    _goldenError('metadata-names-only');
    // Конфиг sing-box из одних групп и выходов мимо прокси даёт ту же болванку.
    _goldenError('singbox-stub');
    _goldenError('clash-stub');
    _goldenError('clash-json-empty');
    _goldenError('xray-stub');
    _goldenError('json-unknown-config');
    _goldenError('json-unknown-array');
    _goldenError('no-links');
  });

  group('golden: HTML-страница', () {
    // ветка fetchRaw для text/html: блоки pre, code, textarea и script,
    // потом длинный base64, и только потом обход ссылок на другие страницы
    _goldenHtml('html-pre');
    _goldenHtml('html-js-var');
    _goldenHtml('wss-in-html');
    _goldenHtml('html-entities');
    _goldenHtml('html-xray-json');
    _goldenHtml('html-sub-links');

    final plain = _read('plain-uri-list');
    final once = base64.encode(utf8.encode(plain));
    _goldenHtmlOf('html-base64-blob', _page(once));
    _goldenHtmlOf(
      'html-double-base64',
      _page(base64.encode(utf8.encode(once))),
    );
    // base64 с переносом через 76 знаков, как пишет MIME
    _goldenHtmlOf(
      'html-base64-xray',
      _page(_wrap76(base64.encode(utf8.encode(_xrayLine())))),
    );
  });

  group('golden: ссылки на подписку в HTML', () {
    _goldenLinks('html-sub-links');
  });

  group('golden: трафик и срок из имён', () {
    _goldenMeta('meta-in-remarks');
    // дата 2026-01-01 до 20.11.2026 читалась как 26.01.01, то есть 2001 год
    _goldenMeta('metadata-stub');
    String named(String name) =>
        'vless://00000000-0000-4000-8000-000000000000@198.51.100.210:443?type=tcp#$name';
    // адрес в имени давал срок в 2035 году, версия ядра в 2032, 31 февраля уезжало в март
    _goldenMetaOf(
      'meta-date-traps',
      [
        named('DE 185.12.34.56'),
        named('mihomo 1.19.31'),
        named('Срок 31.02.2027'),
      ].join('\n'),
    );
    _goldenMetaOf('meta-date-sentence-end', named('Подписка до 15.03.2027.'));
    _goldenMeta('plain-uri-list');

    final meta = _read('meta-in-remarks');
    final once = base64.encode(utf8.encode(meta));
    _goldenMetaOf('meta-base64', once);
    _goldenMetaOf('meta-double-base64', base64.encode(utf8.encode(once)));

    String b64u(String s) =>
        base64Url.encode(utf8.encode(s)).replaceAll('=', '');
    final vmessJson = jsonEncode({
      'v': '2',
      'ps': 'Used 750 MB',
      'add': '198.51.100.200',
      'port': '443',
      'id': '00000000-0000-4000-8000-000000000000',
      'aid': '0',
      'net': 'tcp',
      'tls': 'tls',
    });
    final vmess = 'vmess://${base64.encode(utf8.encode(vmessJson))}';
    final ssrHead =
        '198.51.100.201:8389:origin:aes-256-cfb:plain:${b64u('password')}';
    final ssrRemarks = b64u('Безлимит: 3 ГБ / ∞, до 15/03/2027');
    final ssr = 'ssr://${b64u('$ssrHead/?remarks=$ssrRemarks')}';
    // имя у vmess внутри base64, у ssr в параметре remarks
    _goldenMetaOf('meta-vmess-ssr', '$vmess\n$ssr');
  });

  const clash = [
    'clash-yaml',
    'clash-yaml-anchors',
    'clash-yaml-warp',
    'clash-yaml-broken-node',
    'clash-providers-direct',
    'clash-wireguard-peers',
    'clash-yaml-password-chars',
    'clash-template-groups',
    'clash-yaml-all-types',
    'clash-yaml-tabs',
    'clash-yaml-tabs-tail',
  ];

  group('golden: узлы Clash по одному', () {
    // так раскладываются файл и буфер обмена (import_payload.dart)
    for (final name in clash) {
      _goldenNodes(name);
    }
  });

  group('golden: пропущенные узлы Clash', () {
    // сводка уходит в журнал, когда узлы неизвестного типа выпадают
    for (final name in clash) {
      _goldenSkipped(name);
    }
  });
}

String _read(String name) => File('$_dir/$name.txt').readAsStringSync();

// вторая строка mixed-links-and-config: готовый конфиг xray одной строкой
String _xrayLine() =>
    LineSplitter.split(_read('mixed-links-and-config')).elementAt(1);

String _page(String blob) =>
    '<!DOCTYPE html>\n<html><body>\n<h1>Nodes</h1>\n'
    '<div class="blob">\n$blob\n</div>\n</body></html>\n';

String _wrap76(String s) => [
  for (var i = 0; i < s.length; i += 76)
    s.substring(i, (i + 76).clamp(0, s.length)),
].join('\n');

// Кейс с входом в файле <name>.txt.
void _golden(String name) => _goldenOf(name, _read(name));

// Кейс с входом, собранным в тесте.
void _goldenOf(String name, String input) {
  test(name, () {
    final result = SubscriptionBodyParser.parseBody(input);
    _compare('$_dir/$name.expected.txt', result.join('\n'));
  });
}

void _goldenError(String name) => _goldenErrorOf(name, _read(name));

// Кейс, где парсер обязан отказаться: фиксируется текст исключения.
void _goldenErrorOf(String name, String input) {
  test(name, () {
    String message;
    try {
      final result = SubscriptionBodyParser.parseBody(input);
      fail(
        'ожидался FormatException, а разбор вернул ${result.length} конфигов',
      );
    } on FormatException catch (e) {
      message = e.message;
    }
    _compare('$_dir/$name.error.txt', message);
  });
}

void _goldenHtml(String name) => _goldenHtmlOf(name, _read(name));

void _goldenHtmlOf(String name, String input) {
  test('$name как страница', () {
    final result = SubscriptionBodyParser.extractConfigsFromHtml(input);
    _compare('$_dir/$name.html.expected.txt', result?.join('\n') ?? 'null');
  });
}

void _goldenLinks(String name) {
  test('$name, ссылки', () {
    final result = SubscriptionBodyParser.extractSubscriptionUrlsFromHtml(
      _read(name),
      baseUrl: 'https://panel.example/page/',
    );
    _compare('$_dir/$name.links.expected.txt', result.join('\n'));
  });
}

void _goldenMeta(String name) => _goldenMetaOf(name, _read(name));

void _goldenMetaOf(String name, String input) {
  test('$name, трафик и срок', () {
    final meta = SubscriptionBodyParser.extractMetaFromBody(input);
    _compare(
      '$_dir/$name.meta.expected.txt',
      'used: ${meta.usedBytes}\n'
          'total: ${meta.totalBytes}\n'
          'expires: ${meta.expiresAt?.toIso8601String()}',
    );
  });
}

void _goldenNodes(String name) {
  test('$name по узлам', () {
    final result = SubscriptionBodyParser.clashNodeConfigs(_read(name));
    _compare('$_dir/$name.nodes.expected.txt', result.join('\n'));
  });
}

void _goldenSkipped(String name) {
  test('$name, пропущенные', () {
    final counts = SubscriptionBodyParser.unsupportedClashNodes(_read(name));
    final summary = SubscriptionBodyParser.skippedNodesSummary(counts);
    _compare('$_dir/$name.skipped.expected.txt', '$counts\n$summary');
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
  final expected = file.readAsStringSync().replaceAll('\r\n', '\n').trimRight();
  expect(actual.replaceAll('\r\n', '\n').trimRight(), expected);
}
