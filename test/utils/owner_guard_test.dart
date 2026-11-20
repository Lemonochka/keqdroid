import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/tunnel/app_routing_mode.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/desktop_tun.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/owner_guard.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

import '../helpers/mihomo_rules_sim.dart';
import '../helpers/xray_rules_sim.dart';

// Приложение вне VPN, привязавшее сокет к tun0: мост называет его маркером, и защита обрывает соединение
// раньше всего, что ответило бы через сервер. Выключенная защита конфиг не трогает
const _link =
    'vless://00000000-0000-4000-8000-000000000000@203.0.113.10:443'
    '?type=tcp&security=tls&sni=nl.example#NL';

const _settings = AppSettings(
  directRules: 'ru',
  proxyRules: 'telegram.org',
  blockedRules: 'doubleclick.net',
);

const _chrome = 'com.android.chrome';

const _custom = {
  'outbounds': [
    {
      'tag': 'proxy',
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {
            'address': '203.0.113.11',
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
    {'tag': 'direct', 'protocol': 'freedom'},
  ],
  'routing': {
    'rules': [
      {'type': 'field', 'port': '53', 'outboundTag': 'direct'},
      {'type': 'field', 'network': 'tcp,udp', 'outboundTag': 'proxy'},
    ],
  },
};

const _clash = '''
proxies:
  - name: "NL"
    type: trojan
    server: 203.0.113.12
    port: 443
    password: pw
proxy-groups:
  - name: "Proxy"
    type: select
    proxies: ["NL"]
rules:
  - DST-PORT,443,Proxy
  - MATCH,Proxy
''';

const _androidTun = MihomoTunOptions(
  fromFileDescriptor: true,
  stack: 'gvisor',
  autoRoute: false,
);

Map<String, dynamic> _xray(
  OwnerGuard guard, {
  String input = _link,
  bool tun = true,
  DesktopTunOptions? desktopTun,
}) {
  Socks5Credentials().init('u', 'p');
  return jsonDecode(
        ConfigGeneratorV2.generateConfig(
          input,
          _settings,
          nativeTunInbound: tun,
          desktopTun: desktopTun,
          ownerGuard: guard,
        ),
      )
      as Map<String, dynamic>;
}

Map<String, dynamic> _mihomo(
  OwnerGuard guard, {
  String input = _link,
  MihomoTunOptions? tun = _androidTun,
}) {
  Socks5Credentials().init('u', 'p');
  return MihomoConfigGen.build(
    input,
    _settings,
    socksPort: 2080,
    httpPort: 2081,
    tun: tun,
    ownerGuard: guard,
  );
}

String? _x(
  Map<String, dynamic> c, {
  String process = kOutsideVpnOwner,
  String inbound = 'tun-in',
  String host = '',
  String ip = '93.184.216.34',
  int port = 443,
  String network = 'tcp',
}) => simulateXray(
  c,
  XrayConn(
    inbound: inbound,
    process: process,
    host: host,
    ip: ip,
    port: port,
    network: network,
  ),
);

String _m(
  Map<String, dynamic> c, {
  String process = kOutsideVpnOwner,
  String inType = 'TUN',
  int port = 443,
}) => simulateMihomo(
  c,
  SimConn(process: process, ip: '93.184.216.34', inType: inType, port: port),
);

void main() {
  // переключателя нет: защита там, где сплит выводит приложения из VPN, на Android 10+ в режиме VPN
  test('когда защита включена', () {
    OwnerGuard on({
      bool android = true,
      bool tun = true,
      AppRoutingMode mode = AppRoutingMode.allExceptSelected,
      int? sdk = 37,
    }) => ownerGuardFor(
      android: android,
      tun: tun,
      routingMode: mode,
      sdkInt: sdk,
    );

    expect(on(), OwnerGuard.all);
    expect(on(mode: AppRoutingMode.onlySelected), OwnerGuard.all);
    expect(on(sdk: 29), OwnerGuard.all);
    expect(on(sdk: null), OwnerGuard.all);
    expect(on(mode: AppRoutingMode.allProxy), OwnerGuard.off);
    expect(on(sdk: 28), OwnerGuard.off);
    expect(on(tun: false), OwnerGuard.off);
    expect(on(android: false), OwnerGuard.off);
  });

  group('xray', () {
    test('выключенная защита: конфиг как без параметра', () {
      Socks5Credentials().init('u', 'p');
      for (final input in [_link, jsonEncode(_custom)]) {
        expect(
          ConfigGeneratorV2.generateConfig(
            input,
            _settings,
            nativeTunInbound: true,
            ownerGuard: OwnerGuard.off,
          ),
          ConfigGeneratorV2.generateConfig(
            input,
            _settings,
            nativeTunInbound: true,
          ),
        );
      }
    });

    test('правило первым, только для входа туннеля', () {
      final rules = (_xray(OwnerGuard.all)['routing'] as Map)['rules'] as List;
      expect((rules.first as Map)['ruleTag'], 'outside-vpn');
      expect((rules.first as Map)['inboundTag'], ['tun-in']);
    });

    test(
      'чужое соединение блокируется раньше DNS, exit-ip-probe и списков',
      () {
        final c = _xray(OwnerGuard.all);
        expect(_x(c), 'block');
        expect(_x(c, ip: '172.19.0.2', port: 53, network: 'udp'), 'block');
        expect(_x(c, ip: '1.1.1.1', port: 53, network: 'udp'), 'block');
        expect(_x(c, host: 'www.cloudflare.com', ip: ''), 'block');
        expect(_x(c, host: 'mail.ru', ip: ''), 'block');
      },
    );

    test('своё приложение и молчание моста идут как без защиты', () {
      final on = _xray(OwnerGuard.all);
      final off = _xray(OwnerGuard.off);
      for (final process in [_chrome, '']) {
        for (final (host, ip, port, network) in [
          ('', '93.184.216.34', 443, 'tcp'),
          ('', '172.19.0.2', 53, 'udp'),
          ('www.cloudflare.com', '', 443, 'tcp'),
          ('mail.ru', '', 443, 'tcp'),
        ]) {
          expect(
            _x(
              on,
              process: process,
              host: host,
              ip: ip,
              port: port,
              network: network,
            ),
            _x(
              off,
              process: process,
              host: host,
              ip: ip,
              port: port,
              network: network,
            ),
          );
        }
      }
    });

    test('локальные входы защита не трогает', () {
      final c = _xray(OwnerGuard.all);
      expect(_x(c, inbound: 'socks-in'), isNot('block'));
      expect(_x(c, inbound: 'http-in'), isNot('block'));
    });

    // мост не называет маркером DNS самого Android, и такой запрос идёт как без защиты
    test('DNS без владельца идёт к нашему DNS и Частному DNS как раньше', () {
      final on = _xray(OwnerGuard.all);
      final off = _xray(OwnerGuard.off);
      expect(_x(on, ip: '1.1.1.1', port: 853), 'block');
      for (final (ip, port, network) in [
        ('172.19.0.2', 53, 'udp'),
        ('172.19.0.2', 853, 'tcp'),
        ('1.1.1.1', 853, 'tcp'),
      ]) {
        expect(
          _x(on, process: '', ip: ip, port: port, network: network),
          _x(off, process: '', ip: ip, port: port, network: network),
        );
      }
    });

    test('готовый конфиг: блок раньше авторских правил', () {
      final c = _xray(OwnerGuard.all, input: jsonEncode(_custom));
      expect(_x(c), 'keq-block');
      expect(_x(c, ip: '1.1.1.1', port: 53, network: 'udp'), 'keq-block');
      expect(
        _x(c, process: _chrome, ip: '1.1.1.1', port: 53, network: 'udp'),
        'direct',
      );
      expect(
        (c['outbounds'] as List).where((o) => (o as Map)['tag'] == 'keq-block'),
        hasLength(1),
      );
    });

    test('на ПК и в пробе защиты нет', () {
      final desktop = _xray(
        OwnerGuard.all,
        desktopTun: const DesktopTunOptions(windows: true, mtu: 1500),
      );
      final rules = (desktop['routing'] as Map)['rules'] as List;
      expect(rules.any((r) => (r as Map)['ruleTag'] == 'outside-vpn'), isFalse);
      final proxy = _xray(OwnerGuard.all, tun: false);
      final proxyRules = (proxy['routing'] as Map)['rules'] as List;
      expect(
        proxyRules.any((r) => (r as Map)['ruleTag'] == 'outside-vpn'),
        isFalse,
      );
    });
  });

  group('mihomo', () {
    test('выключенная защита: конфиг как без параметра', () {
      Socks5Credentials().init('u', 'p');
      for (final input in [_link, _clash]) {
        expect(
          MihomoConfigGen.generate(
            input,
            _settings,
            socksPort: 2080,
            tun: _androidTun,
            ownerGuard: OwnerGuard.off,
          ),
          MihomoConfigGen.generate(
            input,
            _settings,
            socksPort: 2080,
            tun: _androidTun,
          ),
        );
      }
    });

    test('ключ для ядра и поиск владельца', () {
      final on = _mihomo(OwnerGuard.all);
      expect(on[MihomoConfigGen.ownerGuardKey], 'all');
      expect(on['find-process-mode'], 'strict');
      expect((on['rules'] as List).first, startsWith('AND,((IN-TYPE,TUN)'));

      final off = _mihomo(OwnerGuard.off);
      expect(off.containsKey(MihomoConfigGen.ownerGuardKey), isFalse);
      expect(off['find-process-mode'], 'off');
    });

    test('чужое соединение из туннеля отклоняется, остальное как раньше', () {
      final on = _mihomo(OwnerGuard.all);
      final off = _mihomo(OwnerGuard.off);
      expect(_m(on), 'REJECT');
      expect(_m(on, port: 853), 'REJECT');
      expect(_m(on, inType: 'HTTP'), _m(off, inType: 'HTTP'));
      expect(_m(on, inType: 'SOCKS5'), _m(off, inType: 'SOCKS5'));
      for (final process in [_chrome, '']) {
        expect(_m(on, process: process), _m(off, process: process));
      }
    });

    test('готовый Clash: правило раньше авторских', () {
      final c = _mihomo(OwnerGuard.all, input: _clash);
      expect(_m(c), 'REJECT');
      expect(_m(c, process: _chrome), 'Proxy');
      expect(c[MihomoConfigGen.ownerGuardKey], 'all');
      expect(c['find-process-mode'], 'strict');
    });

    test('на ПК защиты нет', () {
      final c = _mihomo(
        OwnerGuard.all,
        tun: const MihomoTunOptions(stack: 'gvisor'),
      );
      expect(c.containsKey(MihomoConfigGen.ownerGuardKey), isFalse);
      expect(
        (c['rules'] as List).any((r) => '$r'.contains(kOutsideVpnOwner)),
        isFalse,
      );
    });
  });
}
