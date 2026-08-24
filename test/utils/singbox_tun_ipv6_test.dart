import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/tun_settings.dart';
import 'package:keqdroid/utils/host_ipv6.dart';
import 'package:keqdroid/utils/singbox_tun_config.dart';

/// IPv6 мимо туннеля.
///
/// TUN-интерфейс с одним IPv4-адресом не получает IPv6-маршрутов: на
/// двухстековой машине каждое IPv6-соединение уходит мимо туннеля — мимо
/// правил роутинга и мимо прокси. Наш DNS отдаёт только A-записи, но браузер со
/// своим DoH получает AAAA сам, и «сайт открылся в обход VPN» на дуалстеке —
/// это оно.
///
/// Второе условие такое же важное: адрес заводится ТОЛЬКО когда у машины есть
/// настоящий глобальный IPv6. Там, где IPv6 выключен в системе, sing-box падает
/// на настройке адаптера («set ipv6 dns: Access is denied»), и «починка утечки»
/// означала бы неработающий TUN.
Map<String, dynamic> _config({
  required bool hostHasIpv6,
  TunSettings tun = const TunSettings(),
}) =>
    jsonDecode(
          SingBoxTunConfigGen.generate(
            localSocksPort: 2080,
            socksUsername: 'u',
            socksPassword: 'p',
            serverIpToExclude: '203.0.113.10',
            settings: AppSettings(tun: tun),
            windows: true,
            hostHasIpv6: hostHasIpv6,
          ),
        )
        as Map<String, dynamic>;

List<Map<String, dynamic>> _rules(Map<String, dynamic> config) =>
    ((config['route'] as Map)['rules'] as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _tunInbound(Map<String, dynamic> config) =>
    (config['inbounds'] as List).first as Map<String, dynamic>;

void main() {
  test('на машине с глобальным IPv6 интерфейс забирает и IPv6', () {
    final config = _config(hostHasIpv6: true);
    final address = (_tunInbound(config)['address'] as List).cast<String>();

    expect(address, contains(kTunInterfacePrefix));
    expect(
      address,
      contains(kTunInterfaceIpv6Prefix),
      reason: 'без IPv6-адреса ядро не ставит IPv6-маршруты, и IPv6 утекает',
    );
  });

  test('выход IPv6 наружу закрыт, а локальный IPv6 остаётся прямым', () {
    final rules = _rules(_config(hostHasIpv6: true));

    final blockIndex = rules.indexWhere(
      (r) =>
          r['outbound'] == 'block' &&
          (r['ip_cidr'] as List?)?.contains('::/0') == true,
    );
    expect(blockIndex, isNot(-1), reason: 'IPv6 обязан быть закрыт');

    final localIndex = rules.indexWhere(
      (r) =>
          r['outbound'] == 'direct' &&
          (r['ip_cidr'] as List?)?.contains('fe80::/10') == true,
    );
    expect(localIndex, isNot(-1), reason: 'link-local нужен соседям и SLAAC');
    expect(
      localIndex,
      lessThan(blockIndex),
      reason:
          'первое совпавшее правило и решает: локальный IPv6 идёт раньше '
          'запрета, иначе mDNS/SSDP в своей же сети окажутся заблокированы',
    );

    final local = rules[localIndex]['ip_cidr'] as List;
    expect(local, containsAll(kLocalIpv6Cidrs));
  });

  test('правила пользователя сильнее умолчания про IPv6', () {
    final config = _config(hostHasIpv6: true);
    final rules = _rules(config);
    final blockIndex = rules.indexWhere(
      (r) =>
          r['outbound'] == 'block' &&
          (r['ip_cidr'] as List?)?.contains('::/0') == true,
    );
    // Своё IPv6-правило пользователя (proxy) обязано стоять раньше запрета.
    final userProxy = _rules(
      jsonDecode(
            SingBoxTunConfigGen.generate(
              localSocksPort: 2080,
              socksUsername: 'u',
              socksPassword: 'p',
              serverIpToExclude: '203.0.113.10',
              settings: const AppSettings(proxyRules: '2001:db8::/32'),
              windows: true,
              hostHasIpv6: true,
            ),
          )
          as Map<String, dynamic>,
    );
    final userIndex = userProxy.indexWhere(
      (r) =>
          r['outbound'] == 'proxy' &&
          (r['ip_cidr'] as List?)?.contains('2001:db8::/32') == true,
    );
    final userBlockIndex = userProxy.indexWhere(
      (r) =>
          r['outbound'] == 'block' &&
          (r['ip_cidr'] as List?)?.contains('::/0') == true,
    );

    expect(userIndex, isNot(-1));
    expect(userIndex, lessThan(userBlockIndex));
    expect(blockIndex, isNot(-1));
  });

  test('без глобального IPv6 у машины конфиг IPv6 не трогает', () {
    final config = _config(hostHasIpv6: false);
    expect((_tunInbound(config)['address'] as List), [kTunInterfacePrefix]);
    expect(
      _rules(config).any(
        (r) =>
            (r['ip_cidr'] as List?)?.contains('::/0') == true ||
            (r['ip_cidr'] as List?)?.contains('fe80::/10') == true,
      ),
      isFalse,
      reason: 'мёртвые IPv6-строки в конфиге у всех, у кого IPv6 нет',
    );
  });

  test('выключенная настройка возвращает прежнее поведение', () {
    final config = _config(
      hostHasIpv6: true,
      tun: const TunSettings(blockIpv6Leak: false),
    );
    expect((_tunInbound(config)['address'] as List), [kTunInterfacePrefix]);
    expect(
      _rules(
        config,
      ).any((r) => (r['ip_cidr'] as List?)?.contains('::/0') == true),
      isFalse,
    );
  });

  test('IPv6-адрес сервера исключается маской /128, а не /32', () {
    final config =
        jsonDecode(
              SingBoxTunConfigGen.generate(
                localSocksPort: 2080,
                socksUsername: 'u',
                socksPassword: 'p',
                serverIpToExclude: '2a03:90c0:9992::1',
                settings: const AppSettings(),
                windows: true,
              ),
            )
            as Map<String, dynamic>;

    final direct = _rules(config).firstWhere(
      (r) =>
          r['outbound'] == 'direct' &&
          (r['ip_cidr'] as List?)?.first.toString().startsWith('2a03') == true,
    );
    expect(
      (direct['ip_cidr'] as List).first,
      '2a03:90c0:9992::1/128',
      reason: '/32 на IPv6 — это не сам сервер, а треть интернета мимо туннеля',
    );
  });

  group('признак глобального IPv6', () {
    test('глобальные адреса', () {
      expect(isGlobalIpv6('2a03:90c0:9992::1'), isTrue);
      expect(isGlobalIpv6('2606:4700:4700::1111'), isTrue);
    });

    test('локальные и туннельные адреса глобальными не считаются', () {
      expect(isGlobalIpv6('fe80::1%eth0'), isFalse, reason: 'link-local');
      expect(isGlobalIpv6('fd00::1'), isFalse, reason: 'ULA');
      expect(isGlobalIpv6('fc00::1'), isFalse, reason: 'ULA');
      expect(isGlobalIpv6('::1'), isFalse, reason: 'петля');
      expect(isGlobalIpv6('2002:c000:204::1'), isFalse, reason: '6to4');
      expect(isGlobalIpv6('2001:0:4137:9e76::1'), isFalse, reason: 'Teredo');
      expect(isGlobalIpv6('192.168.0.1'), isFalse, reason: 'не IPv6 вовсе');
    });
  });
}
