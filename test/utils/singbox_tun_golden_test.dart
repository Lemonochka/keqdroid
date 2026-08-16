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
  );
}

void main() {
  group('golden: SingBoxTunConfigGen.generate', () {
    _golden('baseline-all-proxy', () => _generate());

    _golden(
      'routing-only-selected',
      () => _generate(
        routingMode: AppRoutingMode.onlySelected,
        managedProcessNames: const ['chrome.exe', 'telegram.exe'],
      ),
    );

    _golden(
      'routing-all-except-selected',
      () => _generate(
        routingMode: AppRoutingMode.allExceptSelected,
        managedProcessNames: const ['chrome.exe', 'telegram.exe'],
      ),
    );

    _golden(
      'kill-switch-on',
      () => _generate(settings: _settings.copyWith(killSwitch: true)),
    );

    _golden(
      'dns-custom-on',
      () => _generate(
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
      () => _generate(
        settings: _settings.copyWith(
          xrayCore: const XrayCoreSettings(dnsUseCustom: false),
        ),
      ),
    );

    _golden(
      'final-outbound-direct',
      () => _generate(
        settings: _settings.copyWith(
          finalOutbound: AppSettings.finalOutboundDirect,
        ),
      ),
    );

    _golden(
      'final-outbound-block',
      () => _generate(
        settings: _settings.copyWith(
          finalOutbound: AppSettings.finalOutboundBlock,
        ),
      ),
    );

    _golden(
      'local-socks-no-auth',
      // Путь AmneziaWG: wireproxy отдаёт SOCKS5 без auth.
      () => _generate(localSocksNoAuth: true),
    );

    _golden(
      'app-process-name',
      // Свой exe уходит direct, иначе пинги мерили бы задержку через сервер.
      () => _generate(appProcessName: 'keqdroid.exe'),
    );

    _golden(
      'geosite-tokens',
      // geo-токены sing-box не исполняет: .dat читает встроенный xray, и правило
      // должно уехать к нему, а не осесть в ip_cidr.
      () => _generate(
        settings: _settings.copyWith(
          proxyRules: 'geosite:google, proxy.example',
          directRules: 'geosite:private, direct.example',
        ),
      ),
    );
  });
}

/// Один кейс: сгенерировать, сравнить с файлом, при `UPDATE_GOLDEN=1` — перезаписать.
void _golden(String name, String Function() generate) {
  test(name, () {
    final file = File('$_fixtureDir/$name.json');
    final actual = generate();

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
