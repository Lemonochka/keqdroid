import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// Побайтовая отсечка на конфиг mihomo целиком — пара к
/// `config_gen_golden_test.dart`, тот же приём и тот же порядок работы.
///
/// Зачем отдельно от `mihomo_config_gen_test.dart`: тот проверяет поля по
/// одному и не заметит ни исчезнувшего инбаунда, ни правил, вставших в другом
/// порядке. У mihomo порядок правил решает так же, как у xray.
///
/// Ссылки взяты те же, что в xray-голденах: один вход, два ядра, и разница
/// между ними видна диффом двух фикстур, а не чтением двух генераторов.
///
/// **Фикстуры фиксируют поведение как есть, а не как правильно.** Странность,
/// вылезшая при снятии, — находка для отчёта, а не повод править файл руками.
///
/// Перегенерация после осознанного изменения генератора:
///
/// ```
/// UPDATE_GOLDEN=1 flutter test test/utils/mihomo_config_gen_golden_test.dart
/// ```
const _fixtureDir = 'test/fixtures/mihomo_gen';

/// Настройки те же, что у xray-голденов, и по той же причине: пресеты
/// `RoutingPresets` живут своей жизнью, а фикстура обязана краснеть только от
/// правок генератора.
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
    Socks5Credentials().init('u', 'p');
  });

  group('golden: MihomoConfigGen.generate', () {
    _golden('vless-reality-tcp', () {
      return MihomoConfigGen.generate(
        'vless://$_uuid@198.51.100.10:443?type=tcp&security=reality'
        '&sni=decoy.example&pbk=publickey&sid=aabb&fp=chrome&flow=xtls-rprx-vision'
        '#reality',
        _settings,
        socksPort: 2080,
        httpPort: 2081,
      );
    });

    _golden('vless-tls-ws', () {
      // alpn парой h2+http/1.1 — как её выдают панели. По websocket h2 не
      // поднимается, и в фикстуре обязан остаться один http/1.1.
      return MihomoConfigGen.generate(
        'vless://$_uuid@198.51.100.11:443?type=ws&security=tls'
        '&sni=ws.example&host=ws.example&path=%2Fpath&alpn=h2,http%2F1.1#ws',
        _settings,
        socksPort: 2080,
        httpPort: 2081,
      );
    });

    _golden('vless-xhttp-extra', () {
      return MihomoConfigGen.generate(
        'vless://$_uuid@198.51.100.12:443?type=xhttp&security=reality'
        '&sni=decoy.example&pbk=publickey&sid=aa&fp=randomized&path=%2F&mode=auto'
        '&extra=%7B%22xPaddingBytes%22%3A%2292-1412%22%2C%22noGRPCHeader%22%3Atrue%7D'
        '#xhttp',
        _settings,
        socksPort: 2080,
        httpPort: 2081,
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
      return MihomoConfigGen.generate(
        'vmess://$vmess',
        _settings,
        socksPort: 2080,
        httpPort: 2081,
      );
    });

    _golden('trojan-reality', () {
      return MihomoConfigGen.generate(
        'trojan://password@198.51.100.28:443?type=tcp&security=reality'
        '&sni=decoy.example&pbk=publickey&sid=aabb&fp=chrome#trojanreality',
        _settings,
        socksPort: 2080,
        httpPort: 2081,
      );
    });

    _golden('trojan-grpc', () {
      return MihomoConfigGen.generate(
        'trojan://password@198.51.100.14:443?type=grpc&security=tls'
        '&sni=grpc.example&serviceName=grpcsvc#trojan',
        _settings,
        socksPort: 2080,
        httpPort: 2081,
      );
    });

    _golden('shadowsocks-sip002', () {
      final userInfo = base64Url.encode(utf8.encode('aes-256-gcm:password'));
      return MihomoConfigGen.generate(
        'ss://$userInfo@198.51.100.15:8388#ss',
        _settings,
        socksPort: 2080,
        httpPort: 2081,
      );
    });

    _golden('hysteria2-mport-obfs', () {
      return MihomoConfigGen.generate(
        'hysteria2://password@198.51.100.16:443?mport=20000-20050'
        '&obfs=salamander&obfs-password=obfspass&sni=hy2.example#hy2',
        _settings,
        socksPort: 2080,
        httpPort: 2081,
      );
    });
  });
}

/// Один кейс: сгенерировать, сравнить с файлом, при `UPDATE_GOLDEN=1` —
/// перезаписать.
///
/// Ни `apiPort`, ни `apiSecret` здесь не передаются намеренно: с ними в конфиг
/// уезжает `external-controller` с секретом, а секрет на каждое подключение
/// свой — фикстура мигала бы, ничего не сообщая о генераторе.
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
    // Пояс поверх .gitattributes: если фикстура всё же приехала с CRLF.
    final expected = file.readAsStringSync().replaceAll('\r\n', '\n');
    expect(actual.replaceAll('\r\n', '\n'), expected);
  });
}
