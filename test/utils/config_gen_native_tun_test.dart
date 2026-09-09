import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// Инбаунд, которым ядро само читает пакеты из туннеля.
///
/// Дескриптор в конфиг не попадает и попасть не может: ядро читает его из
/// переменной окружения, а номер знает только нативная часть, поднявшая
/// интерфейс. Здесь проверяется всё остальное — что инбаунд появляется там,
/// где должен, не появляется там, где не должен, и не отбирает у конфига
/// ничего из уже работавшего.
const _link = 'vless://00000000-0000-4000-8000-000000000000@198.51.100.10:443'
    '?type=tcp&security=none#tun';

Map<String, dynamic> _config({
  bool nativeTun = true,
  AppSettings settings = const AppSettings(),
}) {
  Socks5Credentials().init('u', 'p');
  return jsonDecode(
    ConfigGeneratorV2.generateConfig(
      _link,
      settings,
      nativeTunInbound: nativeTun,
    ),
  ) as Map<String, dynamic>;
}

List<Map<String, dynamic>> _inbounds(Map<String, dynamic> config) =>
    (config['inbounds'] as List).cast<Map<String, dynamic>>();

Map<String, dynamic>? _tun(Map<String, dynamic> config) {
  for (final inbound in _inbounds(config)) {
    if (inbound['protocol'] == 'tun') return inbound;
  }
  return null;
}

void main() {
  group('инбаунд появляется', () {
    test('форма — ровно та, которую разбирает ядро', () {
      final tun = _tun(_config())!;

      expect(tun['tag'], 'tun-in');
      expect(tun['protocol'], 'tun');
      // Порт ядро у tun не спрашивает, но ключ обязан быть: без него разбор
      // падает на «Listen on AnyIP but no Port(s) set».
      expect(tun.containsKey('port'), isTrue);
      expect((tun['settings'] as Map)['mtu'], isA<int>());
      // Дескриптор — не наше дело: его знает только нативная часть.
      expect(jsonEncode(tun), isNot(contains('fd')));
    });

    test('имя интерфейса задано', () {
      // Проверено на устройстве: пустое имя ядро понимает как «придумай сам» и
      // идёт перебирать занятые через netlink, куда untrusted-приложение не
      // пускают. Разбор конфига падает целиком —
      // `netlinkrib: permission denied`, ни одного инбаунда не поднимается.
      final name = (_tun(_config())!['settings'] as Map)['name'];
      expect(name, isA<String>());
      expect(name as String, isNotEmpty);
    });

    test('снифер включён: без него роутинг по доменам умирает разом', () {
      expect((_tun(_config())!['sniffing'] as Map)['enabled'], isTrue);
    });

    test('локальные инбаунды остаются: через них ходит само приложение', () {
      final tags = [for (final i in _inbounds(_config())) i['tag']];
      expect(tags, contains('socks-in'));
      expect(tags, contains('http-in'));
      expect(tags, contains('tun-in'));
    });

    test('пароль на локальном порту никуда не девается', () {
      final socks = _inbounds(_config())
          .firstWhere((i) => i['tag'] == 'socks-in');
      expect((socks['settings'] as Map)['auth'], 'password');
    });

    test('перехват DNS продолжает работать: правило не привязано к инбаунду',
        () {
      final rules =
          ((_config()['routing'] as Map)['rules'] as List).cast<Map>();
      final dns = rules.firstWhere((r) => r['ruleTag'] == 'dns-out');
      expect(dns.containsKey('inboundTag'), isFalse);
    });
  });

  group('инбаунд не появляется', () {
    test('выключенный флаг — конфиг ровно такой же, как был', () {
      Socks5Credentials().init('u', 'p');
      final withFlag = ConfigGeneratorV2.generateConfig(
        _link,
        const AppSettings(),
        nativeTunInbound: false,
      );
      final without = ConfigGeneratorV2.generateConfig(
        _link,
        const AppSettings(),
      );
      expect(withFlag, without);
      expect(_tun(jsonDecode(without) as Map<String, dynamic>), isNull);
    });

    test('в конфиге замера его нет: пинг туннеля не поднимает', () {
      Socks5Credentials().init('u', 'p');
      final ping = jsonDecode(
        ConfigGeneratorV2.generatePingConfig(
          _link,
          const AppSettings(),
          socksPort: 28150,
          httpInbound: false,
        ),
      ) as Map<String, dynamic>;
      expect(_tun(ping), isNull);
    });
  });
}
