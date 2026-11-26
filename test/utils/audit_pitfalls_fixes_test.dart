import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/traffic_route.dart';
import 'package:keqdroid/models/tun_settings.dart';
import 'package:keqdroid/utils/app_routes.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/custom_clash_config.dart';
import 'package:keqdroid/utils/geo_asset_index.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/proxy_chain.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  group('Xray Hysteria2 udphop', () {
    const hy2Link =
        'hysteria2://password@198.51.100.16:443'
        '?sni=hy2.example&obfs=salamander&obfs-password=obfspass'
        '&mport=20000-20050&hop-interval=12#hy2';

    test(
      'mport строит маску udphop в конце finalmask.udp без мёртвого quicParams.udpHop',
      () {
        final settings = const AppSettings().copyWith(
          xrayCore: const AppSettings().xrayCore.copyWith(noiseEnabled: true),
        );
        final cfg =
            jsonDecode(ConfigGeneratorV2.generateConfig(hy2Link, settings))
                as Map<String, dynamic>;
        final proxy = (cfg['outbounds'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere((o) => o['tag'] == 'proxy');
        final finalmask =
            (proxy['streamSettings'] as Map)['finalmask']
                as Map<String, dynamic>;
        expect(
          (finalmask['quicParams'] as Map?)?.containsKey('udpHop') ?? false,
          isFalse,
        );
        final udp = (finalmask['udp'] as List).cast<Map<String, dynamic>>();
        expect([for (final m in udp) m['type']], [
          'salamander',
          'noise',
          'udphop',
        ]);
        expect(udp.last['settings'], {
          'mode': 'intervallocal,intervalremote',
          'remotePorts': '20000-20050',
          'interval': '12',
        });
      },
    );

    test('за dialerProxy маска udphop снимается с выходного узла', () {
      final chain = const ProxyChainConfig(
        name: 'chain',
        hops: [
          ProxyChainHop(
            name: 'entry',
            config:
                'vless://00000000-0000-4000-8000-000000000000@198.51.100.1:443?type=tcp&security=none#entry',
          ),
          ProxyChainHop(name: 'exit', config: hy2Link),
        ],
      ).encode();
      final cfg =
          jsonDecode(
                ConfigGeneratorV2.generateConfig(chain, const AppSettings()),
              )
              as Map<String, dynamic>;
      final proxy = (cfg['outbounds'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((o) => o['tag'] == 'proxy');
      final finalmask =
          (proxy['streamSettings'] as Map)['finalmask']
              as Map<String, dynamic>?;
      expect(
        (finalmask?['quicParams'] as Map?)?.containsKey('udpHop') ?? false,
        isFalse,
      );
      final udp =
          (finalmask?['udp'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
      expect([for (final m in udp) m['type']], ['salamander']);
    });
  });

  group('IPv6 через туннель против внешнего дозвона', () {
    const vlessDomain =
        'vless://00000000-0000-4000-8000-000000000000@vpn.example.com:443'
        '?type=tcp&security=none#t';

    test(
      'xray включает UseIP только в DNS туннеля, а дозвон до сервера держит UseIPv4',
      () {
        final cfg =
            jsonDecode(
                  ConfigGeneratorV2.generateConfig(
                    vlessDomain,
                    const AppSettings(),
                    nativeTunInbound: true,
                    nativeTunIpv6: true,
                  ),
                )
                as Map<String, dynamic>;
        expect((cfg['dns'] as Map)['queryStrategy'], 'UseIP');
        final proxy = (cfg['outbounds'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere((o) => o['tag'] == 'proxy');
        expect(
          ((proxy['streamSettings'] as Map)['sockopt'] as Map)['domainStrategy'],
          'UseIPv4',
        );
      },
    );

    test('mihomo включает ipv6 в DNS при передаче IPv6 через TUN', () {
      final cfg = MihomoConfigGen.build(
        vlessDomain,
        const AppSettings(),
        socksPort: 2080,
        tun: const MihomoTunOptions(
          stack: TunSettings.stackGvisor,
          fromFileDescriptor: true,
          autoRoute: false,
          ipv6: TunSettings.ipv6Vpn,
        ),
      );
      expect((cfg['dns'] as Map)['ipv6'], isTrue);
    });
  });

  group('Готовый Xray JSON', () {
    test(
      'при IPIfNonMatch целевой узел встаёт первым, даже если freedom в JSON шёл раньше',
      () {
        final raw = jsonEncode({
          'outbounds': [
            {
              'tag': 'direct-first',
              'protocol': 'freedom',
              'settings': <String, dynamic>{},
            },
            {
              'tag': 'vless-main',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': '198.51.100.10',
                    'port': 443,
                    'users': [
                      {
                        'id': '00000000-0000-4000-8000-000000000000',
                        'encryption': 'none',
                      },
                    ],
                  },
                ],
              },
            },
          ],
          'routing': {
            'domainStrategy': 'IPIfNonMatch',
            'rules': <Map<String, dynamic>>[],
          },
        });
        final cfg =
            jsonDecode(
                  ConfigGeneratorV2.generateConfig(raw, const AppSettings()),
                )
                as Map<String, dynamic>;
        final outbounds = (cfg['outbounds'] as List)
            .cast<Map<String, dynamic>>();
        expect(outbounds.first['tag'], 'vless-main');
      },
    );

      test('вырезает dns.script, dns.useSystemHosts и script из finalmask', () {
        final raw = jsonEncode({
          'dns': {
            'script': 'os.execute("calc")',
            'useSystemHosts': true,
            'servers': ['1.1.1.1'],
          },
          'outbounds': [
            {
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': 'vpn.example.com',
                    'port': 443,
                    'users': [
                      {
                        'id': '00000000-0000-4000-8000-000000000000',
                        'encryption': 'none',
                      },
                    ],
                  },
                ],
              },
              'streamSettings': {
                'network': 'kcp',
                'finalmask': {
                  'udp': [
                    {
                      'type': 'noise',
                      'script': 'os.execute("calc")',
                      'settings': {
                        'script': 'os.execute("calc")',
                        'reset': 5,
                      },
                    },
                  ],
                },
              },
            },
          ],
          'routing': {
            'rules': [
              {
                'type': 'field',
                'ruleTag': 'provider-all',
                'network': 'tcp,udp',
                'outboundTag': 'proxy',
              },
            ],
          },
        });
        final cfg =
            jsonDecode(
                  ConfigGeneratorV2.generateConfig(raw, const AppSettings()),
                )
                as Map<String, dynamic>;
        final dns = cfg['dns'] as Map<String, dynamic>;
        expect(dns.containsKey('script'), isFalse);
        expect(dns.containsKey('useSystemHosts'), isFalse);
        final outbounds = (cfg['outbounds'] as List)
            .cast<Map<String, dynamic>>();
        expect(outbounds.first['tag'], 'proxy');
        final mask =
            (((outbounds.first['streamSettings'] as Map)['finalmask']
                        as Map)['udp']
                    as List)
                .single
                as Map<String, dynamic>;
        expect(mask.containsKey('script'), isFalse);
        expect((mask['settings'] as Map).containsKey('script'), isFalse);
        final ruleTags = [
          for (final r in ((cfg['routing'] as Map)['rules'] as List))
            (r as Map)['ruleTag'],
        ];
        expect(
          ruleTags.indexOf('dns-bootstrap'),
          lessThan(ruleTags.indexOf('provider-all')),
        );
      });
  });

  group('Mihomo Hysteria2, Vision и DNS', () {
    test('hysteria2 переносит ech, peer, obfs_password, upmbps и vcn', () {
      const link =
          'hysteria2://pwd@198.51.100.16:443'
          '?peer=hy2.example&obfs=salamander&obfs_password=secret'
          '&upmbps=50&downmbps=200&ech=QUFCQg==&vcn=cert.example#hy2';
      final proxy = MihomoConfigGen.buildProxies(link).single;
      expect(proxy['sni'], 'hy2.example');
      expect(proxy['obfs-password'], 'secret');
      expect(proxy['up'], '50');
      expect(proxy['down'], '200');
      expect(proxy['ech-opts'], {'enable': true, 'config': 'QUFCQg=='});
      expect(proxy['name-cert-verify'], 'cert.example');
    });

    test('VLESS xtls-rprx-vision режет UDP/443 при глобальном прокси', () {
      const vision =
          'vless://00000000-0000-4000-8000-000000000000@198.51.100.10:443'
          '?type=tcp&security=tls&flow=xtls-rprx-vision#v';
      final cfg = MihomoConfigGen.build(
        vision,
        const AppSettings(),
        socksPort: 2080,
        appRoutes: const [
          RouteAppRules(
            tag: 'keq-route-placed',
            apps: [],
            target: RouteTarget.vpn,
            entries: 'youtube.com',
            ownOrder: true,
          ),
        ],
      );
      final rules = (cfg['rules'] as List).cast<String>();
      expect(rules, contains('AND,((NETWORK,udp),(DST-PORT,443)),REJECT'));
      final placedQuicAt = rules.indexOf(
        'AND,((DOMAIN-SUFFIX,youtube.com),(NETWORK,udp),(DST-PORT,443)),REJECT',
      );
      final placedRuleAt = rules.indexOf(
        'DOMAIN-SUFFIX,youtube.com,${MihomoConfigGen.proxyName}',
      );
      expect(placedQuicAt, greaterThanOrEqualTo(0));
      expect(placedQuicAt, lessThan(placedRuleAt));

      const visionUdp443 =
          'vless://00000000-0000-4000-8000-000000000000@198.51.100.10:443'
          '?type=tcp&security=tls&flow=xtls-rprx-vision-udp443#v';
      final allowed = MihomoConfigGen.build(
        visionUdp443,
        const AppSettings(),
        socksPort: 2080,
      );
      expect(
        (allowed['rules'] as List).cast<String>(),
        isNot(contains('AND,((NETWORK,udp),(DST-PORT,443)),REJECT')),
      );
    });

    test(
      'bootstrapNameservers не откатывается на открытый UDP-53 и не берёт dhcp',
      () {
        final dohHostOnly = const AppSettings().xrayCore.copyWith(
          dnsUseCustom: true,
          dnsServers: 'https://dns.google/dns-query',
        );
        expect(MihomoConfigGen.bootstrapNameservers(dohHostOnly), [
          'https://1.1.1.1/dns-query',
          'https://8.8.8.8/dns-query',
        ]);

        final dhcpLocal = const AppSettings().xrayCore.copyWith(
          dnsUseCustom: true,
          dnsServers: 'dhcp+local://eth0',
        );
        expect(MihomoConfigGen.dnsServers(dhcpLocal), ['dhcp://eth0']);
        expect(
          MihomoConfigGen.bootstrapNameservers(dhcpLocal),
          isNot(contains(startsWith('dhcp://'))),
        );
      },
    );

    test('готовый Clash вычищает неизвестные коды geo внутри секции dns', () {
      final clash = CustomClashConfig.tryParse(
        jsonEncode({
          'proxies': [
            {
              'name': 'p',
              'type': 'socks5',
              'server': '198.51.100.1',
              'port': 1080,
            },
          ],
          'dns': {
            'enable': true,
            'nameserver': ['https://1.1.1.1/dns-query'],
            'fallback': ['https://8.8.8.8/dns-query'],
            'nameserver-policy': {
              'geosite:missing-site': ['192.168.1.1'],
              'geosite:private': ['system'],
            },
            'fake-ip-filter-mode': 'rule',
            'fake-ip-filter': [
              'GEOSITE,missing-fake',
              'DOMAIN-SUFFIX,lan',
            ],
            'fallback-filter': {
              'geoip-code': 'ZZ',
              'geosite': ['missing-fb', 'private'],
            },
          },
          'rules': ['MATCH,p'],
        }),
      )!;
      const index = GeoAssetIndex(
        geositeCodes: {'private'},
        geoipCodes: {'private'},
      );
      final cleaned = clash.withKnownGeo(index);
      final dns = cleaned.config.map['dns'] as Map<String, dynamic>;
      expect(
        (dns['nameserver-policy'] as Map).keys,
        ['geosite:private'],
      );
      expect(dns['fake-ip-filter'], ['DOMAIN-SUFFIX,lan']);
      final fb = dns['fallback-filter'] as Map<String, dynamic>;
      expect(fb['geoip'], isFalse);
      expect(fb['geosite'], ['private']);
      expect(
        cleaned.dropped,
        containsAll([
          'geosite:missing-site',
          'geosite:missing-fake',
          'geoip:zz',
          'geosite:missing-fb',
        ]),
      );
    });
  });

  test('живые ядра принимают обновлённые конфиги без ошибок схемы', () async {
    final releaseDir = Directory('build/windows/x64/runner/Release');
    final xrayBin = File('${releaseDir.path}/xray.exe');
    final mihomoBin = File('${releaseDir.path}/mihomo.exe');
    if (!xrayBin.existsSync() || !mihomoBin.existsSync()) return;

    final tmp = await Directory.systemTemp.createTemp('keq_pitfall_live_');
    addTearDown(() => tmp.delete(recursive: true));

    final xrayCfg = File('${tmp.path}/xray.json')
      ..writeAsStringSync(
        ConfigGeneratorV2.generateConfig(
          'hysteria2://password@198.51.100.16:443'
          '?sni=hy2.example&obfs=salamander&obfs-password=obfspass'
          '&mport=20000-20050&hop-interval=12#hy2',
          const AppSettings(fakeIp: true).copyWith(
            xrayCore: const AppSettings().xrayCore.copyWith(noiseEnabled: true),
          ),
          nativeTunInbound: true,
          nativeTunIpv6: true,
        ),
      );
    final xrayRes = await Process.run(
      xrayBin.path,
      ['run', '-test', '-c', xrayCfg.path],
      environment: {'XRAY_LOCATION_ASSET': releaseDir.absolute.path},
    );
    expect(
      xrayRes.exitCode,
      0,
      reason: '${xrayRes.stdout}\n${xrayRes.stderr}',
    );

    final mihomoCfg = File('${tmp.path}/mihomo.yaml')
      ..writeAsStringSync(
        jsonEncode(
          MihomoConfigGen.build(
            'vless://00000000-0000-4000-8000-000000000000@198.51.100.10:443'
            '?type=tcp&security=tls&flow=xtls-rprx-vision#v',
            const AppSettings(),
            socksPort: 2080,
            appRoutes: const [
              RouteAppRules(
                tag: 'keq-route-placed',
                apps: [],
                target: RouteTarget.vpn,
                entries: 'youtube.com\n198.51.100.0/24',
                ownOrder: true,
              ),
              RouteAppRules(
                tag: 'keq-route-proto',
                apps: [],
                target: RouteTarget.vpn,
                entries: 'example.org',
                ports: [(443, 443)],
                ownOrder: true,
              ),
            ],
          ),
        ),
      );
    final mihomoRes = await Process.run(mihomoBin.path, [
      '-t',
      '-d',
      releaseDir.absolute.path,
      '-f',
      mihomoCfg.path,
    ]);
    expect(
      mihomoRes.exitCode,
      0,
      reason: '${mihomoRes.stdout}\n${mihomoRes.stderr}',
    );
  });
}
