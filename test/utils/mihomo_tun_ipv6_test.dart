import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/tun_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/utils/desktop_tun.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

// выбор IPv6 в TUN у mihomo: закрыть, пустить через сервер или мимо.
// TCP закрывает патч ядра по ключу, правило перед MATCH ловит остальное, как tun-ipv6 у xray
const _link =
    'vless://00000000-0000-4000-8000-000000000000@198.51.100.41:443'
    '?type=tcp&security=none#pc';

const _clash = '''
mode: rule
proxies:
  - name: "NL"
    type: trojan
    server: 198.51.100.23
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

MihomoTunOptions _pc(String? ipv6) => MihomoTunOptions(
  device: kTunInterfaceName,
  stack: TunSettings.stackGvisor,
  mtu: 9000,
  ipv6: ipv6,
);

Map<String, dynamic> _build(
  MihomoTunOptions tun, {
  String strategy = 'UseIPv4',
  String input = _link,
  bool ignoreProviderRules = false,
}) {
  Socks5Credentials().init('u', 'p');
  return MihomoConfigGen.build(
    input,
    AppSettings(
      xrayCore: XrayCoreSettings(dnsQueryStrategy: strategy),
      ignoreProviderRules: ignoreProviderRules,
    ),
    socksPort: 2080,
    tun: tun,
  );
}

List<String> _rules(Map<String, dynamic> config) =>
    (config['rules'] as List).cast<String>();

Map<String, dynamic> _tun(Map<String, dynamic> config) =>
    config['tun'] as Map<String, dynamic>;

void main() {
  group('закрыть', () {
    test('TUN берёт IPv6, AAAA по-прежнему режет DNS, TCP сбрасывает ядро', () {
      final config = _build(_pc(TunSettings.ipv6Close));
      // глобальный ipv6 даёт адаптеру адрес IPv6 (config.go parseIPV6), иначе IPv6 шёл бы мимо TUN
      expect(config['ipv6'], isTrue);
      expect((config['dns'] as Map)['ipv6'], isFalse);
      expect(config[MihomoConfigGen.closeTunIpv6Key], isTrue);
      expect(_tun(config).containsKey('inet6-address'), isFalse);

      final rules = _rules(config);
      expect(rules.last, startsWith('MATCH,'));
      expect(rules[rules.length - 2], MihomoConfigGen.closedTunIpv6Rule);
    });

    test('ключ и правило доезжают и до готового конфига Clash', () {
      final kept = _build(_pc(TunSettings.ipv6Close), input: _clash);
      expect(kept[MihomoConfigGen.closeTunIpv6Key], isTrue);
      expect(kept['ipv6'], isTrue);

      final own = _build(
        _pc(TunSettings.ipv6Close),
        input: _clash,
        ignoreProviderRules: true,
      );
      final rules = _rules(own);
      expect(rules.last, startsWith('MATCH,'));
      expect(rules[rules.length - 2], MihomoConfigGen.closedTunIpv6Rule);
    });
  });

  group('через VPN', () {
    test('адрес IPv6 у TUN явный, ничего не закрыто', () {
      // стратегию UseIP ставит connect: без AAAA через сервер IPv6 никто бы не выбрал
      final config = _build(_pc(TunSettings.ipv6Vpn), strategy: 'UseIP');
      expect(config['ipv6'], isTrue);
      expect((config['dns'] as Map)['ipv6'], isTrue);
      expect(_tun(config)['inet6-address'], [kTunInterfaceIpv6Prefix]);
      expect(config.containsKey(MihomoConfigGen.closeTunIpv6Key), isFalse);
      expect(
        _rules(config),
        isNot(contains(MihomoConfigGen.closedTunIpv6Rule)),
      );
    });

    test('на Android тот же адрес читает VpnService', () {
      final config = _build(
        const MihomoTunOptions(
          fromFileDescriptor: true,
          stack: TunSettings.stackGvisor,
          autoRoute: false,
          ipv6: TunSettings.ipv6Vpn,
        ),
        strategy: 'UseIP',
      );
      expect(_tun(config)['inet6-address'], [kTunInterfaceIpv6Prefix]);
    });
  });

  group('мимо VPN', () {
    test(
      'пустой адрес IPv6 сильнее умолчания ядра даже со стратегией UseIP',
      () {
        final config = _build(_pc(TunSettings.ipv6Bypass), strategy: 'UseIP');
        expect(config['ipv6'], isTrue);
        expect(_tun(config)['inet6-address'], isEmpty);
        expect(config.containsKey(MihomoConfigGen.closeTunIpv6Key), isFalse);
        expect(
          _rules(config),
          isNot(contains(MihomoConfigGen.closedTunIpv6Rule)),
        );
      },
    );

    test('со стратегией UseIPv4 глобальный ipv6 выключен, как раньше', () {
      final config = _build(_pc(TunSettings.ipv6Bypass));
      expect(config['ipv6'], isFalse);
    });
  });

  test(
    'без режима в TUN всё как до выбора: семейство решает стратегия DNS',
    () {
      for (final strategy in ['UseIPv4', 'UseIP']) {
        final config = _build(_pc(null), strategy: strategy);
        expect(config['ipv6'], strategy == 'UseIP');
        expect(_tun(config).containsKey('inet6-address'), isFalse);
        expect(config.containsKey(MihomoConfigGen.closeTunIpv6Key), isFalse);
      }
    },
  );

  test(
    'на macOS TUN включает dns-mode hijack только при своей маршрутизации',
    () {
      // без dns-mode sing-tun на Darwin оставляет DNSModeDisabled и не пишет резолвер в SCDynamicStore
      final macos = _build(
        const MihomoTunOptions(
          device: kMacosTunInterfaceName,
          stack: TunSettings.stackGvisor,
          mtu: 9000,
          macos: true,
        ),
      );
      expect(_tun(macos)['dns-mode'], 'hijack');

      final manual = _build(
        const MihomoTunOptions(
          device: kMacosTunInterfaceName,
          stack: TunSettings.stackGvisor,
          mtu: 9000,
          macos: true,
          autoRoute: false,
        ),
      );
      expect(_tun(manual).containsKey('dns-mode'), isFalse);
      expect(_tun(_build(_pc(null))).containsKey('dns-mode'), isFalse);
    },
  );
}
