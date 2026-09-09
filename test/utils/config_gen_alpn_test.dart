import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// ws поверх TLS не переживает, если сервер выберет по ALPN h2: апгрейд
/// соединения в websocket идёт только по HTTP/1.1, и рукопожатие умирает молча —
/// снаружи это выглядит как «ссылка не работает».
///
/// Оба ядра подставляют `http/1.1` сами, но только когда alpn в конфиге пуст.
/// Пришедшую из ссылки пару `h2,http/1.1` они оставляют как есть, поэтому
/// сводить её к одному `http/1.1` приходится нам.
///
/// Тесты ниже одинаково важны обеими сторонами: что пара сводится и что всё
/// остальное остаётся нетронутым.
Map<String, dynamic>? _tls(String uri) {
  Socks5Credentials().init('u', 'p');
  final config = jsonDecode(ConfigGeneratorV2.generateConfig(uri, const AppSettings()))
      as Map<String, dynamic>;
  final outbound = (config['outbounds'] as List).first as Map<String, dynamic>;
  final stream = outbound['streamSettings'] as Map<String, dynamic>;
  return stream['tlsSettings'] as Map<String, dynamic>?;
}

Object? _mihomoAlpn(String uri) {
  Socks5Credentials().init('u', 'p');
  final config = MihomoConfigGen.build(uri, const AppSettings(), socksPort: 2080);
  final proxy = (config['proxies'] as List).cast<Map<String, dynamic>>().single;
  return proxy['alpn'];
}

void main() {
  group('xray: ALPN h2 не едет в ws', () {
    test('пара h2,http/1.1 у ws сводится к одному http/1.1', () {
      expect(
        _tls('vless://uuid@host.example:443?type=ws&security=tls'
            '&sni=ws.example&path=%2Fp&alpn=h2,http%2F1.1')?['alpn'],
        ['http/1.1'],
      );
    });

    test('то же для httpupgrade — он тоже поднимается апгрейдом по HTTP/1.1', () {
      expect(
        _tls('vless://uuid@host.example:443?type=httpupgrade&security=tls'
            '&sni=hu.example&path=%2Fp&alpn=h2,http%2F1.1')?['alpn'],
        ['http/1.1'],
      );
    });

    test('trojan и vmess идут своим путём сборки — их тоже чиним', () {
      expect(
        _tls('trojan://pass@host.example:443?type=ws&security=tls'
            '&sni=ws.example&path=%2Fp&alpn=h2,http%2F1.1')?['alpn'],
        ['http/1.1'],
      );

      final vmess = base64.encode(utf8.encode(jsonEncode({
        'v': '2',
        'add': 'host.example',
        'port': '443',
        'id': 'uuid',
        'net': 'ws',
        'host': 'ws.example',
        'path': '/p',
        'tls': 'tls',
        'sni': 'ws.example',
        'alpn': 'h2,http/1.1',
      })));
      expect(_tls('vmess://$vmess')?['alpn'], ['http/1.1']);
    });

    test('одиночный h2 у ws остаётся: это осознанный выбор, не наше дело', () {
      expect(
        _tls('vless://uuid@host.example:443?type=ws&security=tls'
            '&sni=ws.example&path=%2Fp&alpn=h2')?['alpn'],
        ['h2'],
      );
    });

    test('на других транспортах пара не трогается', () {
      for (final type in ['tcp', 'grpc', 'xhttp']) {
        expect(
          _tls('vless://uuid@host.example:443?type=$type&security=tls'
              '&sni=x.example&alpn=h2,http%2F1.1')?['alpn'],
          ['h2', 'http/1.1'],
          reason: 'транспорт $type',
        );
      }
    });

    test('порядок наоборот — не наш случай, оставляем как прислали', () {
      expect(
        _tls('vless://uuid@host.example:443?type=ws&security=tls'
            '&sni=ws.example&alpn=http%2F1.1,h2')?['alpn'],
        ['http/1.1', 'h2'],
      );
    });
  });

  group('mihomo: правим только trojan', () {
    test('trojan ws — пара сводится: alpn из конфига там доезжает до ws', () {
      expect(
        _mihomoAlpn('trojan://pass@host.example:443?type=ws&security=tls'
            '&sni=ws.example&path=%2Fp&alpn=h2,http%2F1.1'),
        ['http/1.1'],
      );
    });

    test('vless ws — не трогаем: ядро на ws-пути ставит http/1.1 само', () {
      expect(
        _mihomoAlpn('vless://uuid@host.example:443?type=ws&security=tls'
            '&sni=ws.example&path=%2Fp&alpn=h2,http%2F1.1'),
        ['h2', 'http/1.1'],
      );
    });

    test('trojan на tcp — пара остаётся', () {
      expect(
        _mihomoAlpn('trojan://pass@host.example:443?type=tcp&security=tls'
            '&sni=x.example&alpn=h2,http%2F1.1'),
        ['h2', 'http/1.1'],
      );
    });
  });
}
