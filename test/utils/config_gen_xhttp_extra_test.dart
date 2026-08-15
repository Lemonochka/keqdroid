import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// `xhttpSettings.extra` у xray — не «дополнительные поля», а ЗАМЕНА всего
/// блока XHTTP (`SplitHTTPConfig.Build` оставляет от внешнего только host,
/// path и mode). Панели xray 25+ складывают туда все настройки транспорта,
/// поэтому потерянный `extra` — это клиент с дефолтным XHTTP вместо серверного.
Map<String, dynamic> _xhttp(String uri, {AppSettings settings = const AppSettings()}) {
  Socks5Credentials().init('u', 'p');
  final config =
      jsonDecode(ConfigGeneratorV2.generateConfig(uri, settings)) as Map<String, dynamic>;
  final outbound = (config['outbounds'] as List).first as Map<String, dynamic>;
  final stream = outbound['streamSettings'] as Map<String, dynamic>;
  return stream['xhttpSettings'] as Map<String, dynamic>;
}

void main() {
  group('XHTTP extra from share links', () {
    test('extra json rides through to the core verbatim', () {
      final xhttp = _xhttp(
        'vless://uuid@host.example:443?type=xhttp&security=reality'
        '&sni=decoy.example&pbk=k&sid=aa&fp=randomized&path=%2F&mode=auto'
        '&extra=%7B%22xPaddingBytes%22%3A%2292-1412%22%2C%22noGRPCHeader%22%3Atrue%7D',
      );

      expect(xhttp['extra'], {
        'xPaddingBytes': '92-1412',
        'noGRPCHeader': true,
      });
      // host/path/mode остаются снаружи — их xray берёт именно оттуда.
      expect(xhttp['path'], '/');
      expect(xhttp['mode'], 'auto');
    });

    test('flat x_padding_bytes works for links without extra', () {
      final xhttp = _xhttp(
        'vless://uuid@host.example:443?type=xhttp&security=tls&sni=host.example'
        '&path=%2F&x_padding_bytes=100-1000',
      );
      expect(xhttp['extra'], {'xPaddingBytes': '100-1000'});
    });

    test('extra wins over the flat parameter', () {
      final xhttp = _xhttp(
        'vless://uuid@host.example:443?type=xhttp&security=tls&sni=host.example'
        '&x_padding_bytes=1-2&extra=%7B%22xPaddingBytes%22%3A%2292-1412%22%7D',
      );
      expect((xhttp['extra'] as Map)['xPaddingBytes'], '92-1412');
    });

    test('links without either keep no extra key at all', () {
      final xhttp = _xhttp(
        'vless://uuid@host.example:443?type=xhttp&security=tls&sni=host.example&path=%2F',
      );
      expect(xhttp.containsKey('extra'), isFalse);
    });

    test('broken extra json does not take the whole server down with it', () {
      final xhttp = _xhttp(
        'vless://uuid@host.example:443?type=xhttp&security=tls&sni=host.example'
        '&extra=not-json',
      );
      expect(xhttp.containsKey('extra'), isFalse);
      expect(xhttp['path'], '/');
    });

    test('xmux settings merge into the link-supplied extra', () {
      // Обе стороны пишут в один и тот же объект: настройка приложения не
      // должна стирать транспортные параметры сервера, и наоборот.
      final xhttp = _xhttp(
        'vless://uuid@host.example:443?type=xhttp&security=tls&sni=host.example'
        '&extra=%7B%22xPaddingBytes%22%3A%2292-1412%22%7D',
        settings: const AppSettings(
          xrayCore: XrayCoreSettings(xmuxEnabled: true, xmuxMaxConcurrency: '8'),
        ),
      );
      final extra = xhttp['extra'] as Map<String, dynamic>;
      expect(extra['xPaddingBytes'], '92-1412');
      expect((extra['xmux'] as Map)['maxConcurrency'], 8);
    });
  });
}
