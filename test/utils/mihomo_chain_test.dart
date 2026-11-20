import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/tunnel/vpn_backend.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/multi_ping_config.dart';
import 'package:keqdroid/utils/proxy_chain.dart';
import 'package:keqdroid/utils/route_servers.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

// цепочка на mihomo: узлы связаны dialer-proxy (adapter/outbound/base.go), выход остаётся proxy
const _fi =
    'vless://00000000-0000-4000-8000-000000000000@fi.example:443'
    '?type=tcp&security=tls&sni=fi.example#FI';
const _pl = 'trojan://pw@203.0.113.7:443?security=tls&sni=pl.example#PL';
const _tuic =
    'tuic://00000000-0000-4000-8000-000000000000:pw@tu.example:443'
    '?alpn=h3&congestion_control=bbr#TU';

String _chain(List<String> hops) => ProxyChainConfig(
  name: 'chain',
  hops: [for (final h in hops) ProxyChainHop(config: h)],
).encode();

List<Map<String, dynamic>> _proxies(Map<String, dynamic> c) =>
    (c['proxies'] as List).cast<Map<String, dynamic>>();

List<String> _rules(Map<String, dynamic> c) =>
    (c['rules'] as List).cast<String>();

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  group('основной сервер', () {
    test('узлы по порядку, каждый следующий через предыдущий', () {
      final c = MihomoConfigGen.build(
        _chain([_fi, _pl, _tuic]),
        const AppSettings(),
        socksPort: 2080,
      );
      final proxies = _proxies(c);
      expect(proxies.map((p) => p['name']), [
        'keq-chain-0',
        'keq-chain-1',
        'proxy',
      ]);
      expect(proxies.map((p) => p['type']), ['vless', 'trojan', 'tuic']);
      expect(proxies.map((p) => p['dialer-proxy']), [
        null,
        'keq-chain-0',
        'keq-chain-1',
      ]);
      expect(_rules(c).last, 'MATCH,proxy');
    });

    test('адреса всех узлов мимо туннеля', () {
      final rules = _rules(
        MihomoConfigGen.build(
          _chain([_fi, _pl, _tuic]),
          const AppSettings(),
          socksPort: 2080,
        ),
      );
      expect(rules, contains('DOMAIN,fi.example,DIRECT'));
      expect(rules, contains('IP-CIDR,203.0.113.7/32,DIRECT,no-resolve'));
      expect(rules, contains('DOMAIN,tu.example,DIRECT'));
    });

    test('обычный сервер собирается как раньше, без dialer-proxy', () {
      final proxies = _proxies(
        MihomoConfigGen.build(_fi, const AppSettings(), socksPort: 2080),
      );
      expect(proxies, hasLength(1));
      expect(proxies.single['name'], 'proxy');
      expect(proxies.single.containsKey('dialer-proxy'), isFalse);
    });
  });

  test('пинг меряет цепочку целиком', () {
    final c =
        jsonDecode(
              MihomoConfigGen.generatePingConfig(
                _chain([_fi, _pl]),
                const AppSettings(),
                socksPort: 3001,
              ),
            )
            as Map<String, dynamic>;
    expect(_proxies(c).map((p) => p['name']), ['keq-chain-0', 'proxy']);
    expect(_proxies(c).last['dialer-proxy'], 'keq-chain-0');
    expect(c['rules'], ['MATCH,proxy']);
  });

  test('склейка проб переименовывает и dialer-proxy', () {
    String probe(String exit) => MihomoConfigGen.generatePingConfig(
      _chain([_fi, exit]),
      const AppSettings(),
      socksPort: 3001,
    );
    final merged =
        jsonDecode(
              MultiPingConfig.mergeMihomo([
                (id: 'a', configJson: probe(_pl), port: 3001),
                (id: 'b', configJson: probe(_tuic), port: 3002),
              ], httpListeners: false),
            )
            as Map<String, dynamic>;
    final proxies = _proxies(merged);
    final byName = {for (final p in proxies) p['name']: p};
    expect(byName['proxy-0']!['dialer-proxy'], 'keq-chain-0-0');
    expect(byName['proxy-1']!['dialer-proxy'], 'keq-chain-0-1');
    expect(byName.keys, containsAll(['keq-chain-0-0', 'keq-chain-0-1']));
  });

  group('цепочка как сервер маршрута', () {
    final chain = _chain([_pl, _tuic]);
    final route = RouteServerOutbound(
      tag: 'keq-srv-0',
      serverId: 'c',
      config: chain,
      address: '203.0.113.7',
      entries: 'youtube.com',
    );

    test('только у mihomo', () {
      expect(routeServerSupported(chain, VpnBackend.mihomo), isTrue);
      expect(routeServerSupported(chain, VpnBackend.xray), isFalse);
    });

    test('звенья под своими именами, выход под тегом маршрута', () {
      final c = MihomoConfigGen.build(
        _fi,
        const AppSettings(),
        socksPort: 2080,
        routeServers: [route],
      );
      final proxies = _proxies(c);
      expect(proxies.map((p) => p['name']), [
        'proxy',
        'keq-chain-keq-srv-0-0',
        'keq-srv-0',
      ]);
      expect(proxies.last['dialer-proxy'], 'keq-chain-keq-srv-0-0');
      expect(_rules(c), contains('DOMAIN-SUFFIX,youtube.com,keq-srv-0'));
      expect(_rules(c), contains('DOMAIN,tu.example,DIRECT'));
    });
  });

  test('имя звена узнаётся по префиксу', () {
    expect(MihomoConfigGen.isChainHop('keq-chain-0'), isTrue);
    expect(MihomoConfigGen.isChainHop('keq-chain-keq-srv-0-1'), isTrue);
    expect(MihomoConfigGen.isChainHop('proxy'), isFalse);
    expect(MihomoConfigGen.isChainHop('keq-srv-0'), isFalse);
  });
}
