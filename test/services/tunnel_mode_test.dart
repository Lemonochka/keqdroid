import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/services/tunnel_session_builder.dart';
import 'package:keqdroid/tunnel/connection_mode.dart';
import 'package:keqdroid/tunnel/vpn_backend.dart';

void main() {
  group('режим подключения', () {
    const proxy = AppSettings(
      connectionMode: 'proxy',
      connectionModeChosen: true,
    );
    const vpn = AppSettings(
      connectionMode: 'tun',
      connectionModeChosen: true,
    );

    test('на Android невыбранный режим читается как VPN, а не как дефолт', () {
      // Дефолт поля — десктопный `proxy`, и до 0.13.0 на Android он лежал в
      // настройках у всех: режим там просто не читался. Уважить его молча —
      // значит выключить туннель каждому, кто обновится.
      const untouched = AppSettings();
      expect(untouched.connectionMode, 'proxy');
      expect(untouched.connectionModeChosen, isFalse);
      expect(
        TunnelSessionBuilder.resolveMode(untouched, isAndroid: true),
        ConnectionMode.tun,
      );
    });

    test('на десктопе невыбранный режим остаётся прокси', () {
      // Там дефолт осмысленный: TUN требует прав администратора, и первое
      // подключение не должно упираться в UAC.
      expect(
        TunnelSessionBuilder.resolveMode(const AppSettings(), isAndroid: false),
        ConnectionMode.proxy,
      );
    });

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
          const AppSettings(
            connectionMode: 'нечто',
            connectionModeChosen: true,
          ),
          isAndroid: true,
        ),
        ConnectionMode.tun,
      );
    });

    test('флаг выбора переживает round-trip через json', () {
      // Иначе он терялся бы на каждом перезапуске, и Android вечно возвращался
      // бы в VPN, сколько ни переключай.
      final saved = proxy.toJson();
      expect(AppSettings.fromJson(saved).connectionModeChosen, isTrue);
      expect(
        AppSettings.fromJson(const {}).connectionModeChosen,
        isFalse,
        reason: 'настройки, записанные до появления флага',
      );
    });
  });
}
