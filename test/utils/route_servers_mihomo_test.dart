import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/services/traffic_split_service.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/route_servers.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// «Другой сервер» маршрута на mihomo: отдельный выход в конфиге сессии и
/// правила на него между «напрямую» и «через VPN» — там, где ТЗ ставит его
/// в разделе всех приложений.
const _active = 'vless://00000000-0000-4000-8000-000000000000@nl.example:443'
    '?type=tcp&security=tls&sni=nl.example#NL';
const _de = 'trojan://pw@de.example:443?security=tls&sni=de.example#DE';

const _settings = AppSettings(
  directRules: 'vk.com',
  proxyRules: 'discord.com',
  blockedRules: 'ads.example',
);

const _toDe = RouteServerOutbound(
  tag: 'keq-srv-0',
  serverId: 'de',
  config: _de,
  address: 'de.example',
  entries: 'youtube.com, geoip:de',
);

const _clashYaml = '''
proxies:
  - name: "NL"
    type: trojan
    server: nl.example
    port: 443
    password: password
    sni: nl.example
proxy-groups:
  - name: "Proxy"
    type: select
    proxies: ["NL"]
rules:
  - DOMAIN-SUFFIX,author.example,DIRECT
  - MATCH,Proxy
''';

// как у генератора WARP-профилей: общий блок якорем, третий узел ходит через первый
const _warpYaml = '''
warp-common: &warp-common
  type: wireguard
  ip: 172.16.0.2
  private-key: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEA=
  public-key: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIA=
  udp: true
proxies:
  - name: "[WARP] One"
    <<: *warp-common
    server: warp.example
    port: 4500
  - name: "[WARP] Two"
    <<: *warp-common
    server: warp.example
    port: 2408
  - name: "[WARP] Inner"
    <<: *warp-common
    server: relay.example
    port: 4500
    dialer-proxy: "[WARP] One"
  - name: Unused
    type: trojan
    server: unused.example
    port: 443
    password: password
proxy-groups:
  - name: Cloudflare
    type: select
    proxies: ["[WARP] One", "[WARP] Two", "[WARP] Inner", DIRECT]
rules:
  - DST-PORT,53,DIRECT
  - MATCH,Cloudflare
''';

List<String> _rules(Map<String, dynamic> c) =>
    (c['rules'] as List).cast<String>();

List<Map<String, dynamic>> _proxies(Map<String, dynamic> c) =>
    (c['proxies'] as List).cast<Map<String, dynamic>>();

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  test('сервер маршрута — отдельный выход со своим именем', () {
    final c = MihomoConfigGen.build(
      _active,
      _settings,
      socksPort: 2080,
      routeServers: const [_toDe],
    );
    final proxies = _proxies(c);
    expect(proxies.map((p) => p['name']), [
      MihomoConfigGen.proxyName,
      'keq-srv-0',
    ]);
    expect(proxies.last['server'], 'de.example');
    expect(proxies.last['type'], 'trojan');
  });

  test('правила на него — после «напрямую», раньше «через VPN»', () {
    final rules = _rules(MihomoConfigGen.build(
      _active,
      _settings,
      socksPort: 2080,
      routeServers: const [_toDe],
    ));
    final direct = rules.indexOf('DOMAIN-SUFFIX,vk.com,DIRECT');
    final server = rules.indexOf('DOMAIN-SUFFIX,youtube.com,keq-srv-0');
    final proxy = rules.indexOf(
      'DOMAIN-SUFFIX,discord.com,${MihomoConfigGen.proxyName}',
    );
    final block = rules.indexOf('DOMAIN-SUFFIX,ads.example,REJECT');
    expect(server, isNonNegative, reason: '$rules');
    expect(block, lessThan(server));
    expect(direct, lessThan(server));
    expect(server, lessThan(proxy));
    expect(rules, contains('GEOIP,de,keq-srv-0,no-resolve'));
  });

  test('к самому серверу маршрута — напрямую, как к активному', () {
    final rules = _rules(MihomoConfigGen.build(
      _active,
      _settings,
      socksPort: 2080,
      routeServers: const [_toDe],
    ));
    expect(rules, contains('DOMAIN,de.example,DIRECT'));
    expect(
      rules.indexOf('DOMAIN,de.example,DIRECT'),
      lessThan(rules.indexOf('DOMAIN-SUFFIX,youtube.com,keq-srv-0')),
    );
  });

  test('скачанные списки сервера — своим набором', () {
    final c = MihomoConfigGen.build(
      _active,
      _settings,
      socksPort: 2080,
      routeServers: [_toDe.copyWith(listDomains: ['list.example'])],
    );
    final providers = c['rule-providers'] as Map;
    expect(providers['keq-list-keq-srv-0'], {
      'type': 'inline',
      'behavior': 'domain',
      'payload': ['+.list.example'],
    });
    expect(_rules(c), contains('RULE-SET,keq-list-keq-srv-0,keq-srv-0'));
  });

  test('без маршрутов на другие серверы конфиг прежний', () {
    expect(
      MihomoConfigGen.generate(_active, _settings, socksPort: 2080),
      MihomoConfigGen.generate(
        _active,
        _settings,
        socksPort: 2080,
        routeServers: const [],
      ),
    );
  });

  group('готовый YAML сервером маршрута', () {
    const toWarp = RouteServerOutbound(
      tag: 'keq-srv-0',
      serverId: 'warp',
      config: _warpYaml,
      address: 'warp.example',
      entries: 'youtube.com',
    );

    List<Map<String, dynamic>> groups(Map<String, dynamic> c) =>
        (c['proxy-groups'] as List).cast<Map<String, dynamic>>();

    test('группа автора под тегом маршрута, узлы под нашими именами', () {
      final c = MihomoConfigGen.build(
        _active,
        _settings,
        socksPort: 2080,
        routeServers: const [toWarp],
      );
      expect(_proxies(c).map((p) => p['name']), [
        MihomoConfigGen.proxyName,
        'keq-srv-0-1',
        'keq-srv-0-2',
        'keq-srv-0-3',
      ]);
      expect(_proxies(c)[1]['type'], 'wireguard',
          reason: 'якорь раскрыт до того, как узел ушёл в сессию');
      expect(_proxies(c)[3]['dialer-proxy'], 'keq-srv-0-1');
      expect(groups(c).single, {
        'name': 'keq-srv-0',
        'type': 'select',
        'proxies': ['keq-srv-0-1', 'keq-srv-0-2', 'keq-srv-0-3', 'DIRECT'],
      });
      expect(_rules(c), contains('DOMAIN-SUFFIX,youtube.com,keq-srv-0'));
      expect(_rules(c), isNot(contains('MATCH,Cloudflare')));
      expect(_proxies(c).map((p) => p['name']), isNot(contains('Unused')));
    });

    test('ко всем его серверам — напрямую', () {
      final rules = _rules(MihomoConfigGen.build(
        _active,
        _settings,
        socksPort: 2080,
        routeServers: const [toWarp],
      ));
      expect(rules, contains('DOMAIN,warp.example,DIRECT'));
      expect(rules, contains('DOMAIN,relay.example,DIRECT'));
      expect(rules.where((r) => r == 'DOMAIN,warp.example,DIRECT'), hasLength(1));
    });

    test('узел только для dialer-proxy — звено цепочки, счётчик его не задвоит',
        () {
      const yaml = '''
proxies:
  - {name: Entry, type: trojan, server: entry.example, port: 443, password: pw}
  - {name: Exit, type: trojan, server: exit.example, port: 443, password: pw,
     dialer-proxy: Entry}
proxy-groups:
  - {name: Proxy, type: select, proxies: [Exit]}
''';
      final c = MihomoConfigGen.build(
        _active,
        _settings,
        socksPort: 2080,
        routeServers: const [
          RouteServerOutbound(
            tag: 'keq-srv-0',
            serverId: 'chain',
            config: yaml,
            address: 'exit.example',
            entries: 'youtube.com',
          ),
        ],
      );
      final byServer = {for (final p in _proxies(c)) p['server']: p};
      final entry = byServer['entry.example']!['name'] as String;
      expect(MihomoConfigGen.isChainHop(entry), isTrue, reason: entry);
      expect(byServer['exit.example']!['name'], 'keq-srv-0-1');
      expect(byServer['exit.example']!['dialer-proxy'], entry);
      expect(channelOfChains([entry]), TrafficChannel.unknown);
    });

    test('под готовым YAML с теми же именами — без дублей, группы автора целы',
        () {
      final c = MihomoConfigGen.build(
        _warpYaml,
        _settings,
        socksPort: 2080,
        routeServers: const [toWarp],
      );
      final names = [
        ..._proxies(c).map((p) => p['name']),
        ...groups(c).map((g) => g['name']),
      ];
      expect(names.toSet(), hasLength(names.length), reason: '$names');
      expect(groups(c).map((g) => g['name']), ['Cloudflare', 'keq-srv-0']);
      expect(_rules(c).last, 'MATCH,Cloudflare');
    });
  });

  test('готовый clash-конфиг: выход добавлен к выходам автора', () {
    final c = MihomoConfigGen.build(
      _clashYaml,
      _settings,
      socksPort: 2080,
      routeServers: const [_toDe],
    );
    expect(_proxies(c).map((p) => p['name']), ['NL', 'keq-srv-0']);
    final rules = _rules(c);
    expect(rules, contains('DOMAIN-SUFFIX,youtube.com,keq-srv-0'));
    expect(rules, contains('DOMAIN,de.example,DIRECT'));
    expect(rules.last, 'MATCH,Proxy');
  });
}
