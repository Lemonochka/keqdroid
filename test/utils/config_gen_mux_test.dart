import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/proxy_chain.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// Mux — надстройка над протоколом, а не над транспортом: клиент дозванивается
/// до служебного адреса `v1.mux.cool`, а пачку разбирает сервер. Отсюда все
/// правила ниже: где ядро эту пачку поймёт, там ключ `mux` и появляется, а где
/// не поймёт — не появляется, иначе соединение молча не встанет.
const _mux = AppSettings(
  xrayCore: XrayCoreSettings(muxEnabled: true),
);

const _uuid = '00000000-0000-4000-8000-000000000000';

List<Map<String, dynamic>> _outbounds(
  String uri, {
  AppSettings settings = _mux,
}) {
  Socks5Credentials().init('u', 'p');
  final config =
      jsonDecode(ConfigGeneratorV2.generateConfig(uri, settings)) as Map<String, dynamic>;
  return (config['outbounds'] as List).cast<Map<String, dynamic>>();
}

Map<String, dynamic>? _muxOf(String uri, {AppSettings settings = _mux}) =>
    _outbounds(uri, settings: settings).first['mux'] as Map<String, dynamic>?;

void main() {
  group('куда mux попадает', () {
    test('vless: включатель, оба числа и режим QUIC — как ждёт ядро', () {
      expect(
        _muxOf('vless://$_uuid@host.example:443?type=ws&security=tls&sni=x.example'),
        {
          'enabled': true,
          'concurrency': XrayCoreSettings.defaultMuxConcurrency,
          'xudpConcurrency': XrayCoreSettings.defaultMuxXudpConcurrency,
          'xudpProxyUDP443': XrayCoreSettings.muxUdp443Reject,
        },
      );
    });

    test('vmess и trojan тоже: сервер разбирает mux одинаково для всех', () {
      expect(
        _muxOf('trojan://pass@host.example:443?type=tcp&security=tls&sni=x.example'),
        isNotNull,
      );

      final vmess = base64.encode(utf8.encode(jsonEncode({
        'v': '2',
        'add': 'host.example',
        'port': '443',
        'id': _uuid,
        'net': 'ws',
        'path': '/p',
        'tls': 'tls',
        'sni': 'x.example',
      })));
      expect(_muxOf('vmess://$vmess'), isNotNull);
    });

    test('выключен — ключа нет вовсе, а не «enabled: false»', () {
      expect(
        _muxOf(
          'vless://$_uuid@host.example:443?type=ws&security=tls&sni=x.example',
          settings: const AppSettings(),
        ),
        isNull,
      );
    });
  });

  group('куда mux не попадает', () {
    test('shadowsocks: чужой сервер про v1.mux.cool не знает', () {
      final userInfo = base64Url.encode(utf8.encode('aes-256-gcm:password'));
      expect(_muxOf('ss://$userInfo@host.example:8388'), isNull);
    });

    test('hysteria2: свой датаграммный транспорт, mux ему не нужен', () {
      expect(_muxOf('hysteria2://pass@host.example:443?sni=x.example'), isNull);
    });

    test('xhttp: у него свой мультиплексор внутри транспорта', () {
      expect(
        _muxOf('vless://$_uuid@host.example:443?type=xhttp&security=reality'
            '&sni=decoy.example&pbk=k&sid=aa&fp=chrome&path=%2F'),
        isNull,
      );
      expect(
        _muxOf('vless://$_uuid@host.example:443?type=splithttp&security=tls'
            '&sni=x.example&path=%2F'),
        isNull,
      );
    });

    test('в цепочке mux только на выходном узле', () {
      final outbounds = _outbounds(
        const ProxyChainConfig(
          name: 'hop1 to hop2',
          hops: [
            ProxyChainHop(
              config: 'vless://$_uuid@hop1.example:443'
                  '?type=tcp&security=tls&sni=hop1.example',
            ),
            ProxyChainHop(
              config: 'vless://$_uuid@hop2.example:443'
                  '?type=tcp&security=tls&sni=hop2.example',
            ),
          ],
        ).encode(),
      );
      final proxy = outbounds.firstWhere((o) => o['tag'] == 'proxy');
      expect(proxy['mux'], isNotNull);
      for (final o in outbounds.where((o) => o['tag'] != 'proxy')) {
        expect(o['mux'], isNull, reason: 'узел ${o['tag']}');
      }
    });
  });

  group('vision', () {
    test('с vision TCP из пачки исключается: сервер рвёт всё соединение', () {
      final mux = _muxOf(
        'vless://$_uuid@host.example:443?type=tcp&security=reality'
        '&sni=decoy.example&pbk=k&sid=aa&fp=chrome&flow=xtls-rprx-vision',
      );
      expect(mux?['concurrency'], -1);
      // XUDP при этом остаётся — ради него всё и включают.
      expect(mux?['xudpConcurrency'], XrayCoreSettings.defaultMuxXudpConcurrency);
    });

    test('вариант -udp443 тот же: сервер смотрит на укороченное имя флоу', () {
      expect(
        _muxOf('vless://$_uuid@host.example:443?type=tcp&security=reality'
            '&sni=decoy.example&pbk=k&sid=aa&fp=chrome'
            '&flow=xtls-rprx-vision-udp443')?['concurrency'],
        -1,
      );
    });

    test('без vision число берётся из настроек как есть', () {
      expect(
        _muxOf(
          'vless://$_uuid@host.example:443?type=tcp&security=tls&sni=x.example',
          settings: const AppSettings(
            xrayCore: XrayCoreSettings(muxEnabled: true, muxConcurrency: 4),
          ),
        )?['concurrency'],
        4,
      );
    });
  });

  group('значения подрезаются по границам ядра', () {
    Map<String, dynamic>? withNumbers(int c, int x) => _muxOf(
          'vless://$_uuid@host.example:443?type=tcp&security=tls&sni=x.example',
          settings: AppSettings(
            xrayCore: XrayCoreSettings(
              muxEnabled: true,
              muxConcurrency: c,
              muxXudpConcurrency: x,
            ),
          ),
        );

    test('сверху — 128 и 1024', () {
      final mux = withNumbers(999, 9999);
      expect(mux?['concurrency'], 128);
      expect(mux?['xudpConcurrency'], 1024);
    });

    test('снизу — -1: любое отрицательное значит «не мультиплексировать»', () {
      final mux = withNumbers(-50, -50);
      expect(mux?['concurrency'], -1);
      expect(mux?['xudpConcurrency'], -1);
    });

    test('незнакомый режим QUIC откатывается на reject, а не роняет конфиг', () {
      expect(
        _muxOf(
          'vless://$_uuid@host.example:443?type=tcp&security=tls&sni=x.example',
          settings: const AppSettings(
            xrayCore: XrayCoreSettings(
              muxEnabled: true,
              muxXudpProxyUDP443: 'nonsense',
            ),
          ),
        )?['xudpProxyUDP443'],
        XrayCoreSettings.muxUdp443Reject,
      );
    });
  });
}
