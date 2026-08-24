import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/tunnel/app_routing_mode.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

Map<String, dynamic> _proxy(Map<String, dynamic> config) =>
    (config['proxies'] as List).cast<Map<String, dynamic>>().single;

List<String> _rules(Map<String, dynamic> config) =>
    (config['rules'] as List).cast<String>();

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  const settings = AppSettings(
    directRules: 'vk.com, geosite:category-ru, 10.8.0.0/24, geoip:ru',
    proxyRules: 'youtube.com',
    blockedRules: 'doubleclick.net',
  );

  group('инбаунд', () {
    test('слушает только петлю и требует те же креды, что ждёт tun2socks', () {
      final c = MihomoConfigGen.build(
        'vless://uuid@example.com:443?type=tcp&security=none',
        const AppSettings(),
        socksPort: 2080,
      );
      expect(c['socks-port'], 2080);
      expect(c['bind-address'], '127.0.0.1');
      expect(c['allow-lan'], isFalse);
      expect(c['authentication'], ['u:p']);
    });

    test('noauth-режим не пишет authentication вовсе', () {
      final c = MihomoConfigGen.build(
        'vless://uuid@example.com:443?type=tcp&security=none',
        const AppSettings(),
        socksPort: 2080,
        localInboundsNoAuth: true,
      );
      expect(c.containsKey('authentication'), isFalse);
    });

    // Ядро иначе полезет в сеть за своими копиями баз ещё до туннеля.
    test('geo берётся из вшитых баз, без автообновления', () {
      final c = MihomoConfigGen.build(
        'vless://uuid@example.com:443?type=tcp&security=none',
        const AppSettings(),
        socksPort: 2080,
      );
      expect(c['geodata-mode'], isTrue);
      expect(c['geo-auto-update'], isFalse);
    });

    test('log-level none у mihomo называется silent', () {
      final c = MihomoConfigGen.build(
        'vless://uuid@example.com:443?type=tcp&security=none',
        const AppSettings(xrayCore: XrayCoreSettings(logLevel: 'none')),
        socksPort: 2080,
      );
      expect(c['log-level'], 'silent');
    });
  });

  group('прокси', () {
    test('vless + reality + vision', () {
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=reality&sni=decoy.example'
        '&pbk=publickey&sid=aabb&fp=chrome&flow=xtls-rprx-vision',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['type'], 'vless');
      expect(p['server'], 'nl.example');
      expect(p['port'], 443);
      expect(p['uuid'], 'uuid');
      expect(p['tls'], isTrue);
      expect(p['servername'], 'decoy.example');
      expect(p['flow'], 'xtls-rprx-vision');
      expect(p['reality-opts'], {'public-key': 'publickey', 'short-id': 'aabb'});
      expect(p['network'], 'tcp');
      // Без UDP через SOCKS5 ядро молча отбросит UDP-сессии.
      expect(p['udp'], isTrue);
    });

    // У mihomo пустой client-fingerprint значит «без uTLS», а не chrome, как у
    // xray, — поэтому подставляем явно.
    test('vless без fp получает chrome', () {
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@e.example:443?type=tcp&security=tls&sni=e.example',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['client-fingerprint'], 'chrome');
    });

    test('vless + ws переносит path и Host', () {
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@w.example:443?type=ws&security=tls&sni=w.example'
        '&path=%2Fpath&host=w.example',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['network'], 'ws');
      expect(p['ws-opts'], {
        'path': '/path',
        'headers': {'Host': 'w.example'},
      });
    });

    test('vless + grpc', () {
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@g.example:443?type=grpc&security=tls&serviceName=svc',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['network'], 'grpc');
      expect(p['grpc-opts'], {'grpc-service-name': 'svc'});
    });

    test('vmess из base64-json', () {
      final payload = base64.encode(utf8.encode(jsonEncode({
        'v': '2',
        'add': 'v.example',
        'port': '443',
        'id': '11111111-1111-1111-1111-111111111111',
        'aid': '0',
        'net': 'ws',
        'tls': 'tls',
        'sni': 'v.example',
        'path': '/vmess',
        'host': 'v.example',
      })));
      final p = _proxy(MihomoConfigGen.build(
        'vmess://$payload',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['type'], 'vmess');
      expect(p['server'], 'v.example');
      expect(p['port'], 443);
      expect(p['alterId'], 0);
      expect(p['cipher'], 'auto');
      expect(p['tls'], isTrue);
      expect(p['network'], 'ws');
      expect((p['ws-opts'] as Map)['path'], '/vmess');
    });

    test('trojan', () {
      final p = _proxy(MihomoConfigGen.build(
        'trojan://secret@t.example:8443?sni=t.example',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['type'], 'trojan');
      expect(p['password'], 'secret');
      expect(p['sni'], 't.example');
    });

    test('shadowsocks sip002', () {
      final userInfo = base64.encode(utf8.encode('aes-256-gcm:pass'));
      final p = _proxy(MihomoConfigGen.build(
        'ss://$userInfo@s.example:8388#node',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['type'], 'ss');
      expect(p['server'], 's.example');
      expect(p['port'], 8388);
      expect(p['cipher'], 'aes-256-gcm');
      expect(p['password'], 'pass');
    });

    test('hysteria2 с obfs', () {
      final p = _proxy(MihomoConfigGen.build(
        'hysteria2://token@hy.example:443?sni=hy.example&obfs=salamander'
        '&obfs-password=xyz&up=50&down=200',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['type'], 'hysteria2');
      expect(p['password'], 'token');
      expect(p['obfs'], 'salamander');
      expect(p['obfs-password'], 'xyz');
      expect(p['up'], '50');
      expect(p['down'], '200');
    });

    // Тот же принцип, что и у xray: доверять любому сертификату мы не даём.
    test('insecure=1 не превращается в skip-cert-verify', () {
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@e.example:443?type=tcp&security=tls&insecure=1',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p.containsKey('skip-cert-verify'), isFalse);
    });

    test('незнакомый протокол — внятная ошибка без самой ссылки', () {
      expect(
        () => MihomoConfigGen.build(
          'wireguard://secret@w.example:51820',
          const AppSettings(),
          socksPort: 2080,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message.toString(),
          'message',
          allOf(contains('wireguard'), isNot(contains('secret'))),
        )),
      );
    });
  });

  group('транспорт', () {
    // Из-за молчаливого отката на tcp сервер на xhttp отвечал так, будто дело
    // в ключах REALITY: ядро поднималось, конфиг был «валидным», а описывал
    // другой сервер.
    test('xhttp переносится целиком, а не сводится к tcp', () {
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@x.example:443?type=xhttp&security=reality'
        '&pbk=key&sid=ab&sni=cdn.example&mode=auto&path=%2Fpath'
        '&x_padding_bytes=92-1412',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['network'], 'xhttp');
      expect(p['xhttp-opts'], {
        'path': '/path',
        'mode': 'auto',
        'x-padding-bytes': '92-1412',
      });
    });

    test('splithttp — то же самое под старым именем', () {
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@x.example:443?type=splithttp&security=tls&sni=x.example',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['network'], 'xhttp');
      expect((p['xhttp-opts'] as Map)['path'], '/');
    });

    test('extra отдаёт то, чего нет в query, вместе с xmux', () {
      const extra = '{"mode":"packet-up","xPaddingBytes":"100-1000",'
          '"xmux":{"maxConcurrency":"16-32","hKeepAlivePeriod":45}}';
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@x.example:443?type=xhttp&security=tls&sni=x.example'
        '&extra=${Uri.encodeQueryComponent(extra)}',
        const AppSettings(),
        socksPort: 2080,
      ));
      final opts = p['xhttp-opts'] as Map;
      expect(opts['mode'], 'packet-up');
      expect(opts['x-padding-bytes'], '100-1000');
      // hKeepAlivePeriod у mihomo число, остальное — строки: они принимают
      // диапазоны вида `16-32`.
      expect(opts['reuse-settings'],
          {'max-concurrency': '16-32', 'h-keep-alive-period': 45});
    });

    test('битый extra не роняет ссылку целиком', () {
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@x.example:443?type=xhttp&security=tls&sni=x.example'
        '&extra=%7Bnot-json',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['network'], 'xhttp');
      expect(p['xhttp-opts'], {'path': '/'});
    });

    test('raw — это tcp под новым именем', () {
      final p = _proxy(MihomoConfigGen.build(
        'vless://uuid@x.example:443?type=raw&security=none',
        const AppSettings(),
        socksPort: 2080,
      ));
      expect(p['network'], 'tcp');
    });

    test('незнакомый транспорт — ошибка, а не тихий tcp', () {
      expect(
        () => MihomoConfigGen.build(
          'vless://uuid@x.example:443?type=kcp&security=none',
          const AppSettings(),
          socksPort: 2080,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message.toString(),
          'message',
          allOf(contains('kcp'), isNot(contains('uuid'))),
        )),
      );
    });
  });

  group('правила', () {
    test('порядок повторяет xray: блок → сервер → обход → приватные → прокси', () {
      final rules = _rules(MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=none',
        settings,
        socksPort: 2080,
        resolvedServerIp: '203.0.113.7',
      ));

      int at(String needle) => rules.indexWhere((r) => r.contains(needle));

      expect(at('doubleclick.net'), lessThan(at('nl.example')));
      expect(at('nl.example'), lessThan(at('vk.com')));
      expect(at('vk.com'), lessThan(at('192.168.0.0/16')));
      expect(at('192.168.0.0/16'), lessThan(at('youtube.com')));
      expect(rules.last, 'MATCH,proxy');
    });

    test('типы правил переводятся в синтаксис mihomo', () {
      final rules = _rules(MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=none',
        settings,
        socksPort: 2080,
        resolvedServerIp: '203.0.113.7',
      ));
      expect(rules, contains('DOMAIN-SUFFIX,doubleclick.net,REJECT'));
      expect(rules, contains('DOMAIN,nl.example,DIRECT'));
      expect(rules, contains('IP-CIDR,203.0.113.7/32,DIRECT,no-resolve'));
      expect(rules, contains('DOMAIN-SUFFIX,vk.com,DIRECT'));
      expect(rules, contains('GEOSITE,category-ru,DIRECT'));
      expect(rules, contains('GEOIP,ru,DIRECT'));
      // Без `no-resolve`: умолчание снифера — подмена адреса назначения, и
      // тогда пользовательские IP-правила обязаны резолвить домен, иначе они
      // молча промахиваются (тот же случай, что `AsIs` → `IPIfNonMatch` у
      // xray). Полный разбор — в тесте про no-resolve ниже.
      expect(rules, contains('IP-CIDR,10.8.0.0/24,DIRECT'));
      expect(rules, contains('DOMAIN-SUFFIX,youtube.com,proxy'));
    });

    test('«остальное» уважает выбор пользователя', () {
      String finalOf(String mode) => _rules(MihomoConfigGen.build(
            'vless://uuid@nl.example:443?type=tcp&security=none',
            AppSettings(finalOutbound: mode),
            socksPort: 2080,
          )).last;

      expect(finalOf(AppSettings.finalOutboundProxy), 'MATCH,proxy');
      expect(finalOf(AppSettings.finalOutboundDirect), 'MATCH,DIRECT');
      expect(finalOf(AppSettings.finalOutboundBlock), 'MATCH,REJECT');
    });

    // Зеркало `AsIs` → `IPIfNonMatch` у xray: с подменой назначения на домен
    // IP-правило с `no-resolve` промахнулось бы мимо собственного адреса.
    test('подмена назначения снимает no-resolve с пользовательских IP-правил',
        () {
      List<String> rulesFor({required bool routeOnly, required String direct}) =>
          _rules(MihomoConfigGen.build(
            'vless://uuid@nl.example:443?type=tcp&security=none',
            AppSettings(
              directRules: direct,
              xrayCore: XrayCoreSettings(sniffingRouteOnly: routeOnly),
            ),
            socksPort: 2080,
            resolvedServerIp: '203.0.113.7',
          ));

      expect(
        rulesFor(routeOnly: false, direct: '10.130.0.0/16'),
        contains('IP-CIDR,10.130.0.0/16,DIRECT'),
      );
      expect(
        rulesFor(routeOnly: true, direct: '10.130.0.0/16'),
        contains('IP-CIDR,10.130.0.0/16,DIRECT,no-resolve'),
      );

      // Без пользовательских IP-правил резолвить каждый домен незачем — как и
      // у xray, где стратегия остаётся `AsIs`.
      final domainsOnly = rulesFor(routeOnly: false, direct: 'vk.com');
      expect(
        domainsOnly,
        contains('IP-CIDR,192.168.0.0/16,DIRECT,no-resolve'),
      );
      // Адрес сервера защищён от круга при любых настройках.
      expect(
        domainsOnly,
        contains('IP-CIDR,203.0.113.7/32,DIRECT,no-resolve'),
      );
    });

    // Голый адрес mihomo у IP-CIDR не примет — нужен префикс.
    test('голому IP дописывается префикс', () {
      final rules = _rules(MihomoConfigGen.build(
        'vless://uuid@203.0.113.9:443?type=tcp&security=none',
        const AppSettings(directRules: '1.2.3.4'),
        socksPort: 2080,
      ));
      expect(rules, contains('IP-CIDR,203.0.113.9/32,DIRECT,no-resolve'));
      // no-resolve тут нет по той же причине, что и выше: умолчание — подмена
      // адреса. Проверяем префикс, а не суффикс правила.
      expect(rules, contains('IP-CIDR,1.2.3.4/32,DIRECT'));
    });
  });

  group('sniffer', () {
    // Без него доменная половина правил не срабатывает НИКОГДА: в SOCKS от
    // tun2socks приезжает голый IP, сравнивать GEOSITE/DOMAIN-SUFFIX не с чем,
    // и всё уходит в MATCH.
    test('включён и нюхает чистые IP — иначе домены не матчатся вовсе', () {
      final s = MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=none',
        const AppSettings(),
        socksPort: 2080,
      )['sniffer'] as Map<String, dynamic>;

      expect(s['enable'], isTrue);
      expect(s['parse-pure-ip'], isTrue);
      expect((s['sniff'] as Map).keys, containsAll(['HTTP', 'TLS', 'QUIC']));
    });

    // `routeOnly` у xray и `override-destination` у mihomo описывают одно и то
    // же с разных сторон, поэтому значения инвертированы.
    test('override-destination — зеркало sniffingRouteOnly', () {
      bool overrideFor({required bool routeOnly}) =>
          (MihomoConfigGen.build(
            'vless://uuid@nl.example:443?type=tcp&security=none',
            AppSettings(
              xrayCore: XrayCoreSettings(sniffingRouteOnly: routeOnly),
            ),
            socksPort: 2080,
          )['sniffer'] as Map<String, dynamic>)['override-destination'] as bool;

      expect(overrideFor(routeOnly: true), isFalse);
      expect(overrideFor(routeOnly: false), isTrue);
    });

    test('выключенный в настройках sniffing выключен и здесь', () {
      final s = MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=none',
        const AppSettings(
          xrayCore: XrayCoreSettings(sniffingEnabled: false),
        ),
        socksPort: 2080,
      )['sniffer'] as Map<String, dynamic>;

      expect(s['enable'], isFalse);
    });
  });

  group('dns', () {
    // Системного резолвера на Android нет (/etc/resolv.conf отсутствует), и без
    // своего DNS домен сервера из ссылки не разрешается вовсе.
    test('ядро резолвит само, подмена адресов по умолчанию выключена', () {
      final dns = MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=none',
        const AppSettings(),
        socksPort: 2080,
      )['dns'] as Map<String, dynamic>;

      expect(dns['enable'], isTrue);
      expect(dns['enhanced-mode'], 'normal');
      expect(dns['nameserver'], isNotEmpty);
      // Адрес прокси-сервера резолвится мимо туннеля, иначе круг.
      expect(dns['proxy-server-nameserver'], isNotEmpty);
    });

    // Аналог `https://` вместо `https+local://` у xray: DNS прячем в туннель
    // только когда туда же уходит всё остальное.
    test('глобал-прокси гонит DNS по правилам', () {
      Map<String, dynamic> dnsFor(String finalOutbound) =>
          MihomoConfigGen.build(
            'vless://uuid@nl.example:443?type=tcp&security=none',
            AppSettings(finalOutbound: finalOutbound),
            socksPort: 2080,
          )['dns'] as Map<String, dynamic>;

      expect(dnsFor(AppSettings.finalOutboundProxy)['respect-rules'], isTrue);
      expect(
        dnsFor(AppSettings.finalOutboundDirect).containsKey('respect-rules'),
        isFalse,
      );
    });

    test('серверы из настроек xray переводятся в схемы mihomo', () {
      expect(
        MihomoConfigGen.dnsServers(
          const XrayCoreSettings(
            dnsUseCustom: true,
            dnsServers: 'https+local://1.1.1.1/dns-query\n'
                'tcp://9.9.9.9\n'
                '8.8.4.4\n'
                'localhost\n'
                'h2c://example.com/dns-query',
          ),
        ),
        // h2c mihomo не знает — такая запись роняет разбор конфига целиком,
        // поэтому её выбрасываем, а не переносим как есть.
        ['https://1.1.1.1/dns-query', 'tcp://9.9.9.9', '8.8.4.4', 'system'],
      );
    });

    test('пустой список не оставляет ядро без резолвера', () {
      expect(
        MihomoConfigGen.dnsServers(
          const XrayCoreSettings(dnsUseCustom: true, dnsServers: '  \n '),
        ),
        isNotEmpty,
      );
    });

    // Семейство адресов у обоих ядер берётся из одной настройки.
    test('queryStrategy решает судьбу AAAA', () {
      Map<String, dynamic> configFor(String strategy) => MihomoConfigGen.build(
            'vless://uuid@nl.example:443?type=tcp&security=none',
            AppSettings(
              xrayCore: XrayCoreSettings(dnsQueryStrategy: strategy),
            ),
            socksPort: 2080,
          );

      final v4 = configFor('UseIPv4');
      expect(v4['ipv6'], isFalse);
      expect((v4['dns'] as Map)['ipv6'], isFalse);

      final both = configFor('UseIP');
      expect(both['ipv6'], isTrue);
      expect((both['dns'] as Map)['ipv6'], isTrue);
    });
  });

  group('api ядра', () {
    test('external-controller поднимается только с портом и всегда с токеном',
        () {
      final withApi = MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=none',
        const AppSettings(),
        socksPort: 2080,
        apiPort: 9971,
        apiSecret: 's3cr3t',
      );
      expect(withApi['external-controller'], '127.0.0.1:9971');
      expect(withApi['secret'], 's3cr3t');

      // Пинг и спидтест поднимают ядро без API — управлять там нечем.
      final withoutApi = MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=none',
        const AppSettings(),
        socksPort: 2080,
      );
      expect(withoutApi.containsKey('external-controller'), isFalse);
      expect(withoutApi.containsKey('secret'), isFalse);
    });
  });

  group('раздача в локалку', () {
    const lanOn = AppSettings(
      lanSharing: true,
      lanSocksPort: 1080,
      lanHttpPort: 8080,
    );

    test('выключенная раздача не оставляет ни листенеров, ни их правил', () {
      final c = MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=none',
        const AppSettings(),
        socksPort: 2080,
      );
      expect(c.containsKey('listeners'), isFalse);
      expect(c.containsKey('sub-rules'), isFalse);
      expect(c['allow-lan'], isFalse);
    });

    test('листенеры слушают сеть и ходят по своему набору правил', () {
      final listeners = (MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=none',
        lanOn,
        socksPort: 2080,
      )['listeners'] as List)
          .cast<Map<String, dynamic>>();

      expect(listeners.map((l) => l['type']), ['socks', 'http']);
      for (final l in listeners) {
        expect(l['listen'], '0.0.0.0');
        expect(l['rule'], MihomoConfigGen.lanRuleSet);
        // Порт у mihomo строковый (принимает и диапазоны).
        expect(l['port'], isA<String>());
      }
      expect(listeners.first['port'], '1080');
      expect(listeners.last['port'], '8080');
    });

    // Разница «пусто» и «нет ключа» здесь решает всё: без ключа mihomo
    // подставит глобальный `authentication`, то есть случайные креды
    // tun2socks, и в раздачу не зайдёт никто.
    test('без пароля users пустой, но присутствует', () {
      final listeners = (MihomoConfigGen.build(
        'vless://uuid@nl.example:443?type=tcp&security=none',
        lanOn,
        socksPort: 2080,
      )['listeners'] as List)
          .cast<Map<String, dynamic>>();

      for (final l in listeners) {
        expect(l.containsKey('users'), isTrue);
        expect(l['users'], isEmpty);
      }
    });

    test('пароль просят только когда заполнены оба поля', () {
      List<Map<String, String>> usersFor(String user, String pass) =>
          MihomoConfigGen.lanUsers(
            AppSettings(lanSharing: true, lanUsername: user, lanPassword: pass),
          );

      expect(usersFor('keq', 'hunter2'), [
        {'username': 'keq', 'password': 'hunter2'},
      ]);
      expect(usersFor('  ', 'hunter2'), isEmpty);
      expect(usersFor('keq', ''), isEmpty);
    });

    // Инбаунд слушает 0.0.0.0: без замыкающего REJECT не совпавшее соединение
    // ушло бы в DIRECT, и раздача стала бы открытым прокси для интернета.
    test('чужим источникам отказ, своим — туннель', () {
      final rules = MihomoConfigGen.buildLanRules();

      expect(rules.last, 'MATCH,REJECT');
      expect(rules, contains('SRC-IP-CIDR,192.168.0.0/16,proxy'));
      expect(rules, contains('SRC-IP-CIDR,10.0.0.0/8,proxy'));
      expect(rules.where((r) => r.startsWith('SRC-IP-CIDR')).length, 5);
    });
  });

  group('свой туннель', () {
    const link = 'vless://uuid@nl.example:443?type=tcp&security=none';

    MihomoTunOptions desktopTun() => const MihomoTunOptions(
          device: 'tun-keqdis',
          stack: 'gvisor',
          mtu: 9000,
        );

    test('десктоп: ядро создаёт устройство само', () {
      final tun = MihomoConfigGen.build(
        link,
        settings,
        socksPort: 2080,
        httpPort: 2081,
        tun: desktopTun(),
        windows: true,
      )['tun'] as Map<String, dynamic>;

      expect(tun['enable'], isTrue);
      // Имя своё: без него mihomo берёт `Meta`, а wintun считает GUID
      // адаптера от имени — тот же GUID у любого mihomo-клиента на машине.
      expect(tun['device'], 'tun-keqdis');
      expect(tun['stack'], 'gvisor');
      expect(tun['mtu'], 9000);
      expect(tun['auto-route'], isTrue);
      expect(tun['auto-detect-interface'], isTrue);
      // Ради этого схема и нужна: запрос системы на 53 уходит в резолвер ядра.
      expect(tun['dns-hijack'], ['any:53']);
    });

    // На Android дескриптор и MTU принадлежат сервису: он поднял интерфейс, он
    // же и дописывает оба числа в готовый конфиг. Вторая копия MTU на этой
    // стороне разъехалась бы с интерфейсом молча.
    test('android: ни устройства, ни MTU — их проставит владелец fd', () {
      final config = MihomoConfigGen.build(
        link,
        settings,
        socksPort: 2080,
        tun: const MihomoTunOptions(
          fromFileDescriptor: true,
          stack: 'gvisor',
          autoRoute: false,
        ),
      );
      final tun = config['tun'] as Map<String, dynamic>;

      expect(tun['enable'], isTrue);
      expect(tun.containsKey('device'), isFalse);
      expect(tun.containsKey('mtu'), isFalse);
      expect(tun.containsKey('file-descriptor'), isFalse);
      // Адреса и маршруты уже проставил VpnService, а netlink на Android 14+
      // ядру запрещён — с автодетектом листенер не поднялся бы вовсе.
      expect(tun['auto-route'], isFalse);
      expect(tun['auto-detect-interface'], isFalse);
      // Владельца соединения непривилегированный процесс на Android не узнает.
      expect(config['find-process-mode'], 'off');
    });

    test('HTTP-инбаунд поднимается только там, где его просят', () {
      final android =
          MihomoConfigGen.build(link, settings, socksPort: 2080);
      expect(android.containsKey('port'), isFalse);

      final desktop = MihomoConfigGen.build(
        link,
        settings,
        socksPort: 2080,
        httpPort: 2081,
      );
      expect(desktop['port'], 2081);
    });

    test('подсеть своего интерфейса — мимо туннеля', () {
      final rules = MihomoConfigGen.build(
        link,
        settings,
        socksPort: 2080,
        tun: desktopTun(),
        windows: true,
      )['rules'] as List;

      expect(rules, contains('IP-CIDR,198.18.0.0/30,DIRECT,no-resolve'));
    });
  });

  group('fake-ip', () {
    const link = 'vless://uuid@nl.example:443?type=tcp&security=none';
    final on = settings.copyWith(mihomoFakeIp: true);

    Map<String, dynamic> dnsOf(AppSettings s, {MihomoTunOptions? tun}) =>
        MihomoConfigGen.build(
          link,
          s,
          socksPort: 2080,
          httpPort: 2081,
          tun: tun,
          windows: true,
        )['dns'] as Map<String, dynamic>;

    test('включённая настройка со своим туннелем подменяет адреса', () {
      final dns = dnsOf(
        on,
        tun: const MihomoTunOptions(device: 'tun-keqdis', stack: 'gvisor'),
      );

      expect(dns['enhanced-mode'], 'fake-ip');
      expect(dns['fake-ip-range'], '198.18.0.1/16');
      // Локальные зоны и проверки связности — мимо подмены, иначе система
      // рисует «интернета нет» поверх работающего туннеля.
      expect(dns['fake-ip-filter'], contains('*.lan'));
      expect(dns['fake-ip-filter'], contains('connectivitycheck.gstatic.com'));
    });

    // Перехват DNS живёт в tun-блоке: без него подменный адрес некому вернуть
    // системе, и он же вернулся бы в правила как неизвестный IP.
    test('без своего туннеля настройка ничего не включает', () {
      final dns = dnsOf(on);
      expect(dns['enhanced-mode'], 'normal');
      expect(dns.containsKey('fake-ip-range'), isFalse);
    });

    test('выключенная настройка оставляет обычный резолв', () {
      final dns = dnsOf(
        settings,
        tun: const MihomoTunOptions(device: 'tun-keqdis', stack: 'gvisor'),
      );
      expect(dns['enhanced-mode'], 'normal');
    });

    // Ядро стирает подменный адрес перед выбором правила и восстанавливает
    // домен, поэтому IP-правилу с no-resolve сравнивать нечего — оно
    // промахивается всегда.
    test('пользовательские IP-правила теряют no-resolve', () {
      final rules = (MihomoConfigGen.build(
        link,
        on.copyWith(
          directRules: '10.8.0.0/24',
          // Снифер в режиме routeOnly — то есть прежнее условие снятия
          // no-resolve не выполнено, и решает именно fake-ip.
          xrayCore: const XrayCoreSettings(sniffingRouteOnly: true),
        ),
        socksPort: 2080,
        tun: const MihomoTunOptions(device: 'tun-keqdis', stack: 'gvisor'),
        windows: true,
      )['rules'] as List)
          .cast<String>();

      expect(rules, contains('IP-CIDR,10.8.0.0/24,DIRECT'));
      expect(rules, isNot(contains('IP-CIDR,10.8.0.0/24,DIRECT,no-resolve')));
    });

    // Правило против круга обязано решать без резолва при любых настройках:
    // резолв ради него — это тот же круг, только на шаг раньше.
    test('правило про сам сервер no-resolve не теряет', () {
      final rules = (MihomoConfigGen.build(
        link,
        on,
        socksPort: 2080,
        resolvedServerIp: '203.0.113.7',
        tun: const MihomoTunOptions(device: 'tun-keqdis', stack: 'gvisor'),
        windows: true,
      )['rules'] as List)
          .cast<String>();

      expect(rules, contains('IP-CIDR,203.0.113.7/32,DIRECT,no-resolve'));
    });
  });

  group('правила по процессам', () {
    const link = 'vless://uuid@nl.example:443?type=tcp&security=none';

    List<String> rulesFor({
      required AppRoutingMode mode,
      List<String> managed = const [],
    }) =>
        (MihomoConfigGen.build(
          link,
          settings,
          socksPort: 2080,
          httpPort: 2081,
          tun: const MihomoTunOptions(device: 'tun-keqdis', stack: 'gvisor'),
          routingMode: mode,
          managedProcessNames: managed,
          appProcessName: 'keqdroid.exe',
          windows: true,
        )['rules'] as List)
            .cast<String>();

    // Иначе tcp-пинг мерил бы локальный конец туннеля вместо сервера.
    test('свой процесс — первым правилом и мимо туннеля', () {
      final rules = rulesFor(mode: AppRoutingMode.allProxy);
      expect(rules.first, 'PROCESS-NAME,keqdroid.exe,DIRECT');
    });

    test('чужие VPN-клиенты не заворачиваются в туннель в туннеле', () {
      final rules = rulesFor(mode: AppRoutingMode.allProxy);
      expect(rules, contains('PROCESS-NAME,tailscaled.exe,DIRECT'));
      expect(rules, contains('PROCESS-NAME,openvpn.exe,DIRECT'));
    });

    // При пер-аппном сплите пользователь назвал приложения сам, и дописывать к
    // его списку свои нельзя.
    test('при сплите чужие VPN-клиенты не дописываются', () {
      final rules = rulesFor(
        mode: AppRoutingMode.allExceptSelected,
        managed: const ['Telegram.exe'],
      );
      expect(rules.any((r) => r.contains('tailscaled')), isFalse);
      expect(rules, contains('PROCESS-NAME,Telegram.exe,DIRECT'));
      // «Всё кроме выбранных» означает, что остальное идёт в туннель.
      expect(rules.last, 'MATCH,proxy');
    });

    test('«только выбранные» шлёт остальное напрямую', () {
      final rules = rulesFor(
        mode: AppRoutingMode.onlySelected,
        managed: const ['chrome.exe'],
      );
      expect(rules, contains('PROCESS-NAME,chrome.exe,proxy'));
      expect(rules.last, 'MATCH,DIRECT');
    });

    // Под tun2socks в инбаунд ходит ровно один процесс — он же был бы
    // «владельцем» всего, поэтому правил там нет вовсе.
    test('без своего туннеля правил по процессам не бывает', () {
      final config = MihomoConfigGen.build(
        link,
        settings,
        socksPort: 2080,
        managedProcessNames: const ['Telegram.exe'],
        appProcessName: 'keqdroid.exe',
      );
      expect(config['find-process-mode'], 'off');
      expect(
        (config['rules'] as List).any((r) => '$r'.startsWith('PROCESS-NAME')),
        isFalse,
      );
    });
  });

  // Смысл тот же, что у kill switch в sing-box: весь IP-трафик в прокси, а
  // финалом отказ — падение прокси не превращается в утечку мимо туннеля.
  group('kill switch', () {
    const link = 'vless://uuid@nl.example:443?type=tcp&security=none';

    test('весь трафик в прокси, финал — отказ', () {
      final rules = (MihomoConfigGen.build(
        link,
        settings.copyWith(killSwitch: true),
        socksPort: 2080,
        httpPort: 2081,
        tun: const MihomoTunOptions(device: 'tun-keqdis', stack: 'gvisor'),
        windows: true,
      )['rules'] as List)
          .cast<String>();

      expect(rules, contains('IP-CIDR,0.0.0.0/1,proxy'));
      expect(rules, contains('IP-CIDR,128.0.0.0/1,proxy'));
      expect(rules.last, 'MATCH,REJECT');
    });

    // Финал у них и так не proxy: гнать всё в туннель ради отказа бессмысленно.
    test('при обходе и блокировке не применяется', () {
      for (final finalOutbound in const [
        AppSettings.finalOutboundDirect,
        AppSettings.finalOutboundBlock,
      ]) {
        final rules = (MihomoConfigGen.build(
          link,
          settings.copyWith(killSwitch: true, finalOutbound: finalOutbound),
          socksPort: 2080,
          tun: const MihomoTunOptions(device: 'tun-keqdis', stack: 'gvisor'),
          windows: true,
        )['rules'] as List)
            .cast<String>();
        expect(rules.any((r) => r.startsWith('IP-CIDR,0.0.0.0/1')), isFalse);
      }
    });
  });

  test('generate отдаёт валидный JSON (он же YAML для ядра)', () {
    final raw = MihomoConfigGen.generate(
      'vless://uuid@nl.example:443?type=tcp&security=reality&pbk=k&sid=aa',
      settings,
      socksPort: 2080,
    );
    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    expect(parsed['proxies'], isA<List>());
    expect(parsed['rules'], isA<List>());
  });
}
