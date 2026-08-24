import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/utils/import_payload.dart';

/// Готовый конфиг Clash вставляют так же, как ссылку, — целым текстом.
///
/// Резать его построчно нельзя: в YAML нет ни фигурной скобки в начале, ни
/// строки-ссылки, поэтому один профиль превращался в десятки «Unsupported
/// format» — при том, что сервером такой конфиг приложение исполняет (через
/// подписку он приезжал и работал).
const _clashYaml = '''
mixed-port: 7890
proxies:
  - name: "node-1"
    type: vless
    server: example.com
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    tls: true
    network: tcp
proxy-groups:
  - name: PROXY
    type: select
    proxies: ["node-1"]
rules:
  - MATCH,PROXY
''';

void main() {
  test('YAML-конфиг Clash остаётся одним конфигом, а не строками', () {
    final configs = splitServerImportPayload(_clashYaml);

    expect(configs, hasLength(1));
    expect(
      ServersNotifier.validateServerConfig(configs.single),
      isNull,
      reason: 'валидация обязана принять его как сервер',
    );
  });

  test('нормализуется в JSON — хранится он всегда в одной форме', () {
    final config = splitServerImportPayload(_clashYaml).single;
    final decoded = jsonDecode(config) as Map<String, dynamic>;

    expect((decoded['proxies'] as List).single['name'], 'node-1');
  });

  test('негодный clash отдаётся целиком — ради внятной причины', () {
    // Узлы за `proxy-providers`, но групп нет: правилу некуда указывать.
    const broken = '''
proxy-providers:
  main:
    url: "https://example.com/sub"
    type: http
''';
    final configs = splitServerImportPayload(broken);

    expect(configs, hasLength(1));
    final problem = ServersNotifier.validateServerConfig(configs.single);
    expect(problem, isNotNull);
    expect(
      problem,
      contains('proxy-groups'),
      reason: 'причина обязана быть названа, а не «формат не поддерживается»',
    );
  });

  test('список ссылок по-прежнему режется построчно', () {
    final configs = splitServerImportPayload(
      'vless://uuid@a.example:443?type=tcp&security=none\n'
      'vless://uuid@b.example:443?type=tcp&security=none',
    );

    expect(configs, hasLength(2));
  });
}
