import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/singbox_tun_config.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// «Свои адреса для доменов» — одно поле на три ядра, и маски у них разные.
///
/// Голый ключ xray разбирает как полное совпадение, поэтому `*.` переезжает в
/// `domain:`; у mihomo та же маска пишется как `+.`, потому что звёздочка там
/// значит ровно один уровень; sing-box масок не знает вовсе и берёт только
/// точные имена с адресами.
const _vless =
    'vless://uuid@de.example.com:443?security=reality&pbk=pub&sid=aa&fp=chrome&sni=de.example.com&type=tcp#DE';

AppSettings _withHosts(String hosts) => const AppSettings().copyWith(
      xrayCore: XrayCoreSettings(dnsHosts: hosts),
    );

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  group('разбор поля', () {
    test('домен и адрес в любом порядке', () {
      final parsed = XrayCoreSettings.parseDnsHosts(
        'example.com 10.0.0.5\n10.0.0.6 other.example.com',
      );

      expect(parsed.entries, {
        'example.com': ['10.0.0.5'],
        // Системный hosts пишется «адрес домен», и так тоже понимаем.
        'other.example.com': ['10.0.0.6'],
      });
      expect(parsed.dropped, isEmpty);
    });

    test('двоеточие, знак равенства и несколько адресов', () {
      final parsed = XrayCoreSettings.parseDnsHosts(
        'a.example.com: 1.1.1.1, 2.2.2.2\nb.example.com = 3.3.3.3',
      );

      expect(parsed.entries['a.example.com'], ['1.1.1.1', '2.2.2.2']);
      expect(parsed.entries['b.example.com'], ['3.3.3.3']);
    });

    test('псевдоним: вместо адреса другой домен', () {
      final parsed = XrayCoreSettings.parseDnsHosts('old.example.com new.example.com');

      expect(parsed.entries['old.example.com'], ['new.example.com']);
    });

    test('негодные строки не теряются молча', () {
      final parsed = XrayCoreSettings.parseDnsHosts(
        'example.com\n# комментарий\nexample.com 1.1.1.1 second.example.com\n',
      );

      // Строка без адреса и смесь «адрес плюс чужой домен» — обе не годятся
      // ни одному ядру, и обе обязаны попасть в dropped, а не исчезнуть.
      expect(parsed.entries, isEmpty);
      expect(parsed.dropped.length, 2);
    });
  });

  group('в конфигах ядер', () {
    test('xray: точное имя как есть, маска через domain:', () {
      final config = jsonDecode(
        ConfigGeneratorV2.generateConfig(
          _vless,
          _withHosts('example.com 10.0.0.5\n*.lan.example.com 10.0.0.6'),
        ),
      ) as Map<String, dynamic>;

      final hosts = (config['dns'] as Map<String, dynamic>)['hosts']
          as Map<String, dynamic>;
      expect(hosts['example.com'], '10.0.0.5');
      expect(hosts['domain:lan.example.com'], '10.0.0.6');
    });

    test('mihomo: маска через +.', () {
      final config = MihomoConfigGen.build(
        _vless,
        _withHosts('example.com 10.0.0.5\n*.lan.example.com 10.0.0.6'),
        socksPort: 2080,
      );

      final hosts = config['hosts'] as Map<String, dynamic>;
      expect(hosts['example.com'], '10.0.0.5');
      expect(hosts['+.lan.example.com'], '10.0.0.6');
    });

    test('пустое поле не добавляет ключей', () {
      final xray = jsonDecode(
        ConfigGeneratorV2.generateConfig(_vless, const AppSettings()),
      ) as Map<String, dynamic>;
      final mihomo = MihomoConfigGen.build(
        _vless,
        const AppSettings(),
        socksPort: 2080,
      );

      expect((xray['dns'] as Map<String, dynamic>).containsKey('hosts'), isFalse);
      expect(mihomo.containsKey('hosts'), isFalse);
    });

    test('sing-box берёт точные имена, а про остальные говорит вслух', () {
      final settings = _withHosts(
        'example.com 10.0.0.5\n*.lan.example.com 10.0.0.6\nold.example.com new.example.com',
      );

      expect(SingBoxTunConfigGen.hostsServerEntries(settings), {
        'example.com': ['10.0.0.5'],
      });
      // Маска и псевдоним этому ядру не по зубам: карта у сервера `hosts`
      // точная. Молчать об этом нельзя — настройка выглядела бы сломанной.
      expect(SingBoxTunConfigGen.ignoredHostsEntries(settings).length, 2);
    });
  });
}
