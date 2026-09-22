import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/singbox_tun_config.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// «Резолвер для отдельных доменов»: домен спрашивается там, где велели, и
/// нигде больше.
///
/// Тонкость у xray: в списке `domains` голое имя ядро понимает как подстроку,
/// поэтому запись обязана уезжать туда с префиксом — иначе `example.com`
/// поймает и `notexample.community`.
const _vless =
    'vless://uuid@de.example.com:443?security=reality&pbk=pub&sid=aa&fp=chrome&sni=de.example.com&type=tcp#DE';

AppSettings _withPolicy(String policy) => const AppSettings().copyWith(
      xrayCore: XrayCoreSettings(dnsPolicy: policy),
    );

List<Map<String, dynamic>> _xrayServers(AppSettings settings) {
  final config = jsonDecode(
    ConfigGeneratorV2.generateConfig(_vless, settings),
  ) as Map<String, dynamic>;
  return ((config['dns'] as Map<String, dynamic>)['servers'] as List)
      .cast<Map<String, dynamic>>();
}

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  group('разбор поля', () {
    test('домен и резолвер, двоеточие после домена не мешает', () {
      final parsed = XrayCoreSettings.parseDnsPolicy(
        'home.lan 192.168.1.1\nwork.example.com: https://9.9.9.9/dns-query',
      );

      expect(parsed.entries['home.lan'], ['192.168.1.1']);
      expect(parsed.entries['work.example.com'],
          ['https://9.9.9.9/dns-query']);
      expect(parsed.dropped, isEmpty);
    });

    test('адрес, который ядро не поднимет, не считается', () {
      // `sdns://` и `tls://` у xray молча становятся мёртвым UDP-резолвером —
      // строка без единого годного адреса не должна выглядеть настроенной.
      final parsed = XrayCoreSettings.parseDnsPolicy('home.lan sdns://whatever');

      expect(parsed.entries, isEmpty);
      expect(parsed.dropped, ['home.lan sdns://whatever']);
    });
  });

  group('в конфигах ядер', () {
    test('xray: запись выше общего списка и без отката', () {
      final servers = _xrayServers(_withPolicy('home.lan 192.168.1.1'));

      final policy = servers.firstWhere(
        (s) => s['address'] == '192.168.1.1',
        orElse: () => <String, dynamic>{},
      );
      expect(policy['domains'], ['full:home.lan']);
      expect(policy['skipFallback'], isTrue);

      // Раньше общих резолверов: ядро идёт по списку сверху вниз.
      final policyIndex = servers.indexOf(policy);
      final generalIndex = servers.indexWhere(
        (s) => s['address'].toString().contains('1.1.1.1') &&
            s['domains'] == null,
      );
      expect(policyIndex, lessThan(generalIndex));
    });

    test('xray: маска уезжает как domain:, а не подстрокой', () {
      final servers = _xrayServers(_withPolicy('*.home.lan 192.168.1.1'));

      final policy = servers.firstWhere((s) => s['address'] == '192.168.1.1');
      expect(policy['domains'], ['domain:home.lan']);
    });

    test('mihomo: nameserver-policy теми же масками', () {
      final config = MihomoConfigGen.build(
        _vless,
        _withPolicy('home.lan 192.168.1.1\n*.work.example.com https://9.9.9.9/dns-query'),
        socksPort: 2080,
      );

      final dns = config['dns'] as Map<String, dynamic>;
      final policy = dns['nameserver-policy'] as Map<String, dynamic>;
      expect(policy['home.lan'], ['192.168.1.1']);
      expect(policy['+.work.example.com'], ['https://9.9.9.9/dns-query']);
    });

    test('пустое поле ничего не добавляет', () {
      final config = MihomoConfigGen.build(
        _vless,
        const AppSettings(),
        socksPort: 2080,
      );

      expect(
        (config['dns'] as Map<String, dynamic>).containsKey('nameserver-policy'),
        isFalse,
      );
      expect(
        _xrayServers(const AppSettings()).any((s) => s['skipFallback'] == true &&
            (s['domains'] as List?)?.contains('full:home.lan') == true),
        isFalse,
      );
    });

    test('sing-box: свой сервер и правило на каждую запись', () {
      final policies = SingBoxTunConfigGen.policyDnsServers(
        _withPolicy('home.lan 192.168.1.1'),
      );

      expect(policies.length, 1);
      expect(policies.single.mask, 'home.lan');
      // Тег сервера и тег в правиле обязаны совпадать — иначе правило уводит
      // запрос в несуществующий резолвер, и домен не резолвится вовсе.
      expect(policies.single.server['tag'], policies.single.tag);
    });
  });
}
