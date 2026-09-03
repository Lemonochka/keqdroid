import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/proxy_chain.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

const _vless =
    'vless://uuid@de.example.com:443?security=reality&pbk=pub&sid=aa&fp=chrome&sni=de.example.com&type=tcp#DE';
const _trojan =
    'trojan://pass@nl.example.com:8443?sni=nl.example.com&type=ws&path=/w#NL';
const _hysteria = 'hysteria2://pass@hy.example.com:443?sni=hy.example.com#HY';

AppSettings _withFragment({
  bool enabled = true,
  String packets = XrayCoreSettings.fragmentPacketsTlsHello,
  String length = XrayCoreSettings.defaultFragmentLength,
  String interval = XrayCoreSettings.defaultFragmentInterval,
  String dnsQueryStrategy = 'UseIPv4',
}) =>
    const AppSettings().copyWith(
      xrayCore: XrayCoreSettings(
        fragmentEnabled: enabled,
        fragmentPackets: packets,
        fragmentLength: length,
        fragmentInterval: interval,
        dnsQueryStrategy: dnsQueryStrategy,
      ),
    );

List<Map<String, dynamic>> _outbounds(Map<String, dynamic> config) =>
    (config['outbounds'] as List).cast<Map<String, dynamic>>();

Map<String, dynamic>? _byTag(Map<String, dynamic> config, String tag) {
  for (final o in _outbounds(config)) {
    if (o['tag'] == tag) return o;
  }
  return null;
}

String? _dialerProxyOf(Map<String, dynamic>? outbound) {
  final stream = outbound?['streamSettings'] as Map<String, dynamic>?;
  final sockopt = stream?['sockopt'] as Map<String, dynamic>?;
  return sockopt?['dialerProxy'] as String?;
}

Map<String, dynamic> _generate(String link, AppSettings settings) =>
    jsonDecode(ConfigGeneratorV2.generateConfig(link, settings))
        as Map<String, dynamic>;

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  group('ConfigGeneratorV2 fragment', () {
    test('выключена по умолчанию: конфиг остаётся прежним', () {
      final config = _generate(_vless, const AppSettings());

      expect(_byTag(config, 'fragment'), isNull);
      expect(_dialerProxyOf(_byTag(config, 'proxy')), isNull);
    });

    test('включённая заводит freedom-аутбаунд и дозвон через него', () {
      final config = _generate(_vless, _withFragment());

      expect(_dialerProxyOf(_byTag(config, 'proxy')), 'fragment');

      final fragment = _byTag(config, 'fragment')!;
      expect(fragment['protocol'], 'freedom');
      final settings = fragment['settings'] as Map<String, dynamic>;
      expect(settings['fragment'], {
        'packets': 'tlshello',
        'length': '100-200',
        'interval': '10-20',
      });
      // Резолв домена сервера остаётся на DNS-блоке конфига, а не на
      // системном резолвере Go — иначе на Android он не отвечает.
      expect(settings['domainStrategy'], 'UseIPv4');
    });

    test('фрагмент-аутбаунд не становится основным', () {
      final config = _generate(_vless, _withFragment());
      final tags = _outbounds(config).map((o) => o['tag']).toList();

      expect(tags.first, 'proxy');
      expect(tags.indexOf('fragment'), greaterThan(tags.indexOf('proxy')));
    });

    test('целое число и диапазон доезжают как есть, мусор — дефолтом', () {
      final numeric =
          _generate(_vless, _withFragment(length: '80', interval: '0'));
      final fragment = ((_byTag(numeric, 'fragment')!['settings']
          as Map<String, dynamic>)['fragment'] as Map<String, dynamic>);
      expect(fragment['length'], 80);
      // 0 с tlshello — «разрезать, но отправить одним пакетом», значение рабочее.
      expect(fragment['interval'], 0);

      final broken = _generate(
        _vless,
        _withFragment(length: '100-', interval: 'десять'),
      );
      final fallback = ((_byTag(broken, 'fragment')!['settings']
          as Map<String, dynamic>)['fragment'] as Map<String, dynamic>);
      expect(fallback['length'], '100-200');
      expect(fallback['interval'], '10-20');
    });

    test('неизвестный режим packets откатывается на tlshello', () {
      final config = _generate(_vless, _withFragment(packets: 'chaos'));
      final fragment = ((_byTag(config, 'fragment')!['settings']
          as Map<String, dynamic>)['fragment'] as Map<String, dynamic>);

      expect(fragment['packets'], 'tlshello');
    });

    test('в цепочке режется только внешний сокет входного узла', () {
      final link = ProxyChainConfig(
        name: 'chain',
        hops: const [
          ProxyChainHop(config: _vless),
          ProxyChainHop(config: _trojan),
        ],
      ).encode();

      final config = _generate(link, _withFragment());

      // chain-0 — входной узел, он один дозванивается наружу.
      expect(_dialerProxyOf(_byTag(config, 'chain-0')), 'fragment');
      // Выходной узел продолжает ходить через своё звено, а не через фрагмент.
      expect(_dialerProxyOf(_byTag(config, 'proxy')), 'chain-0');
    });

    test('UDP-транспорт не трогаем вовсе', () {
      final config = _generate(_hysteria, _withFragment());

      expect(_byTag(config, 'fragment'), isNull);
      expect(_dialerProxyOf(_byTag(config, 'proxy')), isNull);
    });

    test('проба пингует через ту же фрагментацию', () {
      final config = jsonDecode(
        ConfigGeneratorV2.generatePingConfig(
          _vless,
          _withFragment(),
          socksPort: 10800,
        ),
      ) as Map<String, dynamic>;

      expect(_dialerProxyOf(_byTag(config, 'proxy')), 'fragment');
      expect(_byTag(config, 'fragment'), isNotNull);
    });
  });
}
