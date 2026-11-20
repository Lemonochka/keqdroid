import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

import '../helpers/xray_rules_sim.dart';

// свой CIDR в списке обязан ловить и соединения по домену: при IPIfNonMatch
// xray резолвит домен и проходит правила второй раз, но только если в первом
// не совпало ничего, а прежняя ловушка «любая сеть» совпадала всегда
const _link =
    'vless://00000000-0000-4000-8000-000000000000@203.0.113.10:443'
    '?type=tcp&security=tls&sni=nl.example#NL';

Map<String, dynamic> _config(AppSettings settings) {
  Socks5Credentials().init('u', 'p');
  return jsonDecode(ConfigGeneratorV2.generateConfig(_link, settings))
      as Map<String, dynamic>;
}

String? _go(
  Map<String, dynamic> c, {
  String host = '',
  String ip = '',
  String resolvesTo = '',
}) => simulateXray(
  c,
  XrayConn(inbound: 'socks-in', host: host, ip: ip, resolvesTo: resolvesTo),
);

void main() {
  test('корпоративный CIDR в «Напрямую» ловит и соединение по домену', () {
    final c = _config(const AppSettings(directRules: '10.130.0.0/16'));
    expect((c['routing'] as Map)['domainStrategy'], 'IPIfNonMatch');
    expect(_go(c, host: 'intranet.corp', resolvesTo: '10.130.4.5'), 'direct');
    expect(_go(c, host: 'example.com', resolvesTo: '93.184.216.34'), 'proxy');
    expect(_go(c, ip: '10.130.4.5'), 'direct');
  });

  test('домены из списков по-прежнему решают раньше адресов', () {
    final c = _config(
      const AppSettings(
        directRules: '10.130.0.0/16',
        proxyRules: 'intranet.corp',
      ),
    );
    expect(_go(c, host: 'intranet.corp', resolvesTo: '10.130.4.5'), 'proxy');
  });

  for (final (finalOutbound, tag) in [
    (AppSettings.finalOutboundProxy, 'proxy'),
    (AppSettings.finalOutboundDirect, 'direct'),
    (AppSettings.finalOutboundBlock, 'block'),
  ]) {
    test('«Всё остальное» = $tag и при резолве, и без адреса', () {
      final c = _config(
        AppSettings(directRules: '10.130.0.0/16', finalOutbound: finalOutbound),
      );
      expect(_go(c, host: 'example.com', resolvesTo: '93.184.216.34'), tag);
      expect(_go(c, host: 'no-such.invalid'), tag);
      expect(_go(c, ip: '93.184.216.34'), tag);
    });
  }

  test('без своих адресов ловушка прежняя, порядок выходов тоже', () {
    final c = _config(
      const AppSettings(
        directRules: 'ru',
        finalOutbound: AppSettings.finalOutboundDirect,
      ),
    );
    expect((c['routing'] as Map)['domainStrategy'], 'AsIs');
    final last = ((c['routing'] as Map)['rules'] as List).last as Map;
    expect(last['network'], 'tcp,udp');
    expect(((c['outbounds'] as List).first as Map)['tag'], 'proxy');
  });

  test('явный IPIfNonMatch без своих адресов тоже резолвит', () {
    final c = _config(
      const AppSettings(
        xrayCore: XrayCoreSettings(routingDomainStrategy: 'IPIfNonMatch'),
        directRules: 'geoip:private',
        finalOutbound: AppSettings.finalOutboundDirect,
      ),
    );
    expect(_go(c, host: 'router.lan', resolvesTo: '192.168.1.1'), 'direct');
    expect(((c['outbounds'] as List).first as Map)['tag'], 'direct');
  });

  group('готовый JSON', () {
    String custom(String strategy) => jsonEncode({
      'outbounds': [
        {
          'tag': 'my-proxy',
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': '203.0.113.10',
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
        {'tag': 'my-direct', 'protocol': 'freedom'},
      ],
      'routing': {
        'domainStrategy': strategy,
        'rules': [
          {
            'type': 'field',
            'ip': ['10.130.0.0/16'],
            'outboundTag': 'my-direct',
          },
        ],
      },
    });

    Map<String, dynamic> build(String strategy, String finalOutbound) {
      Socks5Credentials().init('u', 'p');
      return jsonDecode(
            ConfigGeneratorV2.generateConfig(
              custom(strategy),
              AppSettings(
                directRules: '',
                proxyRules: '',
                blockedRules: '',
                finalOutbound: finalOutbound,
              ),
            ),
          )
          as Map<String, dynamic>;
    }

    test('правило автора по адресу ловит соединение по домену', () {
      final c = build('IPIfNonMatch', AppSettings.finalOutboundProxy);
      expect(
        _go(c, host: 'intranet.corp', resolvesTo: '10.130.4.5'),
        'my-direct',
      );
      expect(
        _go(c, host: 'example.com', resolvesTo: '93.184.216.34'),
        'my-proxy',
      );
    });

    test('«Всё остальное = напрямую» и для домена без адреса', () {
      final c = build('IPIfNonMatch', AppSettings.finalOutboundDirect);
      expect(_go(c, host: 'no-such.invalid'), 'my-direct');
      expect(
        _go(c, host: 'example.com', resolvesTo: '93.184.216.34'),
        'my-direct',
      );
    });

    test('при авторском AsIs всё как было', () {
      final c = build('AsIs', AppSettings.finalOutboundDirect);
      final last = ((c['routing'] as Map)['rules'] as List).last as Map;
      expect(last['network'], 'tcp,udp');
      expect(((c['outbounds'] as List).first as Map)['tag'], 'my-proxy');
    });
  });
}
