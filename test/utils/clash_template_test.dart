import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/services/subscription_service.dart';
import 'package:keqdroid/utils/clash_template.dart';
import 'package:keqdroid/utils/custom_clash_config.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/models/app_settings.dart';

String _fixture(String name) =>
    File('test/fixtures/subscription_payloads/$name').readAsStringSync();

Map<String, dynamic> _group(Map<String, dynamic> config, String name) =>
    (config['proxy-groups'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((g) => g['name'] == name);

void main() {
  final body = _fixture('clash-template-groups.txt');

  group('разбор шаблона', () {
    test('главная группа это цель MATCH, переключать можно только select', () {
      final template = ClashTemplate.fromBody(body)!;
      expect(template.mainGroup, 'Основной');
      expect(
        [for (final g in template.groups) g.name],
        ['Недоступные сайты', 'YouTube'],
        reason: 'fallback выбирает ядро, hidden автор спрятал, главная уходит в список серверов',
      );
    });

    test('состав группы собирается как у ядра: include-all по filter', () {
      final template = ClashTemplate.fromBody(body)!;
      final youtube = template.groups.firstWhere((g) => g.name == 'YouTube');
      expect(youtube.members, ['🇩🇪 Germany', '🇫🇮 Finland']);
      expect(youtube.fromProviders, isTrue);
      final blocked =
          template.groups.firstWhere((g) => g.name == 'Недоступные сайты');
      expect(blocked.members.first, 'Любой доступный');
      expect(template.kindOf('Любой доступный'), ClashMemberKind.group);
      expect(template.kindOf('DIRECT'), ClashMemberKind.direct);
      expect(template.kindOf('🇫🇮 Finland'), ClashMemberKind.node);
    });

    test('шаблон Remnawave по умолчанию, одна группа на все узлы, не хранится', () {
      const remnawave = '''
proxies:
  - {name: a, type: ss, server: a.example.com, port: 443, cipher: aes-128-gcm, password: p}
  - {name: b, type: ss, server: b.example.com, port: 443, cipher: aes-128-gcm, password: p}
proxy-groups:
  - name: '→ Remnawave'
    type: 'select'
    proxies: [a, b]
rules:
  - MATCH,→ Remnawave
''';
      expect(ClashTemplate.fromBody(remnawave), isNull);
    });

    test('с relay это не шаблон: ядро отказало бы всему конфигу, а узлами подписка работает', () {
      final relay = '$body\n'.replaceFirst(
        'proxy-groups:\n',
        'proxy-groups:\n  - {name: Цепочка, type: relay, proxies: [🇩🇪 Germany, 🇫🇮 Finland]}\n',
      );
      expect(relay, contains('type: relay'));
      expect(ClashTemplate.fromBody(relay), isNull);
    });

    test('без своих узлов это не шаблон: профиль на proxy-providers идёт как раньше', () {
      expect(ClashTemplate.fromBody(_fixture('clash-providers-direct.txt')), isNull);
      expect(ClashTemplate.fromBody('vless://x@a.example.com:443#a'), isNull);
    });

    test('сохранённый шаблон читается обратно тем же', () {
      final template = ClashTemplate.fromBody(body)!;
      final again = ClashTemplate.fromBody(template.encode())!;
      expect(again.mainGroup, template.mainGroup);
      expect([for (final g in again.groups) g.name],
          [for (final g in template.groups) g.name]);
    });
  });

  group('узел сервера', () {
    test('сервер подписки узнаётся по имени, а правленный руками нет', () {
      final template = ClashTemplate.fromBody(body)!;
      final configs = SubscriptionService.parseBodyForTest(body);
      final servers = [for (final c in configs) ServerItem.fromRaw(c)];
      expect(
        [for (final s in servers) template.nodeFor(s)],
        ['🇩🇪 Germany', '🇫🇮 Finland', '🇱🇻 Latvia'],
      );
      expect(
        template.nodeFor(servers[1].copyWith(configOverridden: true)),
        isNull,
      );
    });
  });

  group('чем подключать сервер', () {
    final template = ClashTemplate.fromBody(body)!.encode();
    final servers = [
      for (final c in SubscriptionService.parseBodyForTest(body))
        ServerItem.fromRaw(c, subscriptionId: 's1'),
    ];

    const mihomo = AppSettings(vpnCore: AppSettings.vpnCoreMihomo);

    test('сервер подписки с шаблоном идёт шаблоном', () {
      final config = templatedSessionConfig(
        server: servers[2],
        template: template,
        settings: mihomo,
      );
      expect(CustomClashConfig.tryParse(config!)!.proxies.first['name'], '🇱🇻 Latvia');
    });

    test('без шаблона, с «Не учитывать правила провайдера» и чужой сервер идут как раньше', () {
      expect(
        templatedSessionConfig(server: servers[0], template: null, settings: mihomo),
        isNull,
      );
      expect(
        templatedSessionConfig(
          server: servers[0],
          template: template,
          settings: mihomo.copyWith(ignoreProviderRules: true),
        ),
        isNull,
      );
      expect(
        templatedSessionConfig(
          server: ServerItem.fromRaw(
            'trojan://p@203.0.113.9:443?security=tls#Other',
            subscriptionId: 's1',
          ),
          template: template,
          settings: mihomo,
        ),
        isNull,
      );
    });

    test('на xray шаблон не включается: ядро из настроек не подменяется', () {
      expect(
        templatedSessionConfig(
          server: servers[0],
          template: template,
          settings: const AppSettings(vpnCore: AppSettings.vpnCoreXray),
        ),
        isNull,
      );
    });
  });

  group('конфиг сессии', () {
    test('выбранный сервер первым в главной группе и в узлах, выбор человека первым в своей', () {
      final template = ClashTemplate.fromBody(body)!;
      final session = (jsonDecode(template.sessionConfig(
        node: '🇫🇮 Finland',
        choices: {'Недоступные сайты': 'DIRECT', 'YouTube': '🇩🇪 Germany'},
      )) as Map).cast<String, dynamic>();

      expect((session['proxies'] as List).first['name'], '🇫🇮 Finland');
      expect((session['proxy-groups'] as List).first['name'], 'Основной',
          reason: 'наши маршруты через VPN ведут в первую группу');
      expect(_group(session, 'Основной')['proxies'],
          ['🇫🇮 Finland', '🇩🇪 Germany', '🇱🇻 Latvia']);
      expect(_group(session, 'Недоступные сайты')['proxies'].first, 'DIRECT');
      expect(_group(session, 'YouTube')['proxies'], ['🇩🇪 Germany']);
      expect(session['profile'], {'store-selected': false});
      expect(session['rules'], (CustomClashConfig.tryParse(body)!.map['rules']));
    });

    test('выбор узла из proxy-providers в список не попадает: ядро отказало бы всему конфигу', () {
      final template = ClashTemplate.fromBody(body)!;
      final session = (jsonDecode(template.sessionConfig(
        node: '🇩🇪 Germany',
        choices: {'Недоступные сайты': 'provider-node-1'},
      )) as Map).cast<String, dynamic>();
      expect(_group(session, 'Недоступные сайты')['proxies'].first,
          'Любой доступный');
    });

    test('главная с автовыбором становится select: всё остальное идёт через выбранный сервер', () {
      final auto = body.replaceFirst(
        '  - name: Основной\n    type: select',
        '  - name: Основной\n    type: url-test',
      );
      final template = ClashTemplate.fromBody(auto)!;
      final session = (jsonDecode(template.sessionConfig(node: '🇱🇻 Latvia'))
              as Map)
          .cast<String, dynamic>();
      expect(_group(session, 'Основной')['type'], 'select');
      expect(_group(session, 'Основной')['proxies'].first, '🇱🇻 Latvia');
    });

    test('mihomo получает шаблон целиком с нашими входами и без его портов', () {
      final template = ClashTemplate.fromBody(body)!;
      final config = (jsonDecode(MihomoConfigGen.generate(
        template.sessionConfig(node: '🇫🇮 Finland'),
        const AppSettings(),
        socksPort: 10808,
      )) as Map).cast<String, dynamic>();
      expect(config['mixed-port'], isNull);
      expect(config['socks-port'], 10808);
      expect([for (final g in config['proxy-groups'] as List) g['name']],
          containsAll(['Основной', 'YouTube', 'Недоступные сайты']));
      expect((config['rules'] as List).last, 'MATCH,Основной');
    });
  });
}
