import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/route_servers.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// «Другой сервер» маршрута на xray: отдельный аутбаунд и правила на него
/// между «напрямую» и «через VPN».
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
  entries: 'youtube.com, geoip:de, 9.9.9.9',
);

const _xrayCustom = '''
{
  "outbounds": [
    {
      "tag": "my-proxy",
      "protocol": "vless",
      "settings": {"vnext": [{"address": "nl.example", "port": 443,
        "users": [{"id": "00000000-0000-4000-8000-000000000000", "encryption": "none"}]}]}
    },
    {"tag": "direct", "protocol": "freedom"}
  ],
  "routing": {"rules": []}
}
''';

// как у генератора WARP-профилей: wireguard ходит через freedom с шумом
const _warpJson = '''
{
  "dns": {"servers": ["9.9.9.9"]},
  "outbounds": [
    {
      "tag": "warp",
      "protocol": "wireguard",
      "settings": {
        "secretKey": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEA=",
        "address": ["172.16.0.2/32"],
        "peers": [{"endpoint": "warp.example:4500",
          "publicKey": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIA="}]
      },
      "streamSettings": {"sockopt": {"dialerProxy": "noise-out"}}
    },
    {
      "tag": "noise-out",
      "protocol": "freedom",
      "settings": {"noises": [{"type": "rand", "packet": "10-20", "delay": "1-2"}]}
    },
    {"tag": "unused", "protocol": "blackhole"}
  ],
  "routing": {"rules": [
    {"type": "field", "port": "53", "outboundTag": "noise-out"},
    {"type": "field", "network": "tcp,udp", "outboundTag": "warp"}
  ]}
}
''';

Map<String, dynamic> _build(
  String server, {
  AppSettings settings = _settings,
  List<RouteServerOutbound> routes = const [_toDe],
}) =>
    jsonDecode(ConfigGeneratorV2.generateConfig(
      server,
      settings,
      routeServers: routes,
    )) as Map<String, dynamic>;

List<Map<String, dynamic>> _rules(Map<String, dynamic> c) => [
      for (final r in (c['routing'] as Map)['rules'] as List)
        (r as Map).cast<String, dynamic>(),
    ];

List<Map<String, dynamic>> _outbounds(Map<String, dynamic> c) => [
      for (final o in c['outbounds'] as List) (o as Map).cast<String, dynamic>(),
    ];

int _at(List<Map<String, dynamic>> rules, String tag) =>
    rules.indexWhere((r) => r['ruleTag'] == tag);

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  test('сервер маршрута — отдельный аутбаунд после основного', () {
    final outbounds = _outbounds(_build(_active));
    expect(outbounds.first['tag'], 'proxy',
        reason: 'первый аутбаунд у xray основной');
    final de = outbounds.firstWhere((o) => o['tag'] == 'keq-srv-0');
    expect(de['protocol'], 'trojan');
    expect((de['settings'] as Map)['address'], 'de.example');
  });

  test('правила на него — после «напрямую», раньше «через VPN»', () {
    final rules = _rules(_build(_active));
    final domains = _at(rules, 'keq-srv-0-domains');
    expect(domains, isNonNegative, reason: '$rules');
    expect(rules[domains]['domain'], ['domain:youtube.com']);
    expect(rules[domains]['outboundTag'], 'keq-srv-0');
    expect(rules[_at(rules, 'keq-srv-0-geoip')]['ip'], ['geoip:de']);
    expect(rules[_at(rules, 'keq-srv-0-ips')]['ip'], ['9.9.9.9']);
    expect(_at(rules, 'block-domains'), lessThan(domains));
    expect(_at(rules, 'direct-private'), lessThan(domains));
    expect(domains, lessThan(_at(rules, 'proxy-domains')));
  });

  test('к самому серверу маршрута — напрямую, его домен резолвится без туннеля',
      () {
    final c = _build(_active);
    final rules = _rules(c);
    final direct = rules.firstWhere((r) => r['ruleTag'] == 'route-server-0');
    expect(direct['domain'], ['full:de.example']);
    expect(direct['outboundTag'], 'direct');
    expect(jsonEncode(c['dns']), contains('full:de.example'));
  });

  test('скачанные списки — в его доменные правила', () {
    final rules = _rules(_build(
      _active,
      routes: [_toDe.copyWith(listDomains: ['list.example'])],
    ));
    expect(
      rules[_at(rules, 'keq-srv-0-domains')]['domain'],
      ['domain:youtube.com', 'domain:list.example'],
    );
  });

  test('фрагментация доходит и до сервера маршрута', () {
    final c = _build(
      _active,
      settings: _settings.copyWith(
        xrayCore: const XrayCoreSettings(fragmentEnabled: true),
      ),
    );
    final outbounds = _outbounds(c);
    String? dialer(String tag) =>
        ((outbounds.firstWhere((o) => o['tag'] == tag)['streamSettings']
                as Map?)?['sockopt'] as Map?)?['dialerProxy'] as String?;
    expect(dialer('proxy'), 'fragment');
    expect(dialer('keq-srv-0'), 'fragment');
    expect(outbounds.where((o) => o['tag'] == 'fragment'), hasLength(1));
  });

  test('без маршрутов на другие серверы конфиг прежний', () {
    expect(
      ConfigGeneratorV2.generateConfig(_active, _settings, routeServers: const []),
      ConfigGeneratorV2.generateConfig(_active, _settings),
    );
  });

  group('готовый JSON сервером маршрута', () {
    const toWarp = RouteServerOutbound(
      tag: 'keq-srv-0',
      serverId: 'warp',
      config: _warpJson,
      address: 'warp.example',
      entries: 'youtube.com',
    );

    test('главный выход и его dialerProxy — под нашими тегами', () {
      final outbounds = _outbounds(_build(_active, routes: const [toWarp]));
      final wg = outbounds.firstWhere((o) => o['tag'] == 'keq-srv-0');
      expect(wg['protocol'], 'wireguard');
      expect(
        ((wg['streamSettings'] as Map)['sockopt'] as Map)['dialerProxy'],
        'keq-srv-0-1',
      );
      final noise = outbounds.firstWhere((o) => o['tag'] == 'keq-srv-0-1');
      expect(noise['protocol'], 'freedom');
      expect((noise['settings'] as Map)['noises'], isNotEmpty);
      expect(outbounds.map((o) => o['tag']), isNot(contains('noise-out')));
      expect(outbounds.map((o) => o['tag']), isNot(contains('unused')));
    });

    test('правила и DNS автора в сессию не попадают', () {
      final c = _build(_active, routes: const [toWarp]);
      final rules = _rules(c);
      expect(rules.where((r) => r['outboundTag'] == 'keq-srv-0-1'), isEmpty);
      expect(
        rules[_at(rules, 'keq-srv-0-domains')]['outboundTag'],
        'keq-srv-0',
      );
      expect(jsonEncode(c['dns']), isNot(contains('9.9.9.9')));
    });

    test('под готовым конфигом с теми же тегами — без дублей', () {
      final c = _build(_warpJson, routes: const [toWarp]);
      final tags = _outbounds(c).map((o) => o['tag']).toList();
      expect(tags.where((t) => t == 'noise-out'), hasLength(1));
      expect(tags.toSet(), hasLength(tags.length), reason: '$tags');
      expect(tags, containsAll(['keq-srv-0', 'keq-srv-0-1']));
    });

    test('поле, которое ядро снесло, вычищено и из выхода маршрута', () {
      final c = _build(
        _active,
        routes: [
          RouteServerOutbound(
            tag: 'keq-srv-0',
            serverId: 'tls',
            config: _xrayCustom.replaceFirst(
              '"protocol": "vless",',
              '"protocol": "vless", "streamSettings": {"security": "tls", '
                  '"tlsSettings": {"allowInsecure": true}},',
            ),
            address: 'nl.example',
            entries: 'youtube.com',
          ),
        ],
      );
      expect(jsonEncode(c), isNot(contains('allowInsecure')));
    });
  });

  test('готовый конфиг: аутбаунд и правила добавлены к авторским', () {
    final c = _build(_xrayCustom);
    final outbounds = _outbounds(c);
    expect(outbounds.first['tag'], 'my-proxy');
    expect(outbounds.map((o) => o['tag']), contains('keq-srv-0'));
    final rules = _rules(c);
    final at = rules.indexWhere(
      (r) => (r['domain'] as List?)?.contains('domain:youtube.com') ?? false,
    );
    expect(at, isNonNegative);
    expect(rules[at]['outboundTag'], 'keq-srv-0');
  });
}
