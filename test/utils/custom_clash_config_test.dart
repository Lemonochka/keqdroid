import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
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

// так строку правила режет ядро (rules/common/base.go, ParseRulePayload): по запятым без экранирования,
// и у каждой части срезает пробелы, только их (trimArr)
String _coreTarget(String rule) {
  final item = [
    for (final part in rule.split(',')) part.replaceAll(RegExp(r'^ +| +$'), ''),
  ];
  if (item.length < 2) return '';
  return switch (item.first.toUpperCase()) {
    'MATCH' => item[1],
    'NOT' || 'OR' || 'AND' || 'SUB-RULE' || 'DOMAIN-REGEX' ||
    'PROCESS-NAME-REGEX' || 'PROCESS-PATH-REGEX' =>
      item.last,
    _ => item.length > 2 ? item[2] : '',
  };
}

void _expectRulesResolve(Map<String, dynamic> config) {
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
    final target = _coreTarget(rule);
    expect(
      names.contains(target) || subRules.contains(target),
      isTrue,
      reason: '$rule -> $target',
    );
  }
}

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

    test('цель правил: первая названная группа, без групп первый узел, без имени DIRECT', () {
      String target(Object config) =>
          CustomClashConfig.tryParse(jsonEncode(config))!.primaryTarget;
      const node = {'name': ' DE ', 'type': 'trojan', 'server': 'de.example'};
      expect(
        target({
          'proxies': [node],
          'proxy-groups': [
            {'name': '  ', 'type': 'select', 'proxies': [' DE ']},
            {'name': ' Main ', 'type': 'select', 'proxies': [' DE ']},
          ],
        }),
        'Main',
      );
      expect(target({'proxies': [node]}), 'DE');
      expect(
        target({
          'proxies': [
            {'type': 'trojan', 'server': 'x.example'},
            node,
          ],
        }),
        'DIRECT',
      );
      expect(
        target({
          'proxies': [
            {...node, 'name': '   '},
          ],
        }),
        'DIRECT',
      );
    });

    test('группа, которая только звено dialer-proxy, целью правил не становится', () {
      String target(Map<String, dynamic> config) =>
          CustomClashConfig.tryParse(jsonEncode(config))!.primaryTarget;
      Map<String, dynamic> node(String name, [String? via]) => {
            'name': name,
            'type': 'trojan',
            'server': '$name.example',
            'dialer-proxy': ?via,
          };
      // одноузловой из подписки: группа-звено первая и единственная
      expect(
        target({
          'proxies': [node('DE', 'Entry'), node('RU')],
          'proxy-groups': [
            {'name': 'Entry', 'type': 'url-test', 'proxies': ['RU']},
          ],
          'rules': ['MATCH,DE'],
        }),
        'DE',
      );
      final relayFirst = {
        'proxies': [node('DE', 'Relay'), node('RU'), node('NL')],
        'proxy-groups': [
          {'name': 'Relay', 'type': 'select', 'proxies': ['RU']},
          {'name': 'Proxy', 'type': 'select', 'proxies': ['DE', 'NL']},
        ],
        'rules': ['MATCH,Proxy'],
      };
      expect(target(relayFirst), 'Proxy');
      // звено, на которое ведут и правила или другая группа, остаётся целью, с правилами провайдера и без
      final sharedAuto = {
        'proxies': [node('DE', 'Auto'), node('RU'), node('NL')],
        'proxy-groups': [
          {'name': 'Auto', 'type': 'url-test', 'proxies': ['RU', 'NL']},
          {'name': 'Proxy', 'type': 'select', 'proxies': ['Auto', 'DE']},
        ],
        'rules': ['MATCH,Auto'],
      };
      expect(target(sharedAuto), 'Auto');
      expect(
        CustomClashConfig.tryParse(jsonEncode(sharedAuto))!
            .withoutProviderRules()
            .primaryTarget,
        'Auto',
      );
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

    test('серверы, проброс портов и правка системы из конфига автора не доходят до ядра', () {
      final authored = '''
$_yaml
ss-config: ss://aes-128-gcm:pass@:8388
vmess-config: vmess://aes-128-gcm:11111111-2222-3333-4444-555555555555@:8389
tuic-server:
  enable: true
  listen: 0.0.0.0:10443
tunnels:
  - tcp/udp,0.0.0.0:6553,8.8.8.8:53,DE WS
iptables:
  enable: true
ntp:
  enable: true
  server: time.apple.com
  write-to-system: true
dns:
  enable: true
  listen: 0.0.0.0:1053
  nameserver: [https://1.1.1.1/dns-query]
''';
      final config = MihomoConfigGen.build(
        authored,
        const AppSettings(),
        socksPort: 2080,
      );
      for (final key in [
        'ss-config',
        'vmess-config',
        'tuic-server',
        'tunnels',
        'iptables',
      ]) {
        expect(config.containsKey(key), isFalse, reason: key);
      }
      expect(config['ntp'], {'enable': true, 'server': 'time.apple.com'});
      expect(config['dns'], {
        'enable': true,
        'nameserver': ['https://1.1.1.1/dns-query'],
      }, reason: 'DNS автора остаётся, без своего сервера на устройстве');
    });

    group('наше поверх провайдерского', () {
      final authored = '''
${_yaml.replaceFirst('mode: rule', 'mode: global')}
hosts:
  provider.example: 10.0.0.1
  shared.example: 10.0.0.2
dns:
  enable: true
  fake-ip-range: 28.0.0.1/8
  nameserver: [https://dns.provider.example/dns-query]
''';
      const tun = MihomoTunOptions(device: 'tun-keqdis', stack: 'gvisor');
      Map<String, dynamic> session(AppSettings settings) => MihomoConfigGen.build(
            authored,
            settings,
            socksPort: 2080,
            tun: tun,
          );

      test('режим всегда по правилам: global обошёл бы защиту и сплит', () {
        expect(session(const AppSettings())['mode'], 'rule');
      });

      test('адрес туннеля по диапазону fake-ip провайдера, с нашим DNS по нашему', () {
        expect(session(const AppSettings())['rules'],
            contains('IP-CIDR,28.0.0.0/30,DIRECT,no-resolve'));
        expect(
          session(const AppSettings(ignoreProviderDns: true))['rules'],
          contains('IP-CIDR,${MihomoConfigGen.tunInterfaceRange},DIRECT,no-resolve'),
        );
      });

      test('DNS провайдера по умолчанию, наш только когда человек его поставил', () {
        expect((session(const AppSettings())['dns'] as Map)['nameserver'],
            ['https://dns.provider.example/dns-query']);
        final own = session(const AppSettings(ignoreProviderDns: true))['dns'] as Map;
        expect(own['nameserver'], isNot(contains('https://dns.provider.example/dns-query')));
      });

      test('hosts человека поверх hosts провайдера, параллельное подключение его', () {
        final config = session(const AppSettings(
          xrayCore: XrayCoreSettings(
            dnsHosts: 'shared.example 10.9.9.9',
            concurrentDial: true,
          ),
        ));
        expect(config['hosts'], {
          'provider.example': '10.0.0.1',
          'shared.example': '10.9.9.9',
        });
        expect(config['tcp-concurrent'], isTrue);
        expect(session(const AppSettings())['hosts'], {
          'provider.example': '10.0.0.1',
          'shared.example': '10.0.0.2',
        });
      });
    });

    test('правила автора по приложениям включают поиск процесса, без них он выключен', () {
      expect(build()['find-process-mode'], 'off');
      final withProcess = _yaml.replaceFirst(
        '  - DOMAIN-SUFFIX,author.example,DIRECT',
        '  - AND,((PROCESS-NAME,org.telegram.messenger),(NETWORK,UDP)),DE WS',
      );
      expect(
        MihomoConfigGen.build(withProcess, const AppSettings(), socksPort: 2080)['find-process-mode'],
        'strict',
      );
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
      _expectRulesResolve(session());
    });

    test('трафик идёт на этот узел, имя на экране соединений прежнее', () {
      final config = session();
      final match = (config['rules'] as List).cast<String>().lastWhere(
            (r) => r.startsWith('MATCH'),
          );
      final groups = (config['proxy-groups'] as List).cast<Map>();
      final target = groups.firstWhere((g) => g['name'] == _coreTarget(match));
      expect(target['proxies'], [name]);
      expect(((config['proxies'] as List).single as Map)['name'], name);
    });
  });

  // 02.11.2026: у провайдера имя узла начиналось или кончалось пробелом (Германия, Россия Москва).
  // без шаблона такой сервер ядро не запускало: proxy [🇩🇪 ⚡ Германия] not found
  group('пробел по краю имени узла', () {
    String node(String name) => SubscriptionService.clashNodeConfigs('''
proxies:
  - name: "$name"
    type: vless
    server: de.example
    port: 8443
    uuid: 716e3485-d4f9-4471-9660-fb4b0b838100
    network: tcp
    udp: true
    packet-encoding: xudp
    tls: true
    servername: de.example
    client-fingerprint: firefox
    reality-opts:
      public-key: oYXosxG2YU6_mQkkPTS8JUnoRxqvaBaG5mH-y0pc2nA
      short-id: 9f2c
    smux: {enabled: true, padding: true, protocol: smux, max-connections: 3}
    serverDescription: x2 10 Gbit/s
''').single;

    Map<String, dynamic> session(String name, {bool ignoreProviderRules = false}) =>
        MihomoConfigGen.build(
          node(name),
          AppSettings(
            lanSharing: true,
            directRules: 'vk.com',
            proxyRules: 'youtube.com',
            ignoreProviderRules: ignoreProviderRules,
          ),
          socksPort: 2080,
          tun: const MihomoTunOptions(
            stack: 'gvisor',
            autoRoute: false,
            fromFileDescriptor: true,
          ),
        );

    for (final name in [' 🇩🇪 ⚡ Германия', '🇷🇺 ⚡ Россия Москва ']) {
      test('каждое правило ведёт туда, что ядро найдёт по имени [$name]', () {
        expect(node(name), startsWith('{'), reason: 'узел должен остаться Clash');
        _expectRulesResolve(session(name));
        _expectRulesResolve(session(name, ignoreProviderRules: true));
      });

      test('трафик идёт на этот узел, имя на экране соединений прежнее [$name]', () {
        final config = session(name);
        final match = (config['rules'] as List).cast<String>().lastWhere(
              (r) => r.startsWith('MATCH'),
            );
        final groups = (config['proxy-groups'] as List).cast<Map>();
        final target = groups.firstWhere((g) => g['name'] == _coreTarget(match));
        expect(target['proxies'], [name]);
        expect(((config['proxies'] as List).single as Map)['name'], name);
      });
    }

    test('имя без пробела по краю конфиг не меняет', () {
      final config = session('🇫🇷 ⚡ Франция');
      expect(config.containsKey('proxy-groups'), isFalse);
      _expectRulesResolve(config);
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
