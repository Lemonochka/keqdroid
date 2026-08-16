import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// Побайтовая отсечка на форму конфига целиком.
///
/// Остальные `config_gen_*_test.dart` проверяют отдельные поля — что reality
/// получил `publicKey`, что пустой fingerprint не уехал в ядро. Ни один из них
/// не заметит, если правила роутинга поменяются местами или пропадёт инбаунд, а
/// для xray порядок правил — это и есть маршрутизация.
///
/// Поэтому здесь фиксируется вывод целиком. Тест намеренно тупой: сгенерировать,
/// сравнить со снятым ранее файлом, упасть на первом разошедшемся байте.
///
/// **Фикстуры фиксируют поведение как есть, а не как правильно.** Если при
/// снятии вылезло что-то странное — это находка, её место в отчёте, а не в
/// подправленной руками фикстуре.
///
/// Перегенерация после осознанного изменения генератора:
///
/// ```
/// UPDATE_GOLDEN=1 flutter test test/utils/config_gen_golden_test.dart
/// ```
///
/// Дифф перегенерированных файлов обязан быть прочитан глазами: он показывает
/// ровно то, что изменилось в конфиге у пользователей.
const _fixtureDir = 'test/fixtures/config_gen';

/// Настройки задаются явно, включая те, что совпадают с дефолтом.
///
/// `AppSettings()` берёт списки правил из `RoutingPresets`, а те живут своей
/// жизнью и правятся при каждом обновлении geo-баз. Оставь их неявными — и
/// фикстуры начнут краснеть от чужих правок, ничего не сообщая о генераторе.
/// Списки здесь короткие и синтетические: задача фикстуры — поймать
/// перестановку правил, а не воспроизвести боевой пресет.
const _settings = AppSettings(
  localPort: 2080,
  httpPort: 2081,
  directRules: 'direct.example, 10.10.0.0/16',
  proxyRules: 'proxy.example, geosite:google',
  blockedRules: 'ads.example, geosite:category-ads-all',
  finalOutbound: AppSettings.finalOutboundProxy,
  lanSharing: false,
  lanSocksPort: 1080,
  lanHttpPort: 8080,
  lanUsername: '',
  lanPassword: '',
  xrayCore: XrayCoreSettings(),
);

/// Синтетика: ни один адрес/UUID/пароль ниже не должен быть настоящим.
const _uuid = '00000000-0000-4000-8000-000000000000';

void main() {
  setUp(() {
    // Генератор читает креды синглтоном при сборке инбаундов.
    Socks5Credentials().init('u', 'p');
  });

  group('golden: generateConfig', () {
    _golden('vless-reality-tcp', () {
      return ConfigGeneratorV2.generateConfig(
        'vless://$_uuid@198.51.100.10:443?type=tcp&security=reality'
        '&sni=decoy.example&pbk=publickey&sid=aabb&fp=chrome&flow=xtls-rprx-vision'
        '#reality',
        _settings,
      );
    });

    _golden('vless-tls-ws', () {
      return ConfigGeneratorV2.generateConfig(
        'vless://$_uuid@198.51.100.11:443?type=ws&security=tls'
        '&sni=ws.example&host=ws.example&path=%2Fpath#ws',
        _settings,
      );
    });

    _golden('vless-xhttp-extra', () {
      return ConfigGeneratorV2.generateConfig(
        'vless://$_uuid@198.51.100.12:443?type=xhttp&security=reality'
        '&sni=decoy.example&pbk=publickey&sid=aa&fp=randomized&path=%2F&mode=auto'
        '&extra=%7B%22xPaddingBytes%22%3A%2292-1412%22%2C%22noGRPCHeader%22%3Atrue%7D'
        '#xhttp',
        _settings,
      );
    });

    _golden('vmess-ws-tls', () {
      // vmess прячет параметры в base64-json, а не в query.
      final vmess = base64.encode(utf8.encode(jsonEncode({
        'v': '2',
        'ps': 'vmess',
        'add': '198.51.100.13',
        'port': '443',
        'id': _uuid,
        'aid': '0',
        'net': 'ws',
        'type': 'none',
        'host': 'vmess.example',
        'path': '/vmess',
        'tls': 'tls',
        'sni': 'vmess.example',
      })));
      return ConfigGeneratorV2.generateConfig('vmess://$vmess', _settings);
    });

    _golden('trojan-grpc', () {
      return ConfigGeneratorV2.generateConfig(
        'trojan://password@198.51.100.14:443?type=grpc&security=tls'
        '&sni=grpc.example&serviceName=grpcsvc#trojan',
        _settings,
      );
    });

    _golden('shadowsocks-sip002', () {
      final userInfo = base64Url.encode(utf8.encode('aes-256-gcm:password'));
      return ConfigGeneratorV2.generateConfig(
        'ss://$userInfo@198.51.100.15:8388#ss',
        _settings,
      );
    });

    _golden('hysteria2-mport-obfs', () {
      return ConfigGeneratorV2.generateConfig(
        'hysteria2://password@198.51.100.16:443?mport=20000-20050'
        '&obfs=salamander&obfs-password=obfspass&sni=hy2.example#hy2',
        _settings,
      );
    });

    _golden('custom-json-server', () {
      // Готовый конфиг как сервер: инбаунды остаются наши, аутбаунды провайдера.
      return ConfigGeneratorV2.generateConfig(
        jsonEncode({
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'freedom',
              'settings': <String, dynamic>{},
            },
          ],
        }),
        _settings,
      );
    });

    _golden('lan-sharing-with-credentials', () {
      return ConfigGeneratorV2.generateConfig(
        'vless://$_uuid@198.51.100.17:443?type=tcp&security=none#lan',
        _settings.copyWith(
          lanSharing: true,
          lanUsername: 'lanuser',
          lanPassword: 'lanpass',
        ),
      );
    });

    _golden('final-outbound-direct', () {
      return ConfigGeneratorV2.generateConfig(
        'vless://$_uuid@198.51.100.18:443?type=tcp&security=none#direct',
        _settings.copyWith(finalOutbound: AppSettings.finalOutboundDirect),
      );
    });

    _golden('final-outbound-block', () {
      return ConfigGeneratorV2.generateConfig(
        'vless://$_uuid@198.51.100.19:443?type=tcp&security=none#block',
        _settings.copyWith(finalOutbound: AppSettings.finalOutboundBlock),
      );
    });

    _golden('user-ip-rules', () {
      // Свой CIDR в direct-списке поднимает domainStrategy до IPIfNonMatch.
      return ConfigGeneratorV2.generateConfig(
        'vless://$_uuid@198.51.100.20:443?type=tcp&security=none#iprules',
        _settings.copyWith(directRules: '192.0.2.0/24, 203.0.113.7'),
      );
    });
  });

  group('golden: generatePingConfig', () {
    _golden('ping-http-inbound', () {
      return ConfigGeneratorV2.generatePingConfig(
        'vless://$_uuid@198.51.100.21:443?type=tcp&security=none#ping',
        _settings,
        socksPort: 28150,
        httpInbound: true,
      );
    }, compact: true);

    _golden('ping-socks-inbound', () {
      return ConfigGeneratorV2.generatePingConfig(
        'vless://$_uuid@198.51.100.22:443?type=tcp&security=none#ping',
        _settings,
        socksPort: 28150,
        httpInbound: false,
      );
    }, compact: true);
  });
}

/// Один кейс: сгенерировать, сравнить с файлом, при `UPDATE_GOLDEN=1` — перезаписать.
///
/// [compact] — для `generatePingConfig`: он отдаёт JSON без отступов
/// (`jsonEncode`, не `JsonEncoder.withIndent`), а фикстура в одну строку на
/// несколько килобайт нечитаема, и смысл ревью диффа теряется. Такой вывод
/// раскладываем с отступами по обе стороны сравнения. Порядок ключей при этом
/// сохраняется — перестановку правил тест по-прежнему видит.
void _golden(String name, String Function() generate, {bool compact = false}) {
  test(name, () {
    final file = File('$_fixtureDir/$name.json');
    var actual = generate();
    if (compact) {
      actual = const JsonEncoder.withIndent('  ')
          .convert(jsonDecode(actual));
    }

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
    // Пояс поверх .gitattributes: если фикстура всё же приехала с CRLF.
    final expected = file.readAsStringSync().replaceAll('\r\n', '\n');
    expect(actual.replaceAll('\r\n', '\n'), expected);
  });
}
