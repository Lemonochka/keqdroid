import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/tunnel/app_routing_mode.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/desktop_tun.dart';
import 'package:keqdroid/utils/owner_guard.dart';
import 'package:keqdroid/utils/proxy_chain.dart';
import 'package:keqdroid/utils/route_servers.dart';
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
      // alpn задан парой h2+http/1.1 намеренно: панели её выдают, а websocket
      // на h2 не поднимается — в фикстуре обязан остаться один http/1.1.
      return ConfigGeneratorV2.generateConfig(
        'vless://$_uuid@198.51.100.11:443?type=ws&security=tls'
        '&sni=ws.example&host=ws.example&path=%2Fpath&alpn=h2,http%2F1.1#ws',
        _settings,
      );
    });

    _golden('vless-mux', () {
      // Мультиплексор целиком: включатель плюс все три числа, как они уедут в
      // ядро. Сервер намеренно без vision — с ним concurrency подменяется на
      // -1, и это отдельный случай в config_gen_mux_test.
      return ConfigGeneratorV2.generateConfig(
        'vless://$_uuid@198.51.100.23:443?type=ws&security=tls'
        '&sni=mux.example&host=mux.example&path=%2Fm#mux',
        _settings.copyWith(
          xrayCore: const XrayCoreSettings(muxEnabled: true),
        ),
      );
    });

    _golden('vless-native-tun', () {
      // Туннель держит само ядро: в конфиге появляется tun-инбаунд, всё
      // остальное обязано остаться прежним — локальные порты с паролем,
      // перехват DNS, порядок правил.
      return ConfigGeneratorV2.generateConfig(
        'vless://$_uuid@198.51.100.25:443?type=tcp&security=none#nativetun',
        _settings,
        nativeTunInbound: true,
      );
    });

    // Fake-ip на Android: подменный DNS встаёт перед общими резолверами, пул
    // заводится в корне конфига, снифер tun-инбаунда узнаёт `fakedns`.
    _golden('vless-native-tun-fake-ip', () {
      return ConfigGeneratorV2.generateConfig(
        'vless://$_uuid@198.51.100.25:443?type=tcp&security=none#nativetun',
        _settings.copyWith(fakeIp: true),
        nativeTunInbound: true,
      );
    });

    // Готовый конфиг со своим dns-блоком: авторские серверы остаются на
    // местах, подмена встаёт перед первым общим из них.
    _golden('custom-json-server-fake-ip', () {
      return ConfigGeneratorV2.generateConfig(
        jsonEncode({
          'dns': {
            'servers': [
              {
                'address': 'https://common.dot.dns.yandex.net/dns-query',
                'domains': ['domain:ru'],
                'skipFallback': true,
              },
              '1.1.1.1',
            ],
          },
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'freedom',
              'settings': <String, dynamic>{},
            },
          ],
        }),
        _settings.copyWith(fakeIp: true),
        nativeTunInbound: true,
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

    _golden('vmess-aead-link', () {
      // Второй формат vmess: не base64-json, а ссылка стандарта #716. Раньше
      // такая не декодировалась вовсе и сервер не собирался.
      return ConfigGeneratorV2.generateConfig(
        'vmess://$_uuid@198.51.100.29:443?type=ws&security=tls'
        '&sni=aead.example&host=aead.example&path=%2Faead&encryption=zero'
        '#vmessaead',
        _settings,
      );
    });

    _golden('vmess-httpupgrade', () {
      // httpupgrade и HTTP-маскировка у vmess не собирались вовсе: сборка знала
      // только ws и grpc. Заодно видно `type` — у vmess это заголовок, а не
      // транспорт.
      final vmess = base64.encode(utf8.encode(jsonEncode({
        'v': '2',
        'ps': 'vmess-hu',
        'add': '198.51.100.26',
        'port': '443',
        'id': _uuid,
        'aid': '0',
        'net': 'httpupgrade',
        'type': 'none',
        'host': 'hu.example',
        'path': '/hu',
        'tls': 'tls',
        'sni': 'hu.example',
      })));
      return ConfigGeneratorV2.generateConfig('vmess://$vmess', _settings);
    });

    _golden('trojan-xhttp', () {
      // Тот же транспорт, что и у VLESS выше, — включая `extra`. У trojan он
      // раньше терялся целиком, и сервер отвечал на запрос не той формы.
      return ConfigGeneratorV2.generateConfig(
        'trojan://password@198.51.100.27:443?type=xhttp&security=tls'
        '&sni=tjx.example&path=%2Ftjx&mode=stream-one'
        '&extra=%7B%22xPaddingBytes%22%3A%22100-1000%22%7D#trojanxhttp',
        _settings,
      );
    });

    _golden('trojan-reality', () {
      // Раньше сборка trojan ставила `security: tls` жёстко, и ключи REALITY
      // уезжали в никуда: клиент шёл обычным TLS на подставной сертификат.
      return ConfigGeneratorV2.generateConfig(
        'trojan://password@198.51.100.28:443?type=tcp&security=reality'
        '&sni=decoy.example&pbk=publickey&sid=aabb&fp=chrome#trojanreality',
        _settings,
      );
    });

    _golden('trojan-grpc', () {
      return ConfigGeneratorV2.generateConfig(
        'trojan://password@198.51.100.14:443?type=grpc&security=tls'
        '&sni=grpc.example&serviceName=grpcsvc#trojan',
        _settings,
      );
    });

    _golden('vless-kcp-legacy', () {
      // mKCP по ссылке старого вида: xray 26 снял seed и header из
      // kcpSettings, прежний провод выражается масками mkcp-legacy —
      // шифрование на seed первым, заголовок последним. Порядок проверен
      // трафиком против xray 25.12.8 (PROGRESS.md, G-12).
      return ConfigGeneratorV2.generateConfig(
        'vless://$_uuid@198.51.100.23:443?type=kcp&security=none'
        '&headerType=srtp&seed=kcpseed&mtu=1350&tti=20#kcp',
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

    _golden('hysteria2-udp-noise', () {
      // Тот самый случай, которому фрагментация не помогает: UDP-сервер, резать
      // нечего. Салмандер из ссылки при этом остаётся — шум дописывается следом.
      return ConfigGeneratorV2.generateConfig(
        'hysteria2://password@198.51.100.24:443?mport=20000-20050'
        '&obfs=salamander&obfs-password=obfspass&sni=hy2.example#hy2noise',
        _settings.copyWith(
          xrayCore: const XrayCoreSettings(
            noiseEnabled: true,
            noiseDelay: '5-20',
            noiseReset: '60',
          ),
        ),
      );
    });

    _golden('custom-json-provider-rules', () {
      // правила провайдера всех видов: сайты напрямую и в блок, второй его узел,
      // протокол, своя локалка и catch-all
      return ConfigGeneratorV2.generateConfig(_providerJson, _settings);
    });

    _golden('custom-json-provider-rules-ignored', () {
      return ConfigGeneratorV2.generateConfig(
        _providerJson,
        _settings.copyWith(ignoreProviderRules: true),
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

    // готовый конфиг на туннеле Android: авторские правила между нашими головой и хвостом
    _golden('custom-json-native-tun', () {
      return ConfigGeneratorV2.generateConfig(
        jsonEncode(_customNativeTun),
        _settings,
        nativeTunInbound: true,
      );
    });

    // защита адреса сервера: чужое для VPN соединение из туннеля блокируется первым правилом
    _golden('vless-native-tun-outside-vpn', () {
      return ConfigGeneratorV2.generateConfig(
        'vless://$_uuid@198.51.100.25:443?type=tcp&security=none#nativetun',
        _settings,
        nativeTunInbound: true,
        ownerGuard: OwnerGuard.all,
      );
    });

    // у автора нет blackhole: блок уходит в дописанный keq-block, правило раньше авторских
    _golden('custom-json-native-tun-outside-vpn', () {
      return ConfigGeneratorV2.generateConfig(
        jsonEncode(_customNativeTun),
        _settings,
        nativeTunInbound: true,
        ownerGuard: OwnerGuard.all,
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

    // TUN на ПК держит сам xray: адаптер, маршруты, WFP. Правила по
    // процессам встают впереди всех, IPv6 закрывается перед final.
    _golden('vless-desktop-tun-windows', () {
      return ConfigGeneratorV2.generateConfig(
        'vless://$_uuid@198.51.100.30:443?type=tcp&security=none#pctun',
        _settings,
        desktopTun: const DesktopTunOptions(
          windows: true,
          mtu: 9000,
          strictRoute: true,
          captureIpv6: true,
          udpTimeoutSec: 120,
          routingMode: AppRoutingMode.onlySelected,
          managedProcessNames: [
            'firefox.exe',
            r'C:\Games\Game One\game.exe',
          ],
          appProcessName: 'keqdroid.exe',
        ),
      );
    });

    _golden('vless-desktop-tun-linux', () {
      return ConfigGeneratorV2.generateConfig(
        'vless://$_uuid@198.51.100.31:443?type=tcp&security=none#pctun',
        _settings.copyWith(fakeIp: true),
        desktopTun: const DesktopTunOptions(
          windows: false,
          mtu: 9000,
          captureIpv6: true,
          appProcessName: 'keqdroid',
          systemResolvers: ['192.168.1.1/32'],
        ),
      );
    });

    _golden('custom-json-desktop-tun', () {
      return ConfigGeneratorV2.generateConfig(
        jsonEncode({
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {
                'address': '198.51.100.32',
                'port': 443,
                'id': _uuid,
                'encryption': 'none',
              },
              'streamSettings': {'network': 'tcp', 'security': 'tls'},
            },
          ],
        }),
        _settings,
        desktopTun: const DesktopTunOptions(
          windows: true,
          mtu: 9000,
          routingMode: AppRoutingMode.allExceptSelected,
          managedProcessNames: ['steam.exe'],
          appProcessName: 'keqdroid.exe',
        ),
      );
    });
  });

  group('golden: серверы маршрутов', () {
    _golden('route-server-link', () {
      return ConfigGeneratorV2.generateConfig(
        'vless://$_uuid@198.51.100.33:443?type=tcp&security=none#active',
        _settings,
        routeServers: const [_routeLink],
      );
    });

    _golden('custom-json-route-server-link', () {
      return ConfigGeneratorV2.generateConfig(
        jsonEncode(_customNativeTun),
        _settings,
        nativeTunInbound: true,
        routeServers: const [_routeLink],
      );
    });

    // из готового конфига только его выходы, теги наши: у автора proxy, как у сессии
    _golden('route-server-custom-json', () {
      return ConfigGeneratorV2.generateConfig(
        'vless://$_uuid@198.51.100.33:443?type=tcp&security=none#active',
        _settings,
        nativeTunInbound: true,
        routeServers: [_routeJson],
      );
    });

    _golden('custom-json-route-server-custom-json', () {
      return ConfigGeneratorV2.generateConfig(
        jsonEncode(_customNativeTun),
        _settings,
        nativeTunInbound: true,
        routeServers: [_routeJson],
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

    _golden('ping-reality-xhttp', () {
      return ConfigGeneratorV2.generatePingConfig(
        'vless://$_uuid@198.51.100.25:443?type=xhttp&security=reality'
        '&sni=decoy.example&pbk=publickey&sid=aabb&fp=chrome&path=%2Fx#ping',
        _settings,
        socksPort: 28150,
        resolvedServerIp: '198.51.100.25',
        httpInbound: true,
      );
    }, compact: true);

    _golden('ping-fragment', () {
      return ConfigGeneratorV2.generatePingConfig(
        'vless://$_uuid@198.51.100.26:443?type=ws&security=tls'
        '&sni=ws.example&host=ws.example&path=%2Fw#ping',
        _settings.copyWith(
          xrayCore: const XrayCoreSettings(fragmentEnabled: true),
        ),
        socksPort: 28150,
        httpInbound: true,
      );
    }, compact: true);

    _golden('ping-chain', () {
      return ConfigGeneratorV2.generatePingConfig(
        ProxyChainConfig(
          name: 'chain',
          hops: [
            ProxyChainHop(
              config: 'vless://$_uuid@198.51.100.27:443?type=tcp&security=reality'
                  '&sni=decoy.example&pbk=publickey&sid=aabb&fp=chrome#hop1',
            ),
            const ProxyChainHop(
              config: 'trojan://pass@198.51.100.28:8443?sni=tr.example&type=ws&path=%2Fw#hop2',
            ),
          ],
        ).encode(),
        _settings,
        socksPort: 28150,
        httpInbound: true,
      );
    }, compact: true);

    _golden('ping-custom-json', () {
      return ConfigGeneratorV2.generatePingConfig(
        jsonEncode({
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': '198.51.100.29',
                    'port': 443,
                    'users': [
                      {'id': _uuid, 'encryption': 'none'},
                    ],
                  },
                ],
              },
              'streamSettings': {
                'network': 'tcp',
                'sockopt': {'dialerProxy': 'front'},
              },
            },
            {
              'tag': 'front',
              'protocol': 'freedom',
              'settings': <String, dynamic>{},
            },
            {
              'tag': 'drop',
              'protocol': 'blackhole',
            },
          ],
        }),
        _settings,
        socksPort: 28150,
        httpInbound: true,
      );
    }, compact: true);

    _golden('ping-hysteria2', () {
      return ConfigGeneratorV2.generatePingConfig(
        'hysteria2://password@198.51.100.30:443?sni=hy2.example#ping',
        _settings,
        socksPort: 28150,
        httpInbound: true,
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

const _routeLink = RouteServerOutbound(
  tag: 'keq-srv-0',
  serverId: 'de',
  config: 'trojan://password@198.51.100.34:443?security=tls&sni=de.example#de',
  address: '198.51.100.34',
  entries: 'route.example, geoip:de',
);

final _routeJson = RouteServerOutbound(
  tag: 'keq-srv-0',
  serverId: 'warp',
  config: jsonEncode({
    'dns': {
      'servers': ['9.9.9.9'],
    },
    'outbounds': [
      {
        'tag': 'proxy',
        'protocol': 'wireguard',
        'settings': {
          'secretKey': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEA=',
          'address': ['172.16.0.2/32'],
          'mtu': 1280,
          'peers': [
            {
              'endpoint': '198.51.100.35:4500',
              'publicKey': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIA=',
            },
          ],
        },
        'streamSettings': {
          'sockopt': {'dialerProxy': 'noise-out'},
        },
      },
      {
        'tag': 'noise-out',
        'protocol': 'freedom',
        'settings': {
          'noises': [
            {'type': 'rand', 'packet': '10-20', 'delay': '1-2'},
          ],
        },
      },
      {'tag': 'direct', 'protocol': 'freedom'},
    ],
    'routing': {
      'rules': [
        {'type': 'field', 'port': '53', 'outboundTag': 'direct'},
        {'type': 'field', 'network': 'tcp,udp', 'outboundTag': 'proxy'},
      ],
    },
  }),
  address: '198.51.100.35',
  entries: 'route.example, geoip:de',
);

const _customNativeTun = {
  'outbounds': [
    {
      'tag': 'proxy',
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {
            'address': '198.51.100.24',
            'port': 443,
            'users': [
              {'id': _uuid, 'encryption': 'none'},
            ],
          },
        ],
      },
    },
    {'tag': 'direct', 'protocol': 'freedom'},
  ],
  'routing': {
    'rules': [
      {
        'type': 'field',
        'domain': ['domain:author.example'],
        'outboundTag': 'direct',
      },
      {
        'type': 'field',
        'port': '53',
        'outboundTag': 'direct',
      },
    ],
  },
};

/// Готовый конфиг провайдера с его правилами, как их отдают подписки.
final _providerJson = jsonEncode({
  'routing': {
    'domainStrategy': 'IPIfNonMatch',
    'rules': [
      {'type': 'field', 'ip': ['::/0'], 'outboundTag': 'block'},
      {'type': 'field', 'protocol': ['bittorrent'], 'outboundTag': 'direct'},
      {'type': 'field', 'ip': ['geoip:private'], 'outboundTag': 'direct'},
      {'type': 'field', 'domain': ['geosite:private', 'domain:provider-direct.example'], 'outboundTag': 'direct'},
      {'type': 'field', 'domain': ['domain:provider-block.example'], 'outboundTag': 'block'},
      {'type': 'field', 'domain': ['domain:video.example'], 'outboundTag': 'proxy-fast'},
      {'type': 'field', 'port': '0-65535', 'outboundTag': 'direct'},
    ],
  },
  'outbounds': [
    {
      'tag': 'proxy',
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {
            'address': '198.51.100.40',
            'port': 443,
            'users': [
              {'id': _uuid, 'encryption': 'none'},
            ],
          },
        ],
      },
      'streamSettings': {'network': 'tcp', 'security': 'reality', 'realitySettings': {'serverName': 'decoy.example', 'publicKey': 'publickey', 'shortId': 'aabb', 'fingerprint': 'chrome'}},
    },
    {
      'tag': 'proxy-fast',
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {
            'address': '198.51.100.41',
            'port': 443,
            'users': [
              {'id': _uuid, 'encryption': 'none'},
            ],
          },
        ],
      },
      'streamSettings': {'network': 'tcp', 'security': 'reality', 'realitySettings': {'serverName': 'decoy.example', 'publicKey': 'publickey', 'shortId': 'aabb', 'fingerprint': 'chrome'}},
    },
    {'tag': 'direct', 'protocol': 'freedom'},
    {'tag': 'block', 'protocol': 'blackhole'},
  ],
});
