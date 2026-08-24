import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/utils/custom_clash_config.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// Готовый конфиг Clash в роли сервера — то же, чем для xray является
/// готовый JSON: прокси, группы и правила авторские, наше дело — инбаунд,
/// снифер и свои списки роутинга поверх.
const _yaml = '''
# профиль панели
port: 7890
socks-port: 7891
mixed-port: 7892
allow-lan: true
mode: rule
external-controller: 127.0.0.1:9090
secret: "panel-secret"
tun:
  enable: true
  stack: system
proxies:
  - name: "NL Reality"
    type: vless
    server: nl.example
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    network: tcp
    tls: true
    servername: www.example.org
    client-fingerprint: chrome
    flow: xtls-rprx-vision
    reality-opts:
      public-key: aGVsbG8gd29ybGQgaGVsbG8gd29ybGQgaGVsbG8gd28
      short-id: 0123abcd
  - name: "DE WS"
    type: trojan
    server: de.example
    port: 443
    password: password
    network: ws
    sni: de.example
    ws-opts:
      path: /tr
      headers:
        Host: de.example
proxy-groups:
  - name: "🚀 Proxy"
    type: select
    proxies: ["NL Reality", "DE WS"]
rules:
  - DOMAIN-SUFFIX,author.example,DIRECT
  - MATCH,🚀 Proxy
''';

void main() {
  setUp(() => Socks5Credentials().init('user', 'pass'));

  group('разбор', () {
    test('YAML читается, имя и endpoint берутся из конфига', () {
      final clash = CustomClashConfig.tryParse(_yaml)!;
      expect(clash.proxies, hasLength(2));
      expect(clash.address, 'nl.example');
      expect(clash.port, 443);
      // Цель для наших правил — ГРУППА, а не узел: пользователь переключает
      // узлы внутри неё, и правило обязано ехать за его выбором.
      expect(clash.primaryTarget, '🚀 Proxy');
    });

    test('вложенные карты доживают до конфига', () {
      final clash = CustomClashConfig.tryParse(_yaml)!;
      final reality = clash.proxies.first['reality-opts'] as Map;
      expect(reality['public-key'], isNotEmpty);
    });

    test('json-форма того же конфига равнозначна', () {
      final asJson = CustomClashConfig.tryParse(_yaml)!.encode();
      final reparsed = CustomClashConfig.tryParse(asJson)!;
      expect(reparsed.address, 'nl.example');
      expect(reparsed.primaryTarget, '🚀 Proxy');
    });

    test('не clash — не clash', () {
      expect(CustomClashConfig.tryParse('vless://uuid@a.example:443'), isNull);
      expect(CustomClashConfig.tryParse('{"outbounds":[]}'), isNull);
      expect(CustomClashConfig.tryParse('proxies: []'), isNull);
      expect(CustomClashConfig.describeProblem('proxies: []'), isNotNull);
    });

    test('сервер узнаётся приложением как clash', () {
      final server = ServerItem(
        id: 'x',
        config: _yaml,
        type: ServerItemType.manual,
      );
      expect(server.protocol, 'clash');
      expect(server.address, 'nl.example');
      expect(server.port, 443);
    });
  });

  group('конфиг сессии', () {
    Map<String, dynamic> build([AppSettings settings = const AppSettings()]) =>
        MihomoConfigGen.build(
          _yaml,
          settings,
          socksPort: 2080,
          resolvedServerIp: '198.51.100.10',
          apiPort: 39001,
          apiSecret: 'ours',
        );

    test('инбаунд наш, авторский — вырезан', () {
      final config = build();
      expect(config['socks-port'], 2080);
      expect(config['bind-address'], '127.0.0.1');
      expect(config['authentication'], ['user:pass']);
      // Порты автора и его api — мимо: в наш инбаунд ходит tun2socks с
      // известными ему кредами, а api читает экран «Соединения».
      expect(config.containsKey('port'), isFalse);
      expect(config.containsKey('mixed-port'), isFalse);
      expect(config['external-controller'], '127.0.0.1:39001');
      expect(config['secret'], 'ours');
      expect(config['allow-lan'], isFalse);
    });

    test('tun автора удалён — туннель держит VpnService', () {
      // С авторским `tun.enable` ядро полезет поднимать СВОЁ устройство
      // поверх нашего, и сессия умрёт на старте.
      expect(build().containsKey('tun'), isFalse);
    });

    test('авторские прокси и группы сохранены как есть', () {
      final config = build();
      expect((config['proxies'] as List), hasLength(2));
      expect((config['proxy-groups'] as List), hasLength(1));
      final reality =
          (config['proxies'] as List).first as Map<String, dynamic>;
      expect(reality['reality-opts'], isA<Map>());
      expect(reality['flow'], 'xtls-rprx-vision');
    });

    test('наши правила — после авторских, но перед их MATCH', () {
      final rules = (build(const AppSettings(
        directRules: 'vk.com',
        blockedRules: 'ads.example',
        proxyRules: 'youtube.com',
      ))['rules'] as List)
          .cast<String>();

      final author = rules.indexOf('DOMAIN-SUFFIX,author.example,DIRECT');
      final ours = rules.indexOf('DOMAIN-SUFFIX,vk.com,DIRECT');
      final match = rules.indexWhere((r) => r.startsWith('MATCH'));

      expect(author, greaterThanOrEqualTo(0));
      expect(author, lessThan(ours));
      expect(ours, lessThan(match));
      expect(rules[match], 'MATCH,🚀 Proxy');
      // «В прокси» у наших правил — авторская группа, а не наш выдуманный тег.
      expect(rules, contains('DOMAIN-SUFFIX,youtube.com,🚀 Proxy'));
    });

    test('сам сервер — первым правилом, иначе круг', () {
      final rules = (build()['rules'] as List).cast<String>();
      expect(rules.first, 'DOMAIN,nl.example,DIRECT');
      expect(rules[1], 'IP-CIDR,198.51.100.10/32,DIRECT,no-resolve');
    });

    test('снифер наш: без него доменные правила не сработают вовсе', () {
      final sniffer = build()['sniffer'] as Map<String, dynamic>;
      expect(sniffer['enable'], isTrue);
      expect(sniffer['parse-pure-ip'], isTrue);
    });

    test('LAN-раздача цепляется к авторской группе', () {
      final config = build(const AppSettings(lanSharing: true));
      final rules = ((config['sub-rules'] as Map)[MihomoConfigGen.lanRuleSet]
              as List)
          .cast<String>();
      expect(rules.first, endsWith(',🚀 Proxy'));
      expect(rules.last, 'MATCH,REJECT');
    });

    test('конфиг остаётся json-совместимым (его читает ядро)', () {
      expect(() => jsonEncode(build()), returnsNormally);
    });
  });
}
