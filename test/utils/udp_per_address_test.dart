import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/desktop_tun.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// Переключатель «UDP по маршрутам для каждого адреса»: ядра включают раздельные
/// UDP-потоки по метке в конфиге (xray — выход keq-udp-per-exit, mihomo —
/// ключ keqdroid-udp-per-exit). Выключен — конфиг прежний.
const _link =
    'vless://00000000-0000-4000-8000-000000000000@198.51.100.10:443'
    '?type=tcp&security=reality&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    '&sni=www.microsoft.com&fp=chrome&flow=xtls-rprx-vision#test';

const _on = AppSettings(xrayCore: XrayCoreSettings(udpPerAddress: true));

List<Map<String, dynamic>> _xrayOutbounds(String json) =>
    ((jsonDecode(json) as Map)['outbounds'] as List)
        .cast<Map<String, dynamic>>();

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  test('по умолчанию выключен', () {
    expect(const XrayCoreSettings().udpPerAddress, isFalse);
    expect(XrayCoreSettings.fromJson(const {}).udpPerAddress, isFalse);
    expect(
      XrayCoreSettings.fromJson(_on.xrayCore.toJson()).udpPerAddress,
      isTrue,
    );
  });

  group('xray', () {
    bool marked(List<Map<String, dynamic>> outbounds) => outbounds.any(
      (o) =>
          o['tag'] == ConfigGeneratorV2.udpPerExitTag &&
          o['protocol'] == 'blackhole',
    );

    test('выключен — метки нет', () {
      expect(
        marked(
          _xrayOutbounds(
            ConfigGeneratorV2.generateConfig(_link, const AppSettings()),
          ),
        ),
        isFalse,
      );
    });

    test('включён — выход-метка, на который ничего не ведёт', () {
      final json = ConfigGeneratorV2.generateConfig(_link, _on);
      expect(marked(_xrayOutbounds(json)), isTrue);
      final rules = ((jsonDecode(json) as Map)['routing']['rules'] as List);
      expect(
        rules.any(
          (r) => (r as Map)['outboundTag'] == ConfigGeneratorV2.udpPerExitTag,
        ),
        isFalse,
      );
      // первый выход xray основной, метка его место не занимает
      expect(_xrayOutbounds(json).first['tag'], 'proxy');
    });

    test('в пинге метки нет: там один сервер', () {
      final ping = ConfigGeneratorV2.generatePingConfig(
        _link,
        _on,
        socksPort: 10900,
      );
      expect(marked(_xrayOutbounds(ping)), isFalse);
    });

    test('у готового xray-конфига тоже', () {
      const custom = '{"outbounds":[{"protocol":"freedom","tag":"direct"}]}';
      expect(
        marked(_xrayOutbounds(ConfigGeneratorV2.generateConfig(custom, _on))),
        isTrue,
      );
      expect(
        marked(
          _xrayOutbounds(
            ConfigGeneratorV2.generateConfig(custom, const AppSettings()),
          ),
        ),
        isFalse,
      );
    });
  });

  group('mihomo', () {
    Map<String, dynamic> config(AppSettings s) =>
        jsonDecode(MihomoConfigGen.generate(_link, s, socksPort: 2080))
            as Map<String, dynamic>;

    test('ключ только при включённом', () {
      expect(config(_on)['keqdroid-udp-per-exit'], isTrue);
      expect(
        config(const AppSettings()).containsKey('keqdroid-udp-per-exit'),
        isFalse,
      );
    });

    test('у готового clash-конфига тоже', () {
      const clash =
          'proxies:\n'
          '  - {name: a, type: ss, server: 198.51.100.10, port: 8388, cipher: aes-128-gcm, password: p}\n'
          'rules:\n  - MATCH,a\n';
      Map<String, dynamic> custom(AppSettings s) =>
          jsonDecode(MihomoConfigGen.generate(clash, s, socksPort: 2080))
              as Map<String, dynamic>;
      expect(custom(_on)['keqdroid-udp-per-exit'], isTrue);
      expect(
        custom(const AppSettings()).containsKey('keqdroid-udp-per-exit'),
        isFalse,
      );
    });
  });

  // TUN на ПК теперь у самого xray, метка та же, что на Android
  test('xray TUN на ПК: метка на месте', () {
    final json = ConfigGeneratorV2.generateConfig(
      _link,
      _on,
      desktopTun: const DesktopTunOptions(windows: true, mtu: 9000),
    );
    expect(
      _xrayOutbounds(
        json,
      ).any((o) => o['tag'] == ConfigGeneratorV2.udpPerExitTag),
      isTrue,
    );
  });
}
