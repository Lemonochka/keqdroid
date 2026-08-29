import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/services/tunnel_session_builder.dart';
import 'package:keqdroid/tunnel/connection_mode.dart';
import 'package:keqdroid/tunnel/vpn_backend.dart';

void main() {
  group('режим подключения', () {
    const proxy = AppSettings(connectionMode: 'proxy');
    const vpn = AppSettings(connectionMode: 'tun');

    test('на Android выбор пользователя больше не игнорируется', () {
      // До появления режима «прокси» здесь стояло жёсткое `tun`: другого пути
      // на Android не было. Настройка теперь доезжает.
      expect(
        TunnelSessionBuilder.resolveMode(proxy, isAndroid: true),
        ConnectionMode.proxy,
      );
      expect(
        TunnelSessionBuilder.resolveMode(vpn, isAndroid: true),
        ConnectionMode.tun,
      );
    });

    test('AmneziaWG на Android остаётся VPN, что бы ни стояло в настройках', () {
      // libwg-go сам владеет TUN и локального прокси не открывает вовсе —
      // wireproxy, который делает это на десктопе, в APK не входит. Пустить
      // такой сервер в режиме прокси значит подключиться в никуда.
      expect(
        TunnelSessionBuilder.resolveMode(
          proxy,
          vpnBackend: VpnBackend.awg,
          isAndroid: true,
        ),
        ConnectionMode.tun,
      );
    });

    test('на десктопе AmneziaWG в прокси-режиме остаётся прокси', () {
      // Там за него отвечает wireproxy: он и есть локальный SOCKS/HTTP.
      expect(
        TunnelSessionBuilder.resolveMode(
          proxy,
          vpnBackend: VpnBackend.awg,
          isAndroid: false,
        ),
        ConnectionMode.proxy,
      );
    });

    test('незнакомое значение в настройках читается как VPN', () {
      expect(
        TunnelSessionBuilder.resolveMode(
          const AppSettings(connectionMode: 'нечто'),
          isAndroid: true,
        ),
        ConnectionMode.tun,
      );
    });
  });
}
