import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/proxy_chain.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// Гонка адресов при дозвоне: одна настройка, две разные ручки у ядер.
///
/// У mihomo это глобальный `tcp-concurrent`, у xray — `sockopt.happyEyeballs`
/// на конкретном аутбаунде, и там важно, кто именно звонит наружу: за
/// `dialerProxy` ядро гонку не исполняет вовсе, поэтому с фрагментацией она
/// обязана оказаться на freedom-аутбаунде, а в цепочке её быть не должно.
const _vless =
    'vless://uuid@de.example.com:443?security=reality&pbk=pub&sid=aa&fp=chrome&sni=de.example.com&type=tcp#DE';
const _second =
    'trojan://pass@nl.example.com:8443?sni=nl.example.com&type=ws&path=/w#NL';

AppSettings _settings({required bool concurrent, bool fragment = false}) =>
    const AppSettings().copyWith(
      xrayCore: XrayCoreSettings(
        concurrentDial: concurrent,
        fragmentEnabled: fragment,
      ),
    );

Map<String, dynamic> _xray(String link, AppSettings settings) =>
    jsonDecode(ConfigGeneratorV2.generateConfig(link, settings))
        as Map<String, dynamic>;

Map<String, dynamic>? _byTag(Map<String, dynamic> config, String tag) {
  for (final o in (config['outbounds'] as List).cast<Map<String, dynamic>>()) {
    if (o['tag'] == tag) return o;
  }
  return null;
}

Map<String, dynamic>? _happy(Map<String, dynamic>? outbound) {
  final stream = outbound?['streamSettings'] as Map<String, dynamic>?;
  final sockopt = stream?['sockopt'] as Map<String, dynamic>?;
  return sockopt?['happyEyeballs'] as Map<String, dynamic>?;
}

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  group('xray', () {
    test('выключено — в конфиге гонки нет вовсе', () {
      final config = _xray(_vless, _settings(concurrent: false));

      expect(_happy(_byTag(config, 'proxy')), isNull);
      expect(_happy(_byTag(config, 'direct')), isNull);
    });

    test('включено — и туннель, и прямой маршрут', () {
      final config = _xray(_vless, _settings(concurrent: true));

      // Оба числа обязаны быть больше нуля: с нулём ядро молча возвращается
      // к перебору адресов по очереди, и настройка не значит ничего.
      for (final tag in ['proxy', 'direct']) {
        final happy = _happy(_byTag(config, tag));
        expect(happy, isNotNull, reason: tag);
        expect(happy!['tryDelayMs'], greaterThan(0), reason: tag);
        expect(happy['maxConcurrentTry'], greaterThan(0), reason: tag);
      }
    });

    test('с фрагментацией гонка переезжает на того, кто звонит', () {
      final config =
          _xray(_vless, _settings(concurrent: true, fragment: true));

      // Прокси-аутбаунд теперь дозванивается через freedom, и ядро его
      // собственную гонку игнорирует — держать её там значит врать конфигом.
      expect(_happy(_byTag(config, 'proxy')), isNull);
      expect(_happy(_byTag(config, 'fragment')), isNotNull);
    });

    test('в цепочке гонки нет ни на одном звене', () {
      final chain = ProxyChainConfig(
        name: 'chain',
        hops: [
          ProxyChainHop(config: _second),
          ProxyChainHop(config: _vless),
        ],
      ).encode();
      final config = _xray(chain, _settings(concurrent: true));

      for (final outbound
          in (config['outbounds'] as List).cast<Map<String, dynamic>>()) {
        final sockopt = (outbound['streamSettings']
            as Map<String, dynamic>?)?['sockopt'] as Map<String, dynamic>?;
        final tag = outbound['tag']?.toString() ?? '';
        if (sockopt?['dialerProxy'] != null) {
          expect(sockopt!['happyEyeballs'], isNull, reason: tag);
        }
      }
    });
  });

  group('mihomo', () {
    test('выключено — ключа в конфиге нет', () {
      final config = MihomoConfigGen.build(
        _vless,
        _settings(concurrent: false),
        socksPort: 2080,
      );

      expect(config.containsKey('tcp-concurrent'), isFalse);
    });

    test('включено — один флаг на всё ядро', () {
      final config = MihomoConfigGen.build(
        _vless,
        _settings(concurrent: true),
        socksPort: 2080,
      );

      expect(config['tcp-concurrent'], isTrue);
    });
  });
}
