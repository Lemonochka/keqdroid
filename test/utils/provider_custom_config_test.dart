import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/geo_asset_index.dart';

/// Реальный конфиг из подписки: провайдер отдаёт его вместо ссылки, когда
/// клиент представился Happ. Всё, ради чего такой сервер и берут, лежит здесь:
/// свой dns, длинный белый список РФ-доменов на `direct`, `geoip:private` и
/// `domainStrategy`. Проверяем, что после сборки сессии это доезжает до ядра
/// целиком и ни одно правило не начинает указывать в несуществующий тег.
const _providerConfig = '''
{
  "dns": { "servers": ["1.1.1.1", "1.0.0.1"] },
  "routing": {
    "rules": [
      {
        "domain": [
          "domain:gosuslugi.ru",
          "domain:vk.com",
          "domain:yandex.ru",
          "domain:wildberries.ru",
          "domain:xn--80ajghhoc2aj1c8b.xn--p1ai"
        ],
        "outboundTag": "direct"
      },
      { "ip": ["geoip:private"], "outboundTag": "direct" },
      { "domain": ["geosite:private"], "outboundTag": "direct" }
    ],
    "domainStrategy": "IPIfNonMatch"
  },
  "inbounds": [
    {
      "tag": "socks", "port": 10808, "listen": "127.0.0.1", "protocol": "socks",
      "settings": { "udp": true }
    },
    {
      "tag": "http", "port": 10809, "listen": "127.0.0.1", "protocol": "http"
    }
  ],
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "185.22.235.13",
            "port": 8443,
            "users": [{"id": "716e3485-d4f9-4471-9660-fb4b0b838100", "encryption": "none", "flow": ""}]
          }
        ]
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": { "serviceName": "xyz", "authority": "", "mode": false },
        "security": "reality",
        "realitySettings": {
          "serverName": "ads.x5.ru",
          "publicKey": "Jx3-T6hnOqY0JL3XrKReYOZk7XAcHr-julwYzBcXzj0",
          "fingerprint": "chrome"
        }
      }
    },
    { "tag": "direct", "protocol": "freedom" },
    { "tag": "block", "protocol": "blackhole" }
  ],
  "remarks": "WHITE BOSS MOUSER (+TORRENT)"
}
''';

Map<String, dynamic> _routing(Map<String, dynamic> config) =>
    (config['routing'] as Map).cast<String, dynamic>();

List<Map<String, dynamic>> _rules(Map<String, dynamic> config) => [
      for (final r in _routing(config)['rules'] as List)
        (r as Map).cast<String, dynamic>(),
    ];

Set<String> _outboundTags(Map<String, dynamic> config) => {
      for (final o in config['outbounds'] as List)
        if ((o as Map)['tag'] != null) o['tag'] as String,
    };

void main() {
  final server = ServerItem.fromRaw(_providerConfig);

  Map<String, dynamic> build({AppSettings settings = const AppSettings()}) =>
      jsonDecode(
        ConfigGeneratorV2.generateConfig(server.config, settings),
      ) as Map<String, dynamic>;

  group('provider custom config', () {
    test('is recognised as a ready-made Xray server', () {
      expect(server.protocol, 'custom');
      expect(server.address, '185.22.235.13');
      expect(server.port, 8443);
      expect(server.displayName, contains('WHITE BOSS MOUSER'));
    });

    test("the author's dns and domainStrategy survive untouched", () {
      final config = build();

      // Авторские резолверы первые и нетронутые; за ними наш резерв на случай,
      // когда до авторских не достучаться (см. CustomXrayConfig.mergeDns).
      expect(
        ((config['dns'] as Map)['servers'] as List).take(2),
        ['1.1.1.1', '1.0.0.1'],
      );
      expect(_routing(config)['domainStrategy'], 'IPIfNonMatch');
    });

    test("the author's rules stay, in order, with their outbound tags", () {
      final rules = _rules(build());

      final whitelist = rules.firstWhere(
        (r) => (r['domain'] as List?)?.contains('domain:gosuslugi.ru') ?? false,
      );
      expect(whitelist['outboundTag'], 'direct');
      // Пуникод не должен пострадать по дороге.
      expect(
        whitelist['domain'],
        contains('domain:xn--80ajghhoc2aj1c8b.xn--p1ai'),
      );

      expect(
        rules.any((r) =>
            ((r['ip'] as List?) ?? const []).contains('geoip:private') &&
            r['outboundTag'] == 'direct'),
        isTrue,
      );
      expect(
        rules.any((r) =>
            ((r['domain'] as List?) ?? const []).contains('geosite:private') &&
            r['outboundTag'] == 'direct'),
        isTrue,
      );
    });

    test('every rule points at an outbound that actually exists', () {
      // Правило с несуществующим тегом роняет разбор ВСЕГО конфига, и
      // подключение умирает безымянным «SOCKS port not ready».
      final config = build();
      final tags = _outboundTags(config);

      for (final rule in _rules(config)) {
        expect(tags, contains(rule['outboundTag']), reason: 'rule: $rule');
      }
    });

    test("our own rules reuse the author's direct/block, not invented tags", () {
      // Свои freedom/blackhole дописываются, только если у автора их нет.
      // Здесь есть оба — лишних аутбаундов появиться не должно. Кроме
      // `dns`-аутбаунда: перехват DNS у автора висел на его же инбаунде, а
      // инбаунды мы заменяем своими.
      final config = build(
        settings: const AppSettings(
          directRules: 'example-direct.com',
          blockedRules: 'example-block.com',
        ),
      );
      final rules = _rules(config);

      expect(
        _outboundTags(config),
        unorderedEquals(<String>{'proxy', 'direct', 'block', 'keq-dns-out'}),
      );
      expect(
        rules.firstWhere(
          (r) => ((r['domain'] as List?) ?? const [])
              .any((d) => '$d'.contains('example-direct.com')),
        )['outboundTag'],
        'direct',
      );
      expect(
        rules.firstWhere(
          (r) => ((r['domain'] as List?) ?? const [])
              .any((d) => '$d'.contains('example-block.com')),
        )['outboundTag'],
        'block',
      );
    });

    test('the provider whitelist wins over the app routing lists', () {
      // Ради этой раскладки готовый конфиг и берут: провайдер уже решил, что
      // vk.com идёт напрямую. Список приложения не должен её перебивать.
      final rules = _rules(
        build(settings: const AppSettings(proxyRules: 'vk.com')),
      );

      // Наше правило узнаём по ruleTag: домен в нём нормализуется к той же
      // форме `domain:vk.com`, что и у автора, и по тексту они неразличимы.
      final ours = rules.indexWhere((r) => r['ruleTag'] == 'user-proxy-domains');
      final authors = rules.indexWhere(
        (r) =>
            r['ruleTag'] == null &&
            ((r['domain'] as List?) ?? const []).contains('domain:vk.com'),
      );

      expect(ours, isNonNegative);
      expect(rules[ours]['domain'].toString(), contains('vk.com'));
      expect(rules[ours]['outboundTag'], 'proxy');
      expect(authors, isNonNegative);
      expect(authors, lessThan(ours));
    });

    test('what the provider did not name still follows the app lists', () {
      // Обратная сторона того же порядка: у автора нет catch-all, поэтому всё
      // неназванное им по-прежнему решают настройки приложения — иначе смена
      // порядка превратила бы их в мёртвые.
      final rules = _rules(
        build(settings: const AppSettings(blockedRules: 'ads.example.org')),
      );
      final ours = rules.firstWhere(
        (r) => r['ruleTag'] == 'user-block-domains',
      );

      expect(ours['domain'], ['domain:ads.example.org']);
      expect(ours['outboundTag'], 'block');
      // И всё это по-прежнему раньше финального правила.
      expect(rules.last['ruleTag'], 'final');
    });

    test('LAN protection stays ahead of the author rules', () {
      // Единственное, что нельзя пускать после авторских правил. Инбаунд
      // LAN-прокси слушает 0.0.0.0, а `lan-deny` отсекает всё, что пришло в
      // него снаружи локальной сети. Пропусти вперёд авторское правило — и
      // запрос из интернета, попавший под него, уедет в туннель раньше
      // запрета, то есть прокси станет открытым.
      final rules = _rules(build(settings: const AppSettings(lanSharing: true)));
      final tags = rules.map((r) => r['ruleTag']).toList();

      final deny = tags.indexOf('lan-deny');
      final firstAuthor = rules.indexWhere((r) => r['ruleTag'] == null);

      expect(tags.indexOf('lan-allow'), isNonNegative);
      expect(deny, isNonNegative);
      expect(deny, lessThan(firstAuthor));
    });

    test('the app inbounds replace the ones from the subscription', () {
      // Порты автора (10808/10809) ждёт его клиент, а не наша нативная часть.
      final inbounds = [
        for (final i in build()['inbounds'] as List) (i as Map),
      ];
      final ports = inbounds.map((i) => i['port']).toSet();

      expect(ports, isNot(contains(10808)));
      expect(ports, isNot(contains(10809)));
      expect(ports, contains(const AppSettings().localPort));
    });

    test('the author has no catch-all, so ours becomes the final word', () {
      final rules = _rules(build());

      expect(rules.last['ruleTag'], 'final');
      expect(rules.last['outboundTag'], 'proxy');
      expect(
        _rules(build(settings: const AppSettings(finalOutbound: 'direct')))
            .last['outboundTag'],
        'direct',
      );
    });
  });

  group('bundled geo bases', () {
    // geoip:private / geosite:private вычищаются из конфига, если кода нет в
    // наших .dat, — и белый список «локалка мимо туннеля» тихо перестаёт
    // работать. Проверяем по тем самым файлам, что кладутся в сборку.
    test('know the private code both rules rely on', () async {
      final index = await GeoAssetIndex.fromDirectory(
        'assets${Platform.pathSeparator}bin${Platform.pathSeparator}windows',
      );

      expect(index.isEmpty, isFalse, reason: 'geo .dat files must be readable');
      expect(index.geoipCodes, contains('private'));
      expect(index.geositeCodes, contains('private'));
    });
  });
}
