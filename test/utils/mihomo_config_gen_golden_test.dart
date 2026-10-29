import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/owner_guard.dart';
import 'package:keqdroid/utils/proxy_chain.dart';
import 'package:keqdroid/utils/route_servers.dart';
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

    _golden('vmess-aead-link', () {
      return MihomoConfigGen.generate(
        'vmess://$_uuid@198.51.100.29:443?type=ws&security=tls'
        '&sni=aead.example&host=aead.example&path=%2Faead&encryption=zero'
        '#vmessaead',
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

    _golden('amneziawg', () {
      // Профиль, а не ссылка. Ключи синтетические, но валидные 32-байтные
      // base64: ядро декодирует их на старте.
      return MihomoConfigGen.generate(
        '[Interface]\n'
        'PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEA=\n'
        'Address = 10.8.1.2/32, fd00::2/128\n'
        'DNS = 1.1.1.1\n'
        'Jc = 4\nJmin = 40\nJmax = 70\nS1 = 86\nS2 = 574\n'
        'H1 = 1\nH2 = 2\nH3 = 3\nH4 = 4\n'
        '\n'
        '[Peer]\n'
        'PublicKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIA=\n'
        'Endpoint = 198.51.100.17:51820\n'
        'AllowedIPs = 0.0.0.0/0, ::/0\n'
        'PersistentKeepalive = 25\n',
        _settings,
        socksPort: 2080,
        httpPort: 2081,
      );
    });

    // узлы связаны dialer-proxy, выход остаётся proxy, адреса всех трёх идут напрямую
    _golden('chain-reality-awg-hy2', () {
      return MihomoConfigGen.generate(
        ProxyChainConfig(
          name: 'chain',
          hops: [
            const ProxyChainHop(
              config: 'vless://$_uuid@198.51.100.20:443?type=tcp&security=reality'
                  '&sni=decoy.example&pbk=publickey&sid=aabb&fp=chrome'
                  '&flow=xtls-rprx-vision#entry',
            ),
            const ProxyChainHop(
              config: '[Interface]\n'
                  'PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEA=\n'
                  'Address = 10.8.1.2/32\n'
                  'Jc = 4\nJmin = 40\nJmax = 70\n'
                  '\n'
                  '[Peer]\n'
                  'PublicKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIA=\n'
                  'Endpoint = 198.51.100.21:51820\n'
                  'AllowedIPs = 0.0.0.0/0\n',
            ),
            const ProxyChainHop(
              config: 'hy2://secret@exit.example:8443?sni=exit.example#exit',
            ),
          ],
        ).encode(),
        _settings,
        socksPort: 2080,
        httpPort: 2081,
        resolvedServerIp: '198.51.100.20',
      );
    });

    // туннель Android: дескриптор держит VpnService, ядро его только читает
    _golden('android-tun', () {
      return MihomoConfigGen.generate(
        'vless://$_uuid@198.51.100.22:443?type=tcp&security=none#androidtun',
        _settings,
        socksPort: 2080,
        httpPort: 2081,
        tun: _androidTun,
      );
    });

    // авторские правила остаются после наших
    _golden('android-tun-custom-clash', () {
      return MihomoConfigGen.generate(
        _clashYaml,
        _settings,
        socksPort: 2080,
        httpPort: 2081,
        tun: _androidTun,
      );
    });

    // защита адреса сервера: правило первым, ключ включает проверку и у DNS-перехвата
    _golden('android-tun-outside-vpn', () {
      return MihomoConfigGen.generate(
        'vless://$_uuid@198.51.100.22:443?type=tcp&security=none#androidtun',
        _settings,
        socksPort: 2080,
        httpPort: 2081,
        tun: _androidTun,
        ownerGuard: OwnerGuard.all,
      );
    });

    _golden('android-tun-custom-clash-outside-vpn', () {
      return MihomoConfigGen.generate(
        _clashYaml,
        _settings,
        socksPort: 2080,
        httpPort: 2081,
        tun: _androidTun,
        ownerGuard: OwnerGuard.all,
      );
    });
  });

  group('golden: правила провайдера в конфиге Clash', () {
    _golden('custom-clash-provider-rules', () {
      return MihomoConfigGen.generate(
        _providerClash,
        _settings,
        socksPort: 2080,
        httpPort: 2081,
      );
    });

    _golden('custom-clash-provider-rules-ignored', () {
      return MihomoConfigGen.generate(
        _providerClash,
        _settings.copyWith(ignoreProviderRules: true),
        socksPort: 2080,
        httpPort: 2081,
      );
    });
  });

  group('golden: серверы маршрутов', () {
    _golden('route-server-link', () {
      return MihomoConfigGen.generate(
        'vless://$_uuid@198.51.100.33:443?type=tcp&security=none#active',
        _settings,
        socksPort: 2080,
        httpPort: 2081,
        routeServers: const [_routeLink],
      );
    });

    _golden('custom-clash-route-server-link', () {
      return MihomoConfigGen.generate(
        _clashYaml,
        _settings,
        socksPort: 2080,
        httpPort: 2081,
        tun: _androidTun,
        routeServers: const [_routeLink],
      );
    });

    // из готового YAML его узлы и группа, имена наши: у автора NL и Proxy, как у активного
    _golden('route-server-custom-clash', () {
      return MihomoConfigGen.generate(
        'vless://$_uuid@198.51.100.33:443?type=tcp&security=none#active',
        _settings,
        socksPort: 2080,
        httpPort: 2081,
        tun: _androidTun,
        routeServers: const [_routeClash],
      );
    });

    _golden('custom-clash-route-server-custom-clash', () {
      return MihomoConfigGen.generate(
        _clashYaml,
        _settings,
        socksPort: 2080,
        httpPort: 2081,
        tun: _androidTun,
        routeServers: const [_routeClash],
      );
    });
  });

  group('golden: MihomoConfigGen.generatePingConfig', () {
    _golden('ping-vless-reality', () {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(
        MihomoConfigGen.generatePingConfig(
          'vless://$_uuid@198.51.100.31:443?type=tcp&security=reality'
          '&sni=decoy.example&pbk=publickey&sid=aabb&fp=chrome#ping',
          _settings,
          socksPort: 28150,
          httpInbound: true,
        ),
      ));
    });
  });
}

const _routeLink = RouteServerOutbound(
  tag: 'keq-srv-0',
  serverId: 'de',
  config: 'trojan://password@198.51.100.34:443?security=tls&sni=de.example#de',
  address: '198.51.100.34',
  entries: 'route.example, geoip:de',
);

const _routeClash = RouteServerOutbound(
  tag: 'keq-srv-0',
  serverId: 'warp',
  config: '''
common: &common
  type: wireguard
  ip: 172.16.0.2
  private-key: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEA=
  public-key: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIA=
  udp: true
  amnezia-wg-option:
    jc: 4
    jmin: 40
    jmax: 70
proxies:
  - name: "NL"
    <<: *common
    server: 198.51.100.35
    port: 4500
  - name: "NL 2408"
    <<: *common
    server: 198.51.100.36
    port: 2408
proxy-groups:
  - name: "Proxy"
    type: url-test
    proxies: ["NL", "NL 2408"]
    url: https://cp.cloudflare.com/
    interval: 300
rules:
  - DST-PORT,53,DIRECT
  - MATCH,Proxy
''',
  address: '198.51.100.35',
  entries: 'route.example, geoip:de',
);

const _androidTun = MihomoTunOptions(
  fromFileDescriptor: true,
  stack: 'gvisor',
  autoRoute: false,
);

const _clashYaml = '''
mode: rule
proxies:
  - name: "NL"
    type: trojan
    server: 198.51.100.23
    port: 443
    password: password
    sni: nl.example
proxy-groups:
  - name: "Proxy"
    type: select
    proxies: ["NL"]
rules:
  - DOMAIN-SUFFIX,author.example,DIRECT
  - DST-PORT,53,DIRECT
  - MATCH,Proxy
''';

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

/// Конфиг Clash провайдера с его правилами всех видов.
const _providerClash = '''
mode: rule
proxies:
  - name: "NL"
    type: trojan
    server: 198.51.100.42
    port: 443
    password: password
    sni: nl.example
  - name: "DE"
    type: trojan
    server: 198.51.100.43
    port: 443
    password: password
    sni: de.example
proxy-groups:
  - name: "Proxy"
    type: select
    proxies: ["NL", "DE"]
rule-providers:
  ads:
    type: http
    behavior: domain
    url: https://provider.example/ads.yaml
    path: ./ads.yaml
rules:
  - DOMAIN-SUFFIX,provider-direct.example,DIRECT
  - GEOSITE,category-ru,DIRECT
  - GEOIP,private,DIRECT,no-resolve
  - IP-CIDR,203.0.113.0/24,REJECT,no-resolve
  - RULE-SET,ads,REJECT
  - AND,((DOMAIN-SUFFIX,quic.example),(NETWORK,UDP)),REJECT
  - DOMAIN-SUFFIX,video.example,DE
  - DST-PORT,53,DIRECT
  - PROCESS-NAME,provider-tool.exe,DIRECT
  - MATCH,DIRECT
''';
