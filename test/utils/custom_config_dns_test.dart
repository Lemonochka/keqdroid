import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/custom_xray_config.dart';

/// DNS в готовом (custom) конфиге.
///
/// Жалоба, с которой это началось: «подключаешься к кастомному конфигу, чистишь
/// все списки роутинга в приложении, ставишь остальной трафик в блок — и не
/// работает НИЧЕГО, даже то, что сам конфиг ведёт напрямую». На экране
/// «Соединения» при этом видно ровно одно: `8.8.8.8:53 UDP` → `no rule (default
/// action)` → `block`.
///
/// Причина не в роутинге приложения, а в подмене инбаундов. Перехват DNS у
/// автора висит на ЕГО `dokodemo-door` (`dns-in`) и правиле `inboundTag:
/// [dns-in] -> dns-out`; инбаунды мы заменяем своими, и правило остаётся без
/// инбаунда — сработать ему больше не на чем. Дальше запрос к 8.8.8.8:53 (этот
/// адрес TUN отдаёт системе) не ловит ни одно авторское правило и падает в наш
/// `final`. Резолва нет → соединений нет → авторским правилам не на чем
/// срабатывать, и «направо» не работает вместе со всем остальным.
///
/// Сгенерированные конфиги этим не болели никогда: у них есть своё правило
/// `dns-out` и DoH в форме `https+local`, которая ходит мимо роутинга.
const _withAuthorDns = '''
{
  "dns": { "servers": ["1.1.1.1", "1.0.0.1"] },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {"type": "field", "domain": ["domain:gosuslugi.ru"], "outboundTag": "direct"},
      {"type": "field", "ip": ["geoip:private"], "outboundTag": "direct"}
    ]
  },
  "inbounds": [
    {"tag": "socks", "port": 10808, "protocol": "socks", "listen": "127.0.0.1"},
    {"tag": "dns-in", "port": 10853, "protocol": "dokodemo-door",
     "settings": {"address": "1.1.1.1", "port": 53, "network": "tcp,udp"}}
  ],
  "outbounds": [
    {"tag": "proxy", "protocol": "vless", "settings": {"vnext": [
      {"address": "nl1.example.com", "port": 443,
       "users": [{"id": "uuid-1", "encryption": "none"}]}]},
     "streamSettings": {"network": "tcp", "security": "reality"}},
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "block", "protocol": "blackhole"}
  ]
}
''';

/// Тот же конфиг без `dns`: отвечать на перехваченный запрос ядру нечем, кроме
/// системного резолвера, которого на Android нет.
const _withoutAuthorDns = '''
{
  "routing": { "rules": [
    {"type": "field", "domain": ["domain:gosuslugi.ru"], "outboundTag": "direct"}
  ]},
  "outbounds": [
    {"tag": "proxy", "protocol": "vless", "settings": {"vnext": [
      {"address": "nl1.example.com", "port": 443,
       "users": [{"id": "uuid-1", "encryption": "none"}]}]},
     "streamSettings": {"network": "tcp", "security": "reality"}},
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "block", "protocol": "blackhole"}
  ]
}
''';

/// Автор развёл DNS сам, и не через инбаунд: правило по порту переживает
/// подмену инбаундов, и решать должно оно.
const _authorRoutesDns = '''
{
  "dns": { "servers": ["https+local://1.1.1.1/dns-query"] },
  "routing": { "rules": [
    {"type": "field", "port": 53, "network": "tcp,udp", "outboundTag": "author-dns"}
  ]},
  "outbounds": [
    {"tag": "proxy", "protocol": "vless", "settings": {"vnext": [
      {"address": "nl1.example.com", "port": 443,
       "users": [{"id": "uuid-1", "encryption": "none"}]}]},
     "streamSettings": {"network": "tcp", "security": "reality"}},
    {"tag": "author-dns", "protocol": "dns"},
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "block", "protocol": "blackhole"}
  ]
}
''';

/// Автор строит роутинг на fakedns. Перехватить такой DNS означало бы выдать
/// приложению адрес из фейкового пула, из которого домен обратно достаёт только
/// снифер с `fakedns` в `destOverride`, — а его у нас нет.
const _fakeDns = '''
{
  "fakedns": [{"ipPool": "198.18.0.0/15", "poolSize": 65535}],
  "dns": { "servers": ["fakedns", "1.1.1.1"] },
  "routing": { "rules": [
    {"type": "field", "domain": ["domain:gosuslugi.ru"], "outboundTag": "direct"}
  ]},
  "outbounds": [
    {"tag": "proxy", "protocol": "vless", "settings": {"vnext": [
      {"address": "nl1.example.com", "port": 443,
       "users": [{"id": "uuid-1", "encryption": "none"}]}]},
     "streamSettings": {"network": "tcp", "security": "reality"}},
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "block", "protocol": "blackhole"}
  ]
}
''';

/// Настройки из жалобы: списки роутинга вычищены, остальной трафик — в блок.
const _clearedAndBlocked = AppSettings(
  directRules: '',
  proxyRules: '',
  blockedRules: '',
  finalOutbound: AppSettings.finalOutboundBlock,
);

Map<String, dynamic> _build(String raw, AppSettings settings) =>
    jsonDecode(ConfigGeneratorV2.generateConfig(raw, settings))
        as Map<String, dynamic>;

List<Map<String, dynamic>> _rules(Map<String, dynamic> config) => [
      for (final r in ((config['routing'] as Map)['rules'] as List))
        (r as Map).cast<String, dynamic>(),
    ];

List<String?> _ruleTags(Map<String, dynamic> config) =>
    [for (final r in _rules(config)) r['ruleTag'] as String?];

Map<String, dynamic>? _outbound(Map<String, dynamic> config, String tag) {
  for (final o in config['outbounds'] as List) {
    if ((o as Map)['tag'] == tag) return o.cast<String, dynamic>();
  }
  return null;
}

void main() {
  group('custom config DNS', () {
    test('DNS устройства отвечает ядро, а не финальное правило', () {
      final config = _build(_withAuthorDns, _clearedAndBlocked);
      final tags = _ruleTags(config);
      final rules = _rules(config);

      final dns = tags.indexOf('dns-out');
      expect(dns, isNonNegative, reason: 'перехвата DNS нет вовсе');
      expect(dns, lessThan(tags.indexOf('final')));
      expect(rules[dns]['port'], '53');
      expect(rules[dns]['network'], 'tcp,udp');

      // Аутбаунд, на который правило указывает, обязан быть протоколом `dns`:
      // иначе запрос уедет наружу, а не будет отвечен из dns-блока конфига.
      final outbound = _outbound(config, rules[dns]['outboundTag'] as String);
      expect(outbound?['protocol'], 'dns');
    });

    test('правило перехвата ограничено нашими инбаундами — иначе круг', () {
      // Без `inboundTag` под правило попадут и запросы САМОГО ядра к своему
      // upstream (их ядро тоже отправляет через роутинг), и `dns`-аутбаунд
      // начнёт отвечать сам себе.
      final config = _build(_withAuthorDns, _clearedAndBlocked);
      final rules = _rules(config);
      final dns = rules[_ruleTags(config).indexOf('dns-out')];

      final inboundTags = (dns['inboundTag'] as List).cast<String>();
      expect(inboundTags, isNotEmpty);
      final actual = [
        for (final i in config['inbounds'] as List) (i as Map)['tag'],
      ];
      for (final tag in inboundTags) {
        expect(actual, contains(tag));
      }
    });

    test('перехват идёт ПОСЛЕ авторских правил: автор главнее', () {
      final config = _build(_withAuthorDns, _clearedAndBlocked);
      final rules = _rules(config);
      final lastAuthor = rules.lastIndexWhere((r) => r['ruleTag'] == null);

      expect(lastAuthor, isNonNegative);
      expect(lastAuthor, lessThan(_ruleTags(config).indexOf('dns-out')));
    });

    test('свой перехват не перебивает авторский `port: 53`', () {
      final config = _build(_authorRoutesDns, _clearedAndBlocked);
      final rules = _rules(config);
      final tags = _ruleTags(config);

      final author = rules.indexWhere((r) => r['outboundTag'] == 'author-dns');
      expect(author, isNonNegative, reason: 'авторское правило потерялось');
      expect(author, lessThan(tags.indexOf('dns-out')));
    });

    test('резолвер самого ядра не уходит в блок', () {
      // Авторский `dns.servers` — обычный UDP-53, и такой запрос ядро
      // отправляет через роутинг. С финалом «блок» ядро блокирует собственный
      // резолвер: молчит не только DNS устройства, но и `IPIfNonMatch`, а
      // значит и ip-правила автора по доменам.
      final config = _build(_withAuthorDns, _clearedAndBlocked);
      final tags = _ruleTags(config);
      final rules = _rules(config);

      final escape = tags.indexOf('dns-resolver');
      expect(escape, isNonNegative);
      expect(escape, lessThan(tags.indexOf('final')));
      expect(rules[escape]['port'], '53');
      // Направление — авторский freedom, а не выдуманный тег.
      expect(rules[escape]['outboundTag'], 'direct');
      expect(_outbound(config, 'direct')?['protocol'], 'freedom');
    });

    test('резолверу мимо роутинга выход не нужен — блок остаётся буквальным',
        () {
      // `https+local` ходит мимо роутинга, блокировать там нечего: лишнее
      // правило означало бы дырку в порт 53 на пустом месте.
      final config = _build(_authorRoutesDns, _clearedAndBlocked);
      expect(_ruleTags(config), isNot(contains('dns-resolver')));
    });

    test('в режимах direct/proxy выход резолверу не дописывается', () {
      for (final finalOutbound in const [
        AppSettings.finalOutboundDirect,
        AppSettings.finalOutboundProxy,
      ]) {
        final config = _build(
          _withAuthorDns,
          _clearedAndBlocked.copyWith(finalOutbound: finalOutbound),
        );
        expect(
          _ruleTags(config),
          isNot(contains('dns-resolver')),
          reason: 'finalOutbound=$finalOutbound',
        );
      }
    });

    test('авторский dns-блок остаётся авторским', () {
      final config = _build(_withAuthorDns, _clearedAndBlocked);
      expect((config['dns'] as Map)['servers'], ['1.1.1.1', '1.0.0.1']);
    });

    test('без авторского dns подставляется свой', () {
      // Дефолт ядра — `localhost`, то есть системный резолвер; на Android его
      // нет (`/etc/resolv.conf` отсутствует), и перехваченный запрос упёрся бы
      // в тишину.
      final config = _build(_withoutAuthorDns, _clearedAndBlocked);
      final servers = (config['dns'] as Map)['servers'] as List;

      expect(servers, isNotEmpty);
      expect(
        servers.any((s) => '${(s as Map)['address']}'.startsWith('https+local')),
        isTrue,
      );
      // DoH мимо роутинга — значит и выход резолверу не нужен.
      expect(_ruleTags(config), isNot(contains('dns-resolver')));
    });

    test('конфиг на fakedns мы не перехватываем', () {
      // Перехват вернул бы приложению фейковый адрес, а достать из него домен
      // обратно нечем: `destOverride` у нас без `fakedns`. Тогда не сработало
      // бы ни одно доменное правило автора — то есть перехват сломал бы ровно
      // то, ради чего он и добавлен.
      final config = _build(_fakeDns, _clearedAndBlocked);
      expect(_ruleTags(config), isNot(contains('dns-out')));
      expect(_outbound(config, 'keq-dns-out'), isNull);
    });

    test('без перехвата DNS устройства всё равно не уходит в блок', () {
      // Перехвата нет, значит запрос к 8.8.8.8:53 дошёл бы до `final`. Ловим
      // его тем же правилом, что и резолвер ядра.
      final config = _build(_fakeDns, _clearedAndBlocked);
      final tags = _ruleTags(config);

      expect(tags, contains('dns-resolver'));
      expect(tags.indexOf('dns-resolver'), lessThan(tags.indexOf('final')));
    });

    test('правила ссылаются только на существующие аутбаунды', () {
      // Тег, которого нет в аутбаундах, роняет разбор ВСЕГО конфига: ядро не
      // поднимается, и наружу это «SOCKS port not ready».
      for (final raw in const [
        _withAuthorDns,
        _withoutAuthorDns,
        _authorRoutesDns,
        _fakeDns,
      ]) {
        for (final finalOutbound in AppSettings.finalOutbounds) {
          final config = _build(
            raw,
            _clearedAndBlocked.copyWith(finalOutbound: finalOutbound),
          );
          final tags = [
            for (final o in config['outbounds'] as List) (o as Map)['tag'],
          ];
          for (final rule in _rules(config)) {
            expect(tags, contains(rule['outboundTag']), reason: 'rule: $rule');
          }
        }
      }
    });
  });

  group('мёртвые правила автора', () {
    // Правило, привязанное к инбаунду автора, после подмены инбаундов не
    // сработает ни разу: условие не выполнится. Молчать об этом нельзя — со
    // стороны это «правила провайдера не работают».
    Map<String, dynamic> parse(String raw) =>
        CustomXrayConfig.tryParse(raw)!.json;

    test('считает правила, оставшиеся без инбаунда', () {
      final report = previewDeadInboundRules(
        parse('''
{
  "routing": { "rules": [
    {"type": "field", "inboundTag": ["socks", "http"], "outboundTag": "proxy"},
    {"type": "field", "inboundTag": ["api"], "outboundTag": "api"},
    {"type": "field", "domain": ["domain:vk.com"], "outboundTag": "direct"}
  ]},
  "outbounds": [
    {"tag": "proxy", "protocol": "vless", "settings": {"vnext": [
      {"address": "a.example.com", "port": 443,
       "users": [{"id": "uuid-1", "encryption": "none"}]}]}},
    {"tag": "direct", "protocol": "freedom"}
  ]
}
'''),
        ConfigGeneratorV2.appInboundTags,
      );

      expect(report.rules, 2);
      expect(report.tags.toSet(), {'socks', 'http', 'api'});
    });

    test('перехват DNS потерей не считается — его мы делаем сами', () {
      final report = previewDeadInboundRules(
        parse('''
{
  "routing": { "rules": [
    {"type": "field", "inboundTag": ["dns-in"], "outboundTag": "dns-out"}
  ]},
  "outbounds": [
    {"tag": "proxy", "protocol": "vless", "settings": {"vnext": [
      {"address": "a.example.com", "port": 443,
       "users": [{"id": "uuid-1", "encryption": "none"}]}]}},
    {"tag": "dns-out", "protocol": "dns"}
  ]
}
'''),
        ConfigGeneratorV2.appInboundTags,
      );

      expect(report.rules, 0);
    });

    test('правило с НАШИМ тегом живо', () {
      final report = previewDeadInboundRules(
        parse('''
{
  "routing": { "rules": [
    {"type": "field", "inboundTag": ["socks-in"], "outboundTag": "proxy"}
  ]},
  "outbounds": [
    {"tag": "proxy", "protocol": "vless", "settings": {"vnext": [
      {"address": "a.example.com", "port": 443,
       "users": [{"id": "uuid-1", "encryption": "none"}]}]}}
  ]
}
'''),
        ConfigGeneratorV2.appInboundTags,
      );

      expect(report.rules, 0);
    });

    test('теги, которые ставит генератор, совпадают со списком для проверки',
        () {
      // Список `appInboundTags` — не константа сама по себе: разъедется с
      // `_buildInbounds`, и детект начнёт врать в обе стороны.
      final config = _build(
        _withAuthorDns,
        _clearedAndBlocked.copyWith(lanSharing: true, lanUsername: ''),
      );
      final actual = [
        for (final i in config['inbounds'] as List) (i as Map)['tag'] as String,
      ];

      expect(actual, isNotEmpty);
      for (final tag in actual) {
        expect(ConfigGeneratorV2.appInboundTags, contains(tag));
      }
    });
  });
}
