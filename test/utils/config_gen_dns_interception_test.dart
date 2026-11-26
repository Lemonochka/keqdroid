import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

// Предохранитель на перехват DNS: он обязан пережить появление новых инбаундов.
//
// Перехват держится на правиле, которое уводит порт 53 в dns-аутбаунд. Если
// оно перестанет накрывать чей-то инбаунд, ядро поднимется как ни в чём не
// бывало, туннель встанет, и только системный резолвер тихо поедет мимо: на
// экране ничего, в логе ничего. Один раз это уже стоило приложению настройки
// Свои DNS, которая не работала вовсе.
//
// Поводом написать стало то, что туннель собираются отдать самому ядру:
// инбаунд у пакетов будет другой, и правило обязано его накрыть само.
const _link =
    'vless://00000000-0000-4000-8000-000000000000@198.51.100.10:443'
    '?type=tcp&security=none#dns';

Map<String, dynamic> _config(String input, [AppSettings? settings]) {
  Socks5Credentials().init('u', 'p');
  return jsonDecode(
        ConfigGeneratorV2.generateConfig(
          input,
          settings ?? const AppSettings(),
        ),
      )
      as Map<String, dynamic>;
}

List<Map<String, dynamic>> _rules(Map<String, dynamic> config) =>
    ((config['routing'] as Map<String, dynamic>)['rules'] as List)
        .cast<Map<String, dynamic>>();

Map<String, dynamic> _rule(Map<String, dynamic> config, String tag) =>
    _rules(config).firstWhere((r) => r['ruleTag'] == tag);

List<String> _inboundTags(Map<String, dynamic> config) => [
  for (final inbound in (config['inbounds'] as List))
    (inbound as Map<String, dynamic>)['tag'] as String,
];

void main() {
  group('обычный конфиг из ссылки', () {
    test(
      'перехват DNS накрывает все наши инбаунды и не ловит собственные запросы ядра',
      () {
        for (final config in [
          _config(_link),
          _config(
            _link,
            const AppSettings(
              lanSharing: true,
              lanUsername: 'lanuser',
              lanPassword: 'lanpass',
            ),
          ),
          jsonDecode(
                ConfigGeneratorV2.generateConfig(
                  _link,
                  const AppSettings(),
                  nativeTunInbound: true,
                ),
              )
              as Map<String, dynamic>,
        ]) {
          final dns = _rule(config, 'dns-out');
          final tags = _inboundTags(config);

          expect(dns['port'], '53');
          expect(dns['network'], 'tcp,udp');
          expect(dns['outboundTag'], 'dns-out');
          expect(
            (dns['inboundTag'] as List?)?.cast<String>(),
            tags,
            reason:
                'без inboundTag ядро перехватывает собственный порт-53 DNS '
                'и шлёт его напрямую мимо туннеля (isOwnLink)',
          );
        }
      },
    );

    test(
      'свой UDP-53 резолвер при доменном сервере получает bootstrap-правило мимо туннеля',
      () {
        const domainLink =
            'vless://00000000-0000-4000-8000-000000000000@vpn.example.com:443'
            '?type=tcp&security=none#dns';
        final settings = const AppSettings().copyWith(
          xrayCore: const AppSettings().xrayCore.copyWith(
            dnsUseCustom: true,
            dnsServers: '8.8.8.8',
          ),
        );
        final config = _config(domainLink, settings);
        final servers = ((config['dns'] as Map)['servers'] as List)
            .whereType<Map<String, dynamic>>()
            .toList();
        final bootstrap = servers.firstWhere(
          (s) =>
              s['address'] == '8.8.8.8' &&
              ((s['domains'] as List?)?.contains('full:vpn.example.com') ??
                  false),
        );
        final bootstrapTag = bootstrap['tag'] as String?;
        expect(bootstrapTag, isNotNull);
        expect(bootstrapTag, isNotEmpty);

        final bootstrapRule = _rule(config, 'dns-bootstrap');
        expect(bootstrapRule['inboundTag'], [bootstrapTag]);
        expect(bootstrapRule['outboundTag'], 'direct');
      },
    );

    test('свой резолвер на 53 порту при final=block не блокирует сам себя', () {
      final settings =
          const AppSettings(
            finalOutbound: AppSettings.finalOutboundBlock,
          ).copyWith(
            xrayCore: const AppSettings().xrayCore.copyWith(
              dnsUseCustom: true,
              dnsServers: '8.8.8.8',
            ),
          );
      final config = _config(_link, settings);
      final resolver = _rule(config, 'dns-resolver');
      expect(resolver['port'], '53');
      expect(resolver['outboundTag'], 'direct');
    });

    test('проба пинга не держит общий localhost в хвосте DNS', () {
      final ping =
          jsonDecode(
                ConfigGeneratorV2.generatePingConfig(
                  _link,
                  const AppSettings(),
                  socksPort: 20999,
                ),
              )
              as Map<String, dynamic>;
      final servers = ((ping['dns'] as Map)['servers'] as List);
      expect(servers, isNot(contains('localhost')));
      final localEntries = servers.whereType<Map<String, dynamic>>().where(
        (s) => s['address'] == 'localhost',
      );
      expect(localEntries, isNotEmpty);
      for (final entry in localEntries) {
        expect(entry['skipFallback'], isTrue);
        expect(entry['finalQuery'], isTrue);
        expect(jsonEncode(entry), isNot(contains('geosite:')));
      }
    });

    test(
      'перехват стоит ПОСЛЕ запрета LAN — иначе открытый резолвер наружу',
      () {
        final config = _config(
          _link,
          const AppSettings(
            lanSharing: true,
            lanUsername: 'lanuser',
            lanPassword: 'lanpass',
          ),
        );
        final tags = [for (final r in _rules(config)) r['ruleTag'] as String?];
        final lan = tags.lastIndexWhere(
          (t) => t != null && t.startsWith('lan-'),
        );
        final dns = tags.indexOf('dns-out');

        expect(lan, isNonNegative, reason: 'правил LAN нет вовсе');
        expect(
          lan,
          lessThan(dns),
          reason:
              'инбаунд LAN слушает 0.0.0.0: перехвати DNS раньше запрета — '
              'и наружу смотрит открытый резолвер. Порядок: $tags',
        );
      },
    );
  });

  group('готовый конфиг автора', () {
    // Здесь правило привязано к инбаундам намеренно: у автора свои, и ловить
    // его собственный DNS мы не вправе. Поэтому список обязан строиться из
    // самих инбаундов, а не быть выписанным руками.
    final custom = jsonEncode({
      'outbounds': [
        {
          'tag': 'proxy',
          'protocol': 'freedom',
          'settings': <String, dynamic>{},
        },
      ],
    });

    test('в перехват попадают все наши инбаунды, сколько бы их ни было', () {
      for (final settings in [
        const AppSettings(),
        const AppSettings(
          lanSharing: true,
          lanUsername: 'lanuser',
          lanPassword: 'lanpass',
        ),
      ]) {
        final config = _config(custom, settings);
        final tags = _inboundTags(config);

        for (final rule in ['dns-out', 'dns-out-tun']) {
          expect(
            (_rule(config, rule)['inboundTag'] as List).cast<String>(),
            tags,
            reason:
                'правило $rule обязано накрывать ровно те инбаунды, что '
                'есть в конфиге: инбаунды $tags',
          );
        }
      }
    });
  });
}
