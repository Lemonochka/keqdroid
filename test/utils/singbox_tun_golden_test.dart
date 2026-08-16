import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/tunnel/app_routing_mode.dart';
import 'package:keqdroid/utils/singbox_tun_config.dart';

/// Побайтовая отсечка на TUN-конфиг целиком — предохранитель под разбор
/// 444-строчного `generate()`.
///
/// Точечных тестов на этот генератор много, но все они смотрят на отдельные
/// ключи. Здесь фиксируется форма: набор правил, их порядок, состав inbound'а и
/// DNS-блока. Цена ошибки тут выше обычной — сломанный TUN-конфиг это
/// «подключилось, но интернета нет», и падает не сборка, а живая машина.
///
/// Фикстуры фиксируют поведение как есть. Странное, найденное при снятии, идёт
/// в отчёт, а не в отредактированный руками файл.
///
/// Перегенерация:
///
/// ```
/// UPDATE_GOLDEN=1 flutter test test/utils/singbox_tun_golden_test.dart
/// ```
///
/// **Платформа задаётся явно, а не берётся из текущей ОС.** Генератор в трёх
/// местах смотрит на `Platform.isWindows`: суффикс `.exe` у имён процессов,
/// лишняя запись `openvpn-gui.exe` и инверсия `strict_route`. Первая редакция
/// этих фикстур снималась на Windows и падала целиком на linux-раннере CI, ничего
/// не сообщая о самом генераторе. Теперь каждый кейс снят в двух вариантах, и оба
/// воспроизводятся на любой машине.
const _fixtureDir = 'test/fixtures/singbox_tun';

/// Явные настройки: `RoutingPresets` живут своей жизнью, и неявные дефолты
/// заставили бы фикстуры краснеть от чужих правок.
const _settings = AppSettings(
  directRules: 'direct.example, 10.10.0.0/16',
  proxyRules: 'proxy.example',
  blockedRules: 'ads.example',
  finalOutbound: AppSettings.finalOutboundProxy,
  killSwitch: false,
  xrayCore: XrayCoreSettings(),
);

/// Общая часть вызова: меняем в кейсах только то, что кейс проверяет.
String _generate({
  required bool windows,
  AppSettings settings = _settings,
  List<String> managedProcessNames = const [],
  AppRoutingMode routingMode = AppRoutingMode.allProxy,
  bool localSocksNoAuth = false,
  String appProcessName = '',
}) {
  return SingBoxTunConfigGen.generate(
    localSocksPort: 2080,
    socksUsername: 'u',
    socksPassword: 'p',
    serverIpToExclude: '198.51.100.10',
    settings: settings,
    managedProcessNames: managedProcessNames,
    routingMode: routingMode,
    localSocksNoAuth: localSocksNoAuth,
    appProcessName: appProcessName,
    windows: windows,
  );
}

void main() {
  group('golden: SingBoxTunConfigGen.generate', () {
    _golden('baseline-all-proxy', (w) => _generate(windows: w));

    _golden(
      'routing-only-selected',
      (w) => _generate(windows: w, 
        routingMode: AppRoutingMode.onlySelected,
        managedProcessNames: const ['chrome.exe', 'telegram.exe'],
      ),
    );

    _golden(
      'routing-all-except-selected',
      (w) => _generate(windows: w, 
        routingMode: AppRoutingMode.allExceptSelected,
        managedProcessNames: const ['chrome.exe', 'telegram.exe'],
      ),
    );

    _golden(
      'kill-switch-on',
      (w) => _generate(windows: w, settings: _settings.copyWith(killSwitch: true)),
    );

    _golden(
      'dns-custom-on',
      (w) => _generate(windows: w, 
        // Адреса в xray-синтаксисе: sing-box их не понимает, и конвертация
        // этого синтаксиса — как раз то, что легко сломать при разборе метода.
        settings: _settings.copyWith(
          xrayCore: const XrayCoreSettings(
            dnsUseCustom: true,
            dnsServers: 'https+local://1.1.1.1/dns-query',
          ),
        ),
      ),
    );

    _golden(
      'dns-custom-off',
      (w) => _generate(windows: w, 
        settings: _settings.copyWith(
          xrayCore: const XrayCoreSettings(dnsUseCustom: false),
        ),
      ),
    );

    _golden(
      'final-outbound-direct',
      (w) => _generate(windows: w, 
        settings: _settings.copyWith(
          finalOutbound: AppSettings.finalOutboundDirect,
        ),
      ),
    );

    _golden(
      'final-outbound-block',
      (w) => _generate(windows: w, 
        settings: _settings.copyWith(
          finalOutbound: AppSettings.finalOutboundBlock,
        ),
      ),
    );

    _golden(
      'local-socks-no-auth',
      // Путь AmneziaWG: wireproxy отдаёт SOCKS5 без auth.
      (w) => _generate(windows: w, localSocksNoAuth: true),
    );

    _golden(
      'app-process-name',
      // Свой exe уходит direct, иначе пинги мерили бы задержку через сервер.
      (w) => _generate(windows: w, appProcessName: 'keqdroid.exe'),
    );

    _golden(
      'geosite-tokens',
      // geo-токены sing-box не исполняет: .dat читает встроенный xray, и правило
      // должно уехать к нему, а не осесть в ip_cidr.
      (w) => _generate(windows: w, 
        settings: _settings.copyWith(
          proxyRules: 'geosite:google, proxy.example',
          directRules: 'geosite:private, direct.example',
        ),
      ),
    );
  });
}

/// Один кейс — две фикстуры, по одной на целевую ОС.
///
/// Обе снимаются и проверяются на любой машине: платформа теперь аргумент
/// генератора, а не свойство раннера. Windows-форма проверяется на linux-CI и
/// наоборот — раньше половина поведения не проверялась нигде.
void _golden(String name, String Function(bool windows) generate) {
  for (final (suffix, windows) in [('windows', true), ('linux', false)]) {
    test('$name ($suffix)', () {
      final file = File('$_fixtureDir/$name.$suffix.json');
      final actual = generate(windows);

      if (Platform.environment['UPDATE_GOLDEN'] == '1') {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(actual);
        return;
      }

      expect(
        file.existsSync(),
        isTrue,
        reason: 'нет фикстуры ${file.path} — сними её: UPDATE_GOLDEN=1 flutter test',
      );
      final expected = file.readAsStringSync().replaceAll('\r\n', '\n');
      expect(actual.replaceAll('\r\n', '\n'), expected);
    });
  }
}
