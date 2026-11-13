import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/traffic_route.dart';
import 'package:keqdroid/tunnel/app_routing_mode.dart';
import 'package:keqdroid/utils/app_routes.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/desktop_tun.dart';
import 'package:keqdroid/utils/proxy_chain.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// TUN на ПК держит сам xray. Здесь то, что раньше решал sing-box перед
/// xray: кто идёт мимо туннеля, куда девается IPv6, как ведут себя режимы
/// сплита. Порядок правил целиком фиксируют голдены vless-desktop-tun-*.
const _link = 'vless://00000000-0000-4000-8000-000000000000@198.51.100.40:443'
    '?type=tcp&security=tls&sni=pc.example#pc';

Map<String, dynamic> _config(
  DesktopTunOptions tun, {
  AppSettings settings = const AppSettings(),
  String input = _link,
  List<RouteAppRules> appRoutes = const [],
}) {
  Socks5Credentials().init('u', 'p');
  return jsonDecode(
    ConfigGeneratorV2.generateConfig(
      input,
      settings,
      desktopTun: tun,
      appRoutes: appRoutes,
    ),
  ) as Map<String, dynamic>;
}

List<Map<String, dynamic>> _rules(Map<String, dynamic> config) =>
    ((config['routing'] as Map)['rules'] as List).cast<Map<String, dynamic>>();

Map<String, dynamic>? _rule(Map<String, dynamic> config, String tag) {
  for (final rule in _rules(config)) {
    if (rule['ruleTag'] == tag) return rule;
  }
  return null;
}

Map<String, dynamic> _tunSettings(Map<String, dynamic> config) =>
    ((config['inbounds'] as List).first as Map)['settings']
        as Map<String, dynamic>;

const _windows = DesktopTunOptions(windows: true, mtu: 9000);
const _linux = DesktopTunOptions(windows: false, mtu: 9000);

void main() {
  test('своё приложение и ядра замера мимо туннеля, только из TUN', () {
    final own = _rule(
      _config(const DesktopTunOptions(
        windows: true,
        mtu: 9000,
        appProcessName: 'keqdroid.exe',
      )),
      'tun-own',
    )!;
    expect(own['inboundTag'], ['tun-in']);
    expect(own['process'], ['keqdroid.exe', 'xray', 'mihomo']);
    expect(own['outboundTag'], 'direct');
  });

  test('DNS любой программы перехватывается раньше правил по процессам', () {
    final rules = _rules(_config(_windows));
    final dns = rules.indexWhere((r) => r['ruleTag'] == 'tun-dns');
    final own = rules.indexWhere((r) => r['ruleTag'] == 'tun-own');
    expect(dns, 0);
    expect(own, greaterThan(dns));
  });

  test('чужие VPN-клиенты мимо туннеля только в режиме весь трафик', () {
    expect(
      _rule(_config(_windows), 'tun-other-vpn')!['process'],
      contains('openvpn-gui'),
    );
    expect(
      _rule(_config(_linux), 'tun-other-vpn')!['process'],
      isNot(contains('openvpn-gui')),
    );
    expect(
      _rule(
        _config(const DesktopTunOptions(
          windows: true,
          mtu: 9000,
          routingMode: AppRoutingMode.allExceptSelected,
          managedProcessNames: ['steam.exe'],
        )),
        'tun-other-vpn',
      ),
      isNull,
    );
  });

  test('только выбранные: невыбранные одним правилом с отрицанием', () {
    final config = _config(const DesktopTunOptions(
      windows: true,
      mtu: 9000,
      routingMode: AppRoutingMode.onlySelected,
      managedProcessNames: ['firefox.exe', r'C:\Apps\chat.exe', '  '],
    ));
    expect(_rule(config, 'tun-unselected')!['process'], [
      '!firefox.exe',
      r'!C:\Apps\chat.exe',
    ]);
    // финал остаётся настройкой «всё остальное»: выбранные идут по всем правилам
    expect(_rules(config).last['outboundTag'], 'proxy');
  });

  test('только выбранные без единого имени: остальное напрямую, как у mihomo', () {
    final rules = _rules(_config(const DesktopTunOptions(
      windows: true,
      mtu: 9000,
      routingMode: AppRoutingMode.onlySelected,
      managedProcessNames: [''],
    )));
    final catchAll = rules[rules.length - 2];
    expect(catchAll['ruleTag'], 'tun-unselected');
    expect(catchAll['inboundTag'], ['tun-in']);
    expect(catchAll['outboundTag'], 'direct');
    expect(catchAll.containsKey('process'), isFalse);
  });

  test('кроме выбранных: выбранные напрямую', () {
    final rule = _rule(
      _config(const DesktopTunOptions(
        windows: false,
        mtu: 9000,
        routingMode: AppRoutingMode.allExceptSelected,
        managedProcessNames: ['steam', '/opt/game/game'],
      )),
      'tun-excluded',
    )!;
    expect(rule['process'], ['steam', '/opt/game/game']);
    expect(rule['outboundTag'], 'direct');
  });

  test('IPv6 закрывается перед final и только из TUN', () {
    final rules = _rules(_config(const DesktopTunOptions(
      windows: true,
      mtu: 9000,
      captureIpv6: true,
    )));
    final ipv6 = rules[rules.length - 2];
    expect(ipv6['ruleTag'], 'tun-ipv6');
    expect(ipv6['ip'], ['::/0']);
    expect(ipv6['inboundTag'], ['tun-in']);
    expect(ipv6['outboundTag'], 'block');
    expect(_rule(_config(_windows), 'tun-ipv6'), isNull);
  });

  test('без захвата IPv6 на адаптере нет IPv6-адреса и маршрута', () {
    final settings = _tunSettings(_config(_windows));
    expect(settings['gateway'], [kTunInterfacePrefix]);
    expect(settings['autoSystemRoutingTable'], ['0.0.0.0/0']);
  });

  test('на Linux маршрут по умолчанию в таблицу ядра, без DNS и WFP', () {
    final settings = _tunSettings(_config(const DesktopTunOptions(
      windows: false,
      mtu: 1500,
      strictRoute: true,
    )));
    expect(settings['autoSystemRoutingTable'], ['0.0.0.0/0']);
    expect(settings.containsKey('dns'), isFalse);
    expect(settings.containsKey('autoSystemWfpBlockLeak'), isFalse);
    expect(settings['mtu'], 1500);
  });

  test('строгий маршрут на Windows закрывает DNS и семейство без маршрута', () {
    final strict = _tunSettings(_config(const DesktopTunOptions(
      windows: true,
      mtu: 9000,
      strictRoute: true,
    )));
    expect(strict['dns'], [kTunDnsAddress]);
    expect(strict['autoSystemWfpBlockLeak'], ['dns', 'misconfigtun']);
    expect(
      _tunSettings(_config(_windows)).containsKey('autoSystemWfpBlockLeak'),
      isFalse,
    );
  });

  test('без своих маршрутов ядро их не ставит и WFP не включает', () {
    final settings = _tunSettings(_config(const DesktopTunOptions(
      windows: true,
      mtu: 9000,
      autoRoute: false,
      strictRoute: true,
    )));
    expect(settings.containsKey('autoSystemRoutingTable'), isFalse);
    expect(settings.containsKey('autoSystemWfpBlockLeak'), isFalse);
    expect(settings['autoOutboundsInterface'], 'auto');
  });

  test('таймаут UDP по умолчанию не пишет политику', () {
    expect(_config(_windows).containsKey('policy'), isFalse);
  });

  test('свой таймаут UDP: уровень 1 со всеми четырьмя таймаутами', () {
    final config = _config(const DesktopTunOptions(
      windows: true,
      mtu: 9000,
      udpTimeoutSec: 60,
    ));
    // одно поле обнулило бы остальные: ToCorePolicy берёт все четыре
    expect((config['policy'] as Map)['levels'], {
      '1': {
        'handshake': 60,
        'connIdle': 60,
        'uplinkOnly': 1,
        'downlinkOnly': 1,
      },
    });
  });

  test('маршруты по приложениям работают в TUN на ПК', () {
    final config = _config(
      _windows,
      appRoutes: const [
        RouteAppRules(
          tag: 'keq-app-0',
          apps: ['discord.exe'],
          target: RouteTarget.direct,
          allTraffic: true,
        ),
      ],
    );
    final rule = _rule(config, 'keq-app-0')!;
    expect(rule['process'], ['discord.exe']);
    expect(rule['inboundTag'], ['tun-in']);
  });

  test('Fake IP включается и на ПК', () {
    final config = _config(
      _windows,
      settings: const AppSettings(fakeIp: true),
    );
    expect(config.containsKey('fakedns'), isTrue);
  });

  test('цепочка получает те же правила TUN', () {
    final chain = const ProxyChainConfig(
      name: 'chain',
      hops: [
        ProxyChainHop(config: _link),
        ProxyChainHop(
          config: 'vless://00000000-0000-4000-8000-000000000000'
              '@198.51.100.41:443?type=tcp&security=tls&sni=b.example#b',
        ),
      ],
    ).encode();
    final config = _config(_windows, input: chain);
    expect(_rule(config, 'tun-own'), isNotNull);
    expect(_tunSettings(config)['name'], kTunInterfaceName);
  });

  test('готовый конфиг со своим fakedns: DNS из TUN не перехватываем', () {
    final config = _config(
      _windows,
      input: jsonEncode({
        'fakedns': [
          {'ipPool': '198.18.0.0/15', 'poolSize': 65535},
        ],
        'outbounds': [
          {
            'tag': 'proxy',
            'protocol': 'vless',
            'settings': {
              'address': '198.51.100.42',
              'port': 443,
              'id': '00000000-0000-4000-8000-000000000000',
              'encryption': 'none',
            },
          },
        ],
      }),
    );
    expect(_rule(config, 'tun-dns'), isNull);
    expect(_rule(config, 'tun-own'), isNotNull);
  });
}
