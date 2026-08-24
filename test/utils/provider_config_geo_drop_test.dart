import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/custom_xray_config.dart';
import 'package:keqdroid/utils/geo_asset_index.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// Правило провайдера с geo-кодом, которого нет в наших базах, исчезает из
/// конфига целиком — иначе ядро не стартует вовсе. Само по себе это верно, но
/// трафик такого правила проваливается в НАШ `final`, и с «остальной трафик =
/// блок» перестаёт ходить: `Hit route rule: [final] so taking detour [block]`
/// на живом ядре. Снаружи — «приложение блокирует то, что провайдер пускает
/// через прокси», без единой строчки о причине.
const _providerConfig = '''
{
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "203.0.113.10",
            "port": 443,
            "users": [{"id": "11111111-2222-3333-4444-555555555555"}]
          }
        ]
      }
    },
    {"tag": "direct", "protocol": "freedom"}
  ],
  "routing": {
    "rules": [
      {"type": "field", "ruleTag": "author-known", "ip": ["geoip:telegram"], "outboundTag": "proxy"},
      {"type": "field", "ruleTag": "author-unknown", "ip": ["geoip:sberbank"], "outboundTag": "proxy"}
    ]
  }
}
''';

const _index = GeoAssetIndex(
  geoipCodes: {'telegram', 'ru', 'private'},
  geositeCodes: {'youtube'},
);

List<Map<String, dynamic>> _rulesOf(String generated) =>
    (((jsonDecode(generated) as Map)['routing'] as Map)['rules'] as List)
        .cast<Map<String, dynamic>>();

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  test('авторские правила идут ПЕРЕД списками из настроек', () {
    final generated = ConfigGeneratorV2.generateConfig(
      _providerConfig,
      const AppSettings(
        directRules: 'ru, yandex.ru',
        proxyRules: '',
        blockedRules: '',
      ),
      resolvedServerIp: '203.0.113.10',
      geoIndex: _index,
    );

    final tags = _rulesOf(generated).map((r) => r['ruleTag']).toList();
    final author = tags.indexOf('author-known');
    final ours = tags.indexWhere(
      (t) => t is String && t.startsWith('user-'),
    );

    expect(author, isNot(-1));
    expect(ours, isNot(-1));
    expect(
      author,
      lessThan(ours),
      reason: 'заготовка провайдера важнее списков приложения',
    );
    expect(tags.last, 'final');
  });

  test('правило с неизвестным кодом исчезает целиком', () {
    final generated = ConfigGeneratorV2.generateConfig(
      _providerConfig,
      const AppSettings(),
      resolvedServerIp: '203.0.113.10',
      geoIndex: _index,
    );

    final tags = _rulesOf(generated).map((r) => r['ruleTag']).toList();
    expect(tags, contains('author-known'));
    expect(
      tags,
      isNot(contains('author-unknown')),
      reason: 'ядро выходит на неизвестном коде — правило приходится убрать',
    );
  });

  test('потеря названа заранее: коды и число правил', () {
    final parsed = CustomXrayConfig.tryParse(_providerConfig)!;
    final lost = previewUnknownGeo(parsed.json, _index);

    expect(lost.removedRules, 1);
    expect(lost.tokens, contains('geoip:sberbank'));
    expect(
      jsonDecode(_providerConfig).toString(),
      parsed.json.toString(),
      reason: 'предпросмотр не имеет права трогать сам конфиг',
    );
  });

  test('без индекса баз ничего не выбрасывается', () {
    final parsed = CustomXrayConfig.tryParse(_providerConfig)!;
    final lost = previewUnknownGeo(parsed.json, GeoAssetIndex.empty);

    expect(lost.removedRules, 0);
    expect(lost.tokens, isEmpty);

    final generated = ConfigGeneratorV2.generateConfig(
      _providerConfig,
      const AppSettings(),
      resolvedServerIp: '203.0.113.10',
    );
    expect(
      _rulesOf(generated).map((r) => r['ruleTag']),
      contains('author-unknown'),
    );
  });
}
