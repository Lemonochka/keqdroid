import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/services/subscription_service.dart';
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

// так их отдаёт генератор WARP-профилей: общий блок якорем, у узлов только адрес
const _anchors = '''
common: &common
  type: trojan
  port: 443
  password: password
proxies:
  - name: One
    <<: *common
    server: one.example
  - name: Two
    <<: *common
    server: two.example
    port: 8443
proxy-groups:
  - name: Proxy
    type: select
    proxies: [One, Two]
rules:
  - MATCH,Proxy
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

    test('узлы на якорях получают общий блок, свои поля сильнее', () {
      final clash = CustomClashConfig.tryParse(_anchors)!;
      expect(clash.proxies, hasLength(2));
      expect(clash.proxies.first, {
        'name': 'One',
        'type': 'trojan',
        'port': 443,
        'password': 'password',
        'server': 'one.example',
      });
      expect(clash.proxies.last['port'], 8443);
      expect(clash.proxies.last.containsKey('<<'), isFalse);
    });

    test('из списка якорей первый сильнее следующих', () {
      final clash = CustomClashConfig.tryParse('''
a: &a {type: trojan, port: 443, sni: a.example}
b: &b {type: vless, port: 8443, password: password}
proxies:
  - {name: X, server: x.example, <<: [*a, *b]}
''')!;
      expect(clash.proxies.single['type'], 'trojan');
      expect(clash.proxies.single['port'], 443);
      expect(clash.proxies.single['password'], 'password');
    });

    test('в JSON << обычный ключ: слияние только у YAML', () {
      final clash = CustomClashConfig.tryParse(jsonEncode({
        'proxies': [
          {
            'name': 'X',
            'type': 'trojan',
            'server': 'x.example',
            '<<': {'port': 1},
          },
        ],
      }))!;
      expect(clash.proxies.single['<<'], {'port': 1});
      expect(clash.proxies.single.containsKey('port'), isFalse);
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
      // Порты автора и его api — мимо: в наш инбаунд ходит приложение с
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

    // Раньше него стоит только проверка выхода для флага, а она трафик
    // туннеля не ловит.
    test('сам сервер — раньше всех правил для трафика туннеля, иначе круг', () {
      final rules = (build()['rules'] as List).cast<String>();
      expect(rules.first, MihomoConfigGen.exitIpProbeRule('🚀 Proxy'));
      expect(rules.first, contains('NOT,((IN-TYPE,TUN))'));
      expect(rules[1], 'DOMAIN,nl.example,DIRECT');
      expect(rules[2], 'IP-CIDR,198.51.100.10/32,DIRECT,no-resolve');
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

  // 31.10.2026: узел «Ultima Free (YT no ads, no torrent)» из Clash-подписки ронял mihomo на старте,
  // правило искало сервер «no torrent)». ссылкой тот же сервер работал
  group('запятая в имени узла', () {
    const name = '🇫🇮 Ultima Free (YT no ads, no torrent)';
    const yaml = '''
proxies:
  - name: "$name"
    type: vless
    server: fi.example
    port: 443
    uuid: 716e3485-d4f9-4471-9660-fb4b0b838100
    network: grpc
    udp: true
    packet-encoding: xudp
    tls: true
    servername: fi.example
    client-fingerprint: chrome
    reality-opts:
      public-key: oYXosxG2YU6_mQkkPTS8JUnoRxqvaBaG5mH-y0pc2nA
      short-id: 9f2c
      support-x25519mlkem768: true
    grpc-opts:
      grpc-service-name: xyz
proxy-groups:
  - name: Select
    type: select
    proxies: ["$name"]
rules:
  - MATCH,Select
''';

    // так строку правила режет ядро (rules/common/base.go, ParseRulePayload): по запятым, без экранирования
    String coreTarget(String rule) {
      final item = [for (final part in rule.split(',')) part.trim()];
      if (item.length < 2) return '';
      return switch (item.first.toUpperCase()) {
        'MATCH' => item[1],
        'NOT' || 'OR' || 'AND' || 'SUB-RULE' || 'DOMAIN-REGEX' ||
        'PROCESS-NAME-REGEX' || 'PROCESS-PATH-REGEX' =>
          item.last,
        _ => item.length > 2 ? item[2] : '',
      };
    }

    Map<String, dynamic> session() {
      final node = SubscriptionService.clashNodeConfigs(yaml).single;
      return MihomoConfigGen.build(
        node,
        const AppSettings(
          lanSharing: true,
          directRules: 'vk.com',
          proxyRules: 'youtube.com',
        ),
        socksPort: 2080,
        tun: const MihomoTunOptions(
          stack: 'gvisor',
          autoRoute: false,
          fromFileDescriptor: true,
        ),
      );
    }

    test('каждое правило ведёт туда, что ядро найдёт по имени', () {
      final config = session();
      final names = {
        'DIRECT', 'REJECT', 'REJECT-DROP', 'PASS', 'COMPATIBLE',
        for (final p in config['proxies'] as List) (p as Map)['name'],
        for (final g in config['proxy-groups'] as List? ?? const []) (g as Map)['name'],
      };
      final subRules = (config['sub-rules'] as Map? ?? const {}).keys.toSet();
      final lines = [
        ...(config['rules'] as List).cast<String>(),
        for (final set in (config['sub-rules'] as Map? ?? const {}).values)
          ...(set as List).cast<String>(),
      ];
      for (final rule in lines) {
        final target = coreTarget(rule);
        expect(
          names.contains(target) || subRules.contains(target),
          isTrue,
          reason: '$rule -> $target',
        );
      }
    });

    test('трафик идёт на этот узел, имя на экране соединений прежнее', () {
      final config = session();
      final match = (config['rules'] as List).cast<String>().lastWhere(
            (r) => r.startsWith('MATCH'),
          );
      final groups = (config['proxy-groups'] as List).cast<Map>();
      final target = groups.firstWhere((g) => g['name'] == coreTarget(match));
      expect(target['proxies'], [name]);
      expect(((config['proxies'] as List).single as Map)['name'], name);
    });
  });

  // форма из docs/config/proxies/wg.md mihomo: адрес только у пира
  group('wireguard с адресом в peers', () {
    const peers = '''
proxies:
- name: "wg"
  type: wireguard
  ip: 172.16.0.2
  private-key: cGFzc3dvcmQtcGFzc3dvcmQtcGFzc3dvcmQtcGFzcw==
  peers:
    - server: 203.0.113.60
      port: 2408
      public-key: cGFzc3dvcmQtcGFzc3dvcmQtcGFzc3dvcmQtcGFzcw==
      allowed-ips: ['0.0.0.0/0']
''';

    test('адрес и порт берутся у первого пира', () {
      final clash = CustomClashConfig.tryParse(peers);
      expect(clash, isNotNull);
      expect(clash!.endpoint, (address: '203.0.113.60', port: 2408));
      final server = ServerItem.fromRaw(clash.encode());
      expect(server.address, '203.0.113.60');
      expect(server.port, 2408);
    });

    test('адрес пира идёт мимо туннеля', () {
      Socks5Credentials().init('u', 'p');
      final session = MihomoConfigGen.build(
        CustomClashConfig.tryParse(peers)!.encode(),
        const AppSettings(),
        socksPort: 2080,
      );
      expect(
        session['rules'] as List,
        contains(startsWith('IP-CIDR,203.0.113.60/32,DIRECT')),
      );
    });
  });
}
