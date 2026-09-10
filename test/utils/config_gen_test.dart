import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

void main() {
  const settings = AppSettings();

    test('переносит vcn и pcs из ссылки в tlsSettings', () {
      // Регрессия с живого сервера: панель отдаёт `sni` чужого домена, а
      // сертификат велит проверять по настоящему имени и по отпечаткам. Пока мы
      // эти два поля выбрасывали, ядро сверяло сертификат с маскировочным `sni`
      // и роняло рукопожатие — сервер работал во всех клиентах, кроме нашего.
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'vless://uuid@vps1.example.org:8443?security=tls&type=tcp'
        '&sni=spotify.com&fp=chrome&vcn=vps1.example.org'
        '&pcs=c88234050d72a3e9430ec7738636806deaf85c3708fee0fd9202ebd917e2c843'
        '%2Ca2372d06431e9716365eeed47ec020351497d182fcc038e457e58168a03cac07'
        '#demo',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final outbound = (map['outbounds'] as List).first as Map<String, dynamic>;
      final tls = (outbound['streamSettings']
          as Map<String, dynamic>)['tlsSettings'] as Map<String, dynamic>;

      expect(tls['serverName'], 'spotify.com');
      expect(tls['verifyPeerCertByName'], 'vps1.example.org');
      // Список отпечатков ядро принимает одной строкой через запятую и само
      // режет её на части — склеивать или разбирать нам нечего.
      expect(
        tls['pinnedPeerCertSha256'],
        'c88234050d72a3e9430ec7738636806deaf85c3708fee0fd9202ebd917e2c843,'
        'a2372d06431e9716365eeed47ec020351497d182fcc038e457e58168a03cac07',
      );
    });

    test('без vcn и pcs пустых полей в tlsSettings не появляется', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'vless://uuid@example.com:443?security=tls&type=tcp&sni=example.com#d',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final outbound = (map['outbounds'] as List).first as Map<String, dynamic>;
      final tls = (outbound['streamSettings']
          as Map<String, dynamic>)['tlsSettings'] as Map<String, dynamic>;

      expect(tls.containsKey('verifyPeerCertByName'), isFalse);
      expect(tls.containsKey('pinnedPeerCertSha256'), isFalse);
    });

    test('type=raw получает http-заголовок так же, как type=tcp', () {
      // `raw` — новое имя транспорта в ядре, и ссылки с ним уже ходят.
      // mihomo-генератор считал их одним транспортом давно, xray-генератор нет:
      // маскировка под http молча терялась.
      Socks5Credentials().init('u', 'p');
      Map<String, dynamic> streamFor(String type) {
        final config = ConfigGeneratorV2.generateConfig(
          'vless://uuid@example.com:443?type=$type&headerType=http'
          '&host=cdn.example.com&security=none#d',
          settings,
        );
        final map = jsonDecode(config) as Map<String, dynamic>;
        final outbound =
            (map['outbounds'] as List).first as Map<String, dynamic>;
        return outbound['streamSettings'] as Map<String, dynamic>;
      }

      for (final type in ['tcp', 'raw']) {
        final tcp = streamFor(type)['tcpSettings'] as Map<String, dynamic>?;
        expect(tcp, isNotNull, reason: type);
        final header = tcp!['header'] as Map<String, dynamic>;
        expect(header['type'], 'http');
      }
    });

    test('reality: pqv доезжает как mldsa65Verify', () {
      // Без ключа соединение встаёт, но без дополнительной post-quantum
      // проверки — то есть тише, чем просил выдавший ссылку.
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'vless://uuid@example.com:443?security=reality&pbk=pub&sid=12'
        '&fp=chrome&sni=example.com&type=tcp&pqv=BASE64KEY#d',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final outbound = (map['outbounds'] as List).first as Map<String, dynamic>;
      final reality = (outbound['streamSettings']
          as Map<String, dynamic>)['realitySettings'] as Map<String, dynamic>;

      expect(reality['mldsa65Verify'], 'BASE64KEY');
    });

  group('ConfigGeneratorV2', () {
    test('builds VLESS reality settings', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'vless://uuid@example.com:443?security=reality&pbk=pub&sid=12&spx=/x&fp=chrome&sni=example.com&type=tcp#demo',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final outbound = (map['outbounds'] as List).first as Map<String, dynamic>;
      final stream = outbound['streamSettings'] as Map<String, dynamic>;
      final reality = stream['realitySettings'] as Map<String, dynamic>;

      expect(reality['publicKey'], 'pub');
      expect(reality['shortId'], '12');
      expect(reality['spiderX'], '/x');
    });

    test('builds VMess outbound from base64 payload', () {
      Socks5Credentials().init('u', 'p');
      final payload = base64.encode(utf8.encode(jsonEncode({
        'v': '2',
        'ps': 'demo',
        'add': 'example.com',
        'port': '443',
        'id': '11111111-1111-1111-1111-111111111111',
        'aid': '0',
        'net': 'ws',
        'type': 'none',
        'host': 'example.com',
        'path': '/ws',
        'tls': 'tls',
      })));
      final config = ConfigGeneratorV2.generateConfig('vmess://$payload', settings);
      final map = jsonDecode(config) as Map<String, dynamic>;
      final outbound = (map['outbounds'] as List).first as Map<String, dynamic>;
      final settings2 = outbound['settings'] as Map<String, dynamic>;
      // Новая структура: address/port/id вместо vnext
      expect(settings2['address'], 'example.com');
      expect(settings2['port'], 443);
      expect(settings2['id'], '11111111-1111-1111-1111-111111111111');
    });

    test('VMess TLS без fp получает firefox', () {
      Socks5Credentials().init('u', 'p');
      final payload = base64.encode(utf8.encode(jsonEncode({
        'v': '2',
        'add': 'example.com',
        'port': '443',
        'id': '11111111-1111-1111-1111-111111111111',
        'aid': '0',
        'net': 'tcp',
        'tls': 'tls',
        'sni': 'example.com',
      })));
      final config = ConfigGeneratorV2.generateConfig('vmess://$payload', settings);
      final map = jsonDecode(config) as Map<String, dynamic>;
      final stream = ((map['outbounds'] as List).first as Map)['streamSettings'] as Map<String, dynamic>;
      final tls = stream['tlsSettings'] as Map<String, dynamic>;
      expect(tls['fingerprint'], 'firefox');
    });

    test('builds VMess outbound from url-safe base64 payload', () {
      Socks5Credentials().init('u', 'p');
      final raw = utf8.encode(jsonEncode({
        'add': 'vmess.example.com',
        'port': '443',
        'id': '22222222-2222-2222-2222-222222222222',
        'aid': '0',
        'scy': 'chacha20-poly1305',
        'net': 'tcp',
        'tls': 'none',
      }));
      final payload = base64Url.encode(raw).replaceAll('=', '');
      final config = ConfigGeneratorV2.generateConfig('vmess://$payload', settings);
      final map = jsonDecode(config) as Map<String, dynamic>;
      final outbound = (map['outbounds'] as List).first as Map<String, dynamic>;
      final settings2 = outbound['settings'] as Map<String, dynamic>;
      // Новая структура: address/port/id вместо vnext
      expect(settings2['address'], 'vmess.example.com');
      expect(settings2['security'], 'chacha20-poly1305');
    });

    test('builds Shadowsocks outbound from plaintext userinfo URI', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'ss://aes-256-gcm:myPass@example.com:8388#demo',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final outbound = (map['outbounds'] as List).first as Map<String, dynamic>;
      final settings2 = outbound['settings'] as Map<String, dynamic>;
      // Новая структура: address/port/method/password
      expect(settings2['address'], 'example.com');
      expect(settings2['port'], 8388);
      expect(settings2['method'], 'aes-256-gcm');
      expect(settings2['password'], 'myPass');
    });

    test('builds Shadowsocks outbound from SIP002 base64 format', () {
      Socks5Credentials().init('u', 'p');
      // SIP002: ss://BASE64(method:password)@host:port
      final userInfo = base64Url.encode(utf8.encode('chacha20-ietf-poly1305:secret')).replaceAll('=', '');
      final config = ConfigGeneratorV2.generateConfig(
        'ss://$userInfo@example.net:443',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final outbound = (map['outbounds'] as List).first as Map<String, dynamic>;
      final settings2 = outbound['settings'] as Map<String, dynamic>;
      // Новая структура: address/port/method/password
      expect(settings2['address'], 'example.net');
      expect(settings2['port'], 443);
      expect(settings2['method'], 'chacha20-ietf-poly1305');
      expect(settings2['password'], 'secret');
    });

    test('throws on invalid shadowsocks payload', () {
      expect(
        () => ConfigGeneratorV2.generateConfig('ss://broken', settings),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('builds Hysteria/HY2 outbound (network hysteria for Xray 26+)', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'hysteria://example.com:443?auth=secret&insecure=0&sni=example.com',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final outbound = (map['outbounds'] as List).first as Map<String, dynamic>;
      expect(outbound['protocol'], 'hysteria');
      final stream = outbound['streamSettings'] as Map<String, dynamic>;
      expect(stream['network'], 'hysteria');
      expect(stream['security'], 'tls');
    });

    // Решение хозяйки: первую версию не поддерживаем. Молчаливая сборка её как
    // второй давала конфиг не того протокола и сервер, который не отвечает.
    test('Hysteria v1 отклоняется, а не собирается как вторая', () {
      Socks5Credentials().init('u', 'p');
      expect(
        () => ConfigGeneratorV2.generateConfig(
          'hysteria://host:443?auth=secret&upmbps=100&downmbps=200&peer=sni.example',
          settings,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    // Разбор запроса по правилам HTML-формы читает `+` как пробел, и base64
    // приезжает испорченным: ядру это неотличимо от неверного ключа.
    test('плюс в base64-параметрах ссылки остаётся плюсом', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'vless://uuid@198.51.100.10:443?type=tcp&security=tls&sni=e.example'
        '&ech=AA+BB/CC=&pcs=QQ+WW/EE=',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final outbound = (map['outbounds'] as List).first as Map<String, dynamic>;
      final tls = (outbound['streamSettings'] as Map)['tlsSettings'] as Map;
      expect(tls['echConfigList'], 'AA+BB/CC=');
      expect(tls['pinnedPeerCertSha256'], 'QQ+WW/EE=');
    });

    // Список портов прямо в адресе `Uri.parse` не берёт, и раньше ссылка
    // разваливалась целиком — вместе с sni, obfs и всем остальным.
    test('hysteria2: список портов из адреса не ломает разбор ссылки', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'hysteria2://password@198.51.100.16:20000-20050,443?sni=hy2.example',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final outbound = (map['outbounds'] as List).first as Map<String, dynamic>;
      final stream = outbound['streamSettings'] as Map<String, dynamic>;
      final hysteria = stream['hysteriaSettings'] as Map<String, dynamic>;
      expect((hysteria['udphop'] as Map)['ports'], '20000-20050,443');
      expect((stream['tlsSettings'] as Map)['serverName'], 'hy2.example');
    });

    test('killSwitch does not add split rules to xray routing', () {
      // Правило 0.0.0.0/1+128.0.0.0/1 → proxy было no-op (catch-all ниже и так
      // шлёт всё в proxy); настоящий kill switch — final: block в sing-box
      // TUN-конфиге (см. singbox_tun_config_test.dart).
      Socks5Credentials().init('u', 'p');
      for (final s in [settings, AppSettings(killSwitch: true)]) {
        final config = ConfigGeneratorV2.generateConfig(
          'vless://uuid@example.com:443',
          s,
        );
        final map = jsonDecode(config) as Map<String, dynamic>;
        final rules = (map['routing'] as Map)['rules'] as List;
        final hasKillSwitch = rules.any((r) =>
          (r['ip'] as List?)?.contains('0.0.0.0/1') == true);
        expect(hasKillSwitch, false);
      }
    });

    test('custom direct CIDR bumps domainStrategy to IPIfNonMatch', () {
      Socks5Credentials().init('u', 'p');
      // корпоративный диапазон в Direct: должен ловиться и по имени хоста,
      // а не только по голому IP — для этого нужен IPIfNonMatch.
      final s = AppSettings(directRules: 'ru, 10.130.0.0/16');
      final config =
          ConfigGeneratorV2.generateConfig('vless://uuid@example.com:443', s);
      final map = jsonDecode(config) as Map<String, dynamic>;
      expect((map['routing'] as Map)['domainStrategy'], 'IPIfNonMatch');
      // и сам CIDR присутствует как direct-правило
      final rules = (map['routing'] as Map)['rules'] as List;
      final hasCidr = rules.any((r) =>
          (r['ip'] as List?)?.contains('10.130.0.0/16') == true &&
          r['outboundTag'] == 'direct');
      expect(hasCidr, true);
    });

    test('domainStrategy stays AsIs without custom IP rules', () {
      Socks5Credentials().init('u', 'p');
      // дефолтные правила = только доменные суффиксы + приватные LAN → AsIs
      final config =
          ConfigGeneratorV2.generateConfig('vless://uuid@example.com:443', settings);
      final map = jsonDecode(config) as Map<String, dynamic>;
      expect((map['routing'] as Map)['domainStrategy'], 'AsIs');
    });

    test('LAN inbounds are noauth without credentials', () {
      Socks5Credentials().init('u', 'p');
      const s = AppSettings(lanSharing: true);
      final config =
          ConfigGeneratorV2.generateConfig('vless://uuid@example.com:443', s);
      final map = jsonDecode(config) as Map<String, dynamic>;
      final inbounds =
          (map['inbounds'] as List).cast<Map<String, dynamic>>();

      final socksLan = inbounds.firstWhere((i) => i['tag'] == 'socks-lan');
      expect((socksLan['settings'] as Map)['auth'], 'noauth');
      expect((socksLan['settings'] as Map).containsKey('accounts'), isFalse);

      final httpLan = inbounds.firstWhere((i) => i['tag'] == 'http-lan');
      expect((httpLan['settings'] as Map).containsKey('accounts'), isFalse);
    });

    test('LAN inbounds require password when both credentials are set', () {
      Socks5Credentials().init('u', 'p');
      const s = AppSettings(
        lanSharing: true,
        lanUsername: 'lan-user',
        lanPassword: 'lan-pass',
      );
      final config =
          ConfigGeneratorV2.generateConfig('vless://uuid@example.com:443', s);
      final map = jsonDecode(config) as Map<String, dynamic>;
      final inbounds =
          (map['inbounds'] as List).cast<Map<String, dynamic>>();

      final socksLan = inbounds.firstWhere((i) => i['tag'] == 'socks-lan');
      expect((socksLan['settings'] as Map)['auth'], 'password');
      expect((socksLan['settings'] as Map)['accounts'],
          [{'user': 'lan-user', 'pass': 'lan-pass'}]);
      // UDP-режим SOCKS сохраняется и с паролем
      expect((socksLan['settings'] as Map)['udp'], isTrue);

      final httpLan = inbounds.firstWhere((i) => i['tag'] == 'http-lan');
      expect((httpLan['settings'] as Map)['accounts'],
          [{'user': 'lan-user', 'pass': 'lan-pass'}]);

      // локальные loopback-инбаунды не затронуты LAN-кредами
      final socksIn = inbounds.firstWhere((i) => i['tag'] == 'socks-in');
      final accounts =
          ((socksIn['settings'] as Map)['accounts'] as List).cast<Map>();
      expect(accounts.single['user'], 'u');
    });

    test('half-filled LAN credentials fall back to noauth', () {
      Socks5Credentials().init('u', 'p');
      const s = AppSettings(lanSharing: true, lanUsername: 'only-user');
      final config =
          ConfigGeneratorV2.generateConfig('vless://uuid@example.com:443', s);
      final map = jsonDecode(config) as Map<String, dynamic>;
      final socksLan = ((map['inbounds'] as List).cast<Map<String, dynamic>>())
          .firstWhere((i) => i['tag'] == 'socks-lan');
      expect((socksLan['settings'] as Map)['auth'], 'noauth');
    });

    test('newline-separated routing lists parse per line, same as commas', () {
      Socks5Credentials().init('u', 'p');
      // UI обещает «по одному в строке или через запятую»; сплит только по ','
      // склеивал построчные записи в один несрабатывающий domain-токен.
      const s = AppSettings(directRules: 'yandex.ru\nvk.com\n192.168.50.0/24');
      final config =
          ConfigGeneratorV2.generateConfig('vless://uuid@example.com:443', s);
      final map = jsonDecode(config) as Map<String, dynamic>;
      final rules =
          ((map['routing'] as Map)['rules'] as List).cast<Map<String, dynamic>>();

      final domainRule = rules.firstWhere((r) =>
          r['outboundTag'] == 'direct' &&
          (r['domain'] as List?)?.contains('domain:yandex.ru') == true);
      expect(domainRule['domain'], contains('domain:vk.com'));
      expect(
        (domainRule['domain'] as List).any((d) => (d as String).contains('\n')),
        isFalse,
      );

      final hasCidr = rules.any((r) =>
          r['outboundTag'] == 'direct' &&
          (r['ip'] as List?)?.contains('192.168.50.0/24') == true);
      expect(hasCidr, true);
    });

    test('builds Trojan outbound with TLS', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'trojan://password@example.com:443?sni=example.com&fp=chrome&type=tcp',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final outbound = (map['outbounds'] as List).first as Map<String, dynamic>;
      expect(outbound['protocol'], 'trojan');
      final settings2 = outbound['settings'] as Map<String, dynamic>;
      expect(settings2['address'], 'example.com');
      expect(settings2['port'], 443);
      expect(settings2['password'], 'password');
      final stream = outbound['streamSettings'] as Map<String, dynamic>;
      expect(stream['security'], 'tls');
      expect(stream['network'], 'tcp');
      final tlsSettings = stream['tlsSettings'] as Map<String, dynamic>;
      expect(tlsSettings['serverName'], 'example.com');
    });

    // Ядро отвергает `allowInsecure` безусловно и роняет при этом разбор всего
    // конфига — подробности и остальные протоколы в removed_tls_fields_test.
    test('Trojan TLS drops allowInsecure even when insecure=1', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'trojan://password@example.com:443?sni=example.com&type=tcp&insecure=1',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final stream = ((map['outbounds'] as List).first as Map)['streamSettings'] as Map<String, dynamic>;
      final tls = stream['tlsSettings'] as Map<String, dynamic>;
      expect(tls.containsKey('allowInsecure'), isFalse);
      expect(tls['serverName'], 'example.com');
    });

    // Пустое поле ядро читает как Chrome (`GetFingerprint("")`), а он на наших
    // сетях уходит в тишину, поэтому пишем свой отпечаток — как и для REALITY.
    test('VLESS TLS без fp получает firefox', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'vless://5783a3e7-e373-51cd-8642-c83782b807c5@example.com:443?encryption=none&security=tls&sni=example.com&type=tcp',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final stream = ((map['outbounds'] as List).first as Map)['streamSettings'] as Map<String, dynamic>;
      final tls = stream['tlsSettings'] as Map<String, dynamic>;
      expect(tls['fingerprint'], 'firefox');
    });

    test('Trojan TLS без fp получает firefox', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'trojan://password@example.com:443?sni=example.com&type=tcp',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final stream = ((map['outbounds'] as List).first as Map)['streamSettings'] as Map<String, dynamic>;
      final tls = stream['tlsSettings'] as Map<String, dynamic>;
      expect(tls['fingerprint'], 'firefox');
    });

    // У hysteria рукопожатие QUIC: отпечаток ядро там не применяет, и писать
    // его незачем.
    test('Hysteria2 без fp отпечатка не получает', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'hy2://secret@example.com:443?sni=example.com',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final stream = ((map['outbounds'] as List).first as Map)['streamSettings'] as Map<String, dynamic>;
      final tls = stream['tlsSettings'] as Map<String, dynamic>;
      expect(tls.containsKey('fingerprint'), isFalse);
    });

    // Ссылки на reality часто приходят без `fp`, и отпечаток в этом случае
    // выбираем мы (см. `defaultTlsFingerprint`).
    test('REALITY без fp получает firefox, а не chrome', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'vless://uuid@nl.example:443?security=reality&type=tcp'
        '&sni=decoy.example&pbk=publickey&sid=aabb',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final stream = ((map['outbounds'] as List).first as Map)['streamSettings']
          as Map<String, dynamic>;
      final reality = stream['realitySettings'] as Map<String, dynamic>;
      expect(reality['fingerprint'], 'firefox');
    });

    test('REALITY с fp из ссылки его и оставляет', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'vless://uuid@nl.example:443?security=reality&type=tcp'
        '&sni=decoy.example&pbk=publickey&sid=aabb&fp=chrome',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final stream = ((map['outbounds'] as List).first as Map)['streamSettings']
          as Map<String, dynamic>;
      final reality = stream['realitySettings'] as Map<String, dynamic>;
      expect(reality['fingerprint'], 'chrome');
    });

    // Скачивание по downloadSettings — отдельное подключение со своим TLS.
    test('downloadSettings без fp получает тот же отпечаток', () {
      Socks5Credentials().init('u', 'p');
      const extra = '{"downloadSettings":{"address":"dl.example","port":443,'
          '"network":"xhttp","security":"tls",'
          '"tlsSettings":{"serverName":"dl.example"}}}';
      final config = ConfigGeneratorV2.generateConfig(
        'vless://uuid@x.example:443?security=tls&type=xhttp&sni=x.example'
        '&extra=${Uri.encodeQueryComponent(extra)}',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final stream = ((map['outbounds'] as List).first as Map)['streamSettings']
          as Map<String, dynamic>;
      final download = ((stream['xhttpSettings'] as Map)['extra']
          as Map)['downloadSettings'] as Map;
      expect(download['tlsSettings'],
          {'serverName': 'dl.example', 'fingerprint': 'firefox'});
    });

    test('downloadSettings с fp из ссылки его и оставляет', () {
      Socks5Credentials().init('u', 'p');
      const extra = '{"downloadSettings":{"address":"dl.example","port":443,'
          '"network":"xhttp","security":"reality",'
          '"realitySettings":{"publicKey":"pk","fingerprint":"safari"}}}';
      final config = ConfigGeneratorV2.generateConfig(
        'vless://uuid@x.example:443?security=tls&type=xhttp&sni=x.example'
        '&extra=${Uri.encodeQueryComponent(extra)}',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final stream = ((map['outbounds'] as List).first as Map)['streamSettings']
          as Map<String, dynamic>;
      final download = ((stream['xhttpSettings'] as Map)['extra']
          as Map)['downloadSettings'] as Map;
      expect((download['realitySettings'] as Map)['fingerprint'], 'safari');
    });

    test('VLESS TLS keeps the fingerprint named by the link', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'vless://5783a3e7-e373-51cd-8642-c83782b807c5@example.com:443?encryption=none&security=tls&sni=example.com&type=tcp&fp=firefox',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final stream = ((map['outbounds'] as List).first as Map)['streamSettings'] as Map<String, dynamic>;
      final tls = stream['tlsSettings'] as Map<String, dynamic>;
      expect(tls['fingerprint'], 'firefox');
    });

    // Строку постквантового шифрования разбирает само ядро, и разбирает её по
    // длинам: ключ обязан декодироваться в 32 или 1184 байта, а всё короткое
    // между точками считается паддингом. Любая правка строки по пути — и ядро
    // отвечает «unsupported encryption», поэтому переносим дословно.
    test('VLESS переносит строку encryption дословно', () {
      Socks5Credentials().init('u', 'p');
      const encryption =
          'mlkem768x25519plus.xorpub.0rtt.TQWG00S9SOQfvBRqDpXGzHBAagxTkExzd';
      final config = ConfigGeneratorV2.generateConfig(
        'vless://5783a3e7-e373-51cd-8642-c83782b807c5@example.com:443'
        '?encryption=$encryption&security=tls&sni=example.com&type=tcp',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final outbound = (map['outbounds'] as List).first as Map<String, dynamic>;
      final vless = outbound['settings'] as Map<String, dynamic>;
      expect(vless['encryption'], encryption);
    });

    test('builds Trojan outbound with WebSocket', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'trojan://mypassword@trojan.example.net:8443?sni=trojan.example.net&type=ws&path=/ws&host=trojan.example.net',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final outbound = (map['outbounds'] as List).first as Map<String, dynamic>;
      expect(outbound['protocol'], 'trojan');
      final stream = outbound['streamSettings'] as Map<String, dynamic>;
      expect(stream['network'], 'ws');
      final wsSettings = stream['wsSettings'] as Map<String, dynamic>;
      expect(wsSettings['path'], '/ws');
    });

    test('builds Trojan outbound with gRPC', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'trojan://grpcpass@grpc.example.com:443?sni=grpc.example.com&type=grpc&serviceName=h2c',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final outbound = (map['outbounds'] as List).first as Map<String, dynamic>;
      final stream = outbound['streamSettings'] as Map<String, dynamic>;
      expect(stream['network'], 'grpc');
      final grpcSettings = stream['grpcSettings'] as Map<String, dynamic>;
      expect(grpcSettings['serviceName'], 'h2c');
    });

    test('builds Hysteria2 (hy2://) outbound', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'hy2://example.com:443?auth=hy2secret&sni=example.com&insecure=0',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final outbound = (map['outbounds'] as List).first as Map<String, dynamic>;
      expect(outbound['protocol'], 'hysteria');
      final settings2 = outbound['settings'] as Map<String, dynamic>;
      expect(settings2['version'], 2);
      final stream = outbound['streamSettings'] as Map<String, dynamic>;
      expect(stream['network'], 'hysteria');
      expect(stream['security'], 'tls');
      final hysteriaSettings = stream['hysteriaSettings'] as Map<String, dynamic>;
      expect(hysteriaSettings['version'], 2);
      expect(hysteriaSettings['auth'], 'hy2secret');
    });

    test('Hysteria2 auth from userInfo when query has no auth', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'hy2://hy2secret@example.com:443?sni=example.com&insecure=0',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final outbound = (map['outbounds'] as List).first as Map<String, dynamic>;
      final hysteriaSettings = (outbound['streamSettings'] as Map)['hysteriaSettings'] as Map<String, dynamic>;
      expect(hysteriaSettings['auth'], 'hy2secret');
    });

    test('Hysteria2 with salamander obfs and default alpn h3', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'hy2://secret@example.com:443?obfs=salamander&obfs-password=test123&sni=example.com',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final stream =
          ((map['outbounds'] as List).first as Map)['streamSettings'] as Map<String, dynamic>;
      final tls = stream['tlsSettings'] as Map<String, dynamic>;
      expect(tls['alpn'], ['h3']);
      final finalmask = stream['finalmask'] as Map<String, dynamic>;
      final udp = finalmask['udp'] as List;
      expect((udp.first as Map)['type'], 'salamander');
      expect(
        ((udp.first as Map)['settings'] as Map)['password'],
        'test123',
      );
    });

    test('hysteria2:// scheme with tls fp alpn ech (share link style)', () {
      Socks5Credentials().init('u', 'p');
      final uri =
          'hysteria2://fake-auth-token@proxy.example.com:443?security=tls&fp=chrome&alpn=h3&ech=AGb%2BDQBiAAAgACBn&sni=proxy.example.com#demo';
      final config = ConfigGeneratorV2.generateConfig(uri, settings);
      final map = jsonDecode(config) as Map<String, dynamic>;
      final outbound = (map['outbounds'] as List).first as Map<String, dynamic>;
      expect(outbound['protocol'], 'hysteria');
      final stream = outbound['streamSettings'] as Map<String, dynamic>;
      expect(stream['network'], 'hysteria');
      expect(stream.containsKey('quicSettings'), isFalse);
      final tls = stream['tlsSettings'] as Map<String, dynamic>;
      expect(tls['fingerprint'], 'chrome');
      expect(tls['alpn'], ['h3']);
      expect(tls['echConfigList'], isA<String>());
      expect(tls['echConfigList'] as String, contains('AGb'));
      final hysteriaSettings = stream['hysteriaSettings'] as Map<String, dynamic>;
      expect(hysteriaSettings['auth'], 'fake-auth-token');
      expect(hysteriaSettings['version'], 2);
    });

    test('builds VLESS with XTLS and flow', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'vless://uuid@example.com:443?security=xtls&flow=xtls-rprx-vision&sni=example.com&type=tcp',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final outbound = (map['outbounds'] as List).first as Map<String, dynamic>;
      expect(outbound['protocol'], 'vless');
      final settings2 = outbound['settings'] as Map<String, dynamic>;
      expect(settings2['flow'], 'xtls-rprx-vision');
    });

    test('builds VLESS with WebSocket', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'vless://uuid@ws.example.com:443?type=ws&path=/vless&host=ws.example.com&security=tls&sni=ws.example.com',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final outbound = (map['outbounds'] as List).first as Map<String, dynamic>;
      final stream = outbound['streamSettings'] as Map<String, dynamic>;
      expect(stream['network'], 'ws');
      final wsSettings = stream['wsSettings'] as Map<String, dynamic>;
      expect(wsSettings['path'], '/vless');
    });

    test('builds VLESS with gRPC multiMode', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'vless://uuid@grpc.example.com:443?type=grpc&serviceName=grpc-service&mode=multi&security=tls&sni=grpc.example.com',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final outbound = (map['outbounds'] as List).first as Map<String, dynamic>;
      final stream = outbound['streamSettings'] as Map<String, dynamic>;
      expect(stream['network'], 'grpc');
      final grpcSettings = stream['grpcSettings'] as Map<String, dynamic>;
      expect(grpcSettings['serviceName'], 'grpc-service');
      expect(grpcSettings['multiMode'], true);
    });

    test('geoip:ru preset emits ip rule with geoip token, no bare geoip field', () {
      Socks5Credentials().init('u', 'p');
      final geoSettings = const AppSettings(directRules: 'geoip:ru');
      final config = ConfigGeneratorV2.generateConfig(
        'vless://uuid@example.com:443?type=tcp',
        geoSettings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final rules = (map['routing'] as Map)['rules'] as List;
      // xray matches geoip via the `ip` field (`geoip:ru`), never a top-level
      // `geoip` key — a bare `geoip` rule trips "this rule has no effective fields".
      final geoRule = rules.cast<Map<String, dynamic>>().firstWhere(
        (r) =>
            r['outboundTag'] == 'direct' &&
            (r['ip'] as List?)?.contains('geoip:ru') == true,
        orElse: () => <String, dynamic>{},
      );
      expect(geoRule['ip'], contains('geoip:ru'));
      expect(geoRule['outboundTag'], 'direct');
      // No rule may carry a bare `geoip` field — xray ignores it.
      final badGeoRule = rules.cast<Map<String, dynamic>>().where(
        (r) => r['geoip'] != null,
      );
      expect(badGeoRule, isEmpty);
    });

    test('throws on unsupported protocol', () {
      Socks5Credentials().init('u', 'p');
      expect(
        () => ConfigGeneratorV2.generateConfig('ssh://user@example.com', settings),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws on VLESS without UUID', () {
      Socks5Credentials().init('u', 'p');
      expect(
        () => ConfigGeneratorV2.generateConfig('vless://@example.com:443', settings),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws on Trojan without password', () {
      Socks5Credentials().init('u', 'p');
      expect(
        () => ConfigGeneratorV2.generateConfig('trojan://@example.com:443', settings),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws on Hysteria without auth', () {
      Socks5Credentials().init('u', 'p');
      expect(
        () => ConfigGeneratorV2.generateConfig('hysteria://example.com:443', settings),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('applies custom DNS and log level from xray core settings', () {
      Socks5Credentials().init('u', 'p');
      const core = XrayCoreSettings(
        logLevel: 'debug',
        dnsUseCustom: true,
        dnsServers: 'https://dns.google/dns-query',
        dnsQueryStrategy: 'PreferIPv4',
        routingDomainStrategy: 'IPIfNonMatch',
      );
      final config = ConfigGeneratorV2.generateConfig(
        'vless://uuid@example.com:443?type=tcp',
        const AppSettings(xrayCore: core),
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      expect((map['log'] as Map)['loglevel'], 'debug');
      final dns = map['dns'] as Map<String, dynamic>;
      expect(dns['queryStrategy'], 'PreferIPv4');
      final servers = (dns['servers'] as List).cast<Map<String, dynamic>>();
      // Первым идёт bootstrap на адрес сервера: его нельзя резолвить ничем, что
      // само требует туннеля, — отсюда `+local`. Открытым UDP-53 его тоже не
      // ищем: у части провайдеров он подменяется. Поэтому пользовательский
      // `https://` для bootstrap приводится к `https+local://`, а в общем списке
      // остаётся как вписан. Пользовательские серверы — следом.
      expect(servers.first['address'], 'https+local://dns.google/dns-query');
      expect(servers.first['domains'], ['full:example.com']);
      expect(servers[1]['address'], 'localhost');
      expect(servers[1]['finalQuery'], isTrue);
      expect(
        servers.map((s) => s['address']),
        contains('https://dns.google/dns-query'),
      );
      expect((map['routing'] as Map)['domainStrategy'], 'IPIfNonMatch');
    });

    test('generatePingConfig uses local HTTP inbound on ephemeral port', () {
      // HTTP, not SOCKS: the Dart probe uses dart:io HttpClient, whose findProxy
      // can only speak 'PROXY host:port' (HTTP CONNECT), never SOCKS.
      Socks5Credentials().init('u', 'p');
      const port = 28999;
      final config = ConfigGeneratorV2.generatePingConfig(
        'vless://uuid@example.com:443?type=tcp',
        settings,
        socksPort: port,
        httpInbound: true,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final inbound = (map['inbounds'] as List).first as Map<String, dynamic>;
      expect(inbound['port'], port);
      expect(inbound['protocol'], 'http');
      final httpSettings = inbound['settings'] as Map<String, dynamic>;
      expect(httpSettings['allowTransparent'], false);
      expect(map['inbounds'].length, 1);
      expect((map['log'] as Map)['loglevel'], 'none');
      final dns = map['dns'] as Map<String, dynamic>;
      expect(dns['queryStrategy'], 'UseIPv4');
      expect((map['routing'] as Map)['domainStrategy'], 'AsIs');
    });

    test('generatePingConfig defaults to noauth SOCKS inbound (Android probe)', () {
      // Android's Java probe uses Proxy.Type.SOCKS, so without httpInbound the
      // ephemeral ping must expose a noauth SOCKS inbound.
      Socks5Credentials().init('u', 'p');
      const port = 28999;
      final config = ConfigGeneratorV2.generatePingConfig(
        'vless://uuid@example.com:443?type=tcp',
        settings,
        socksPort: port,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final inbound = (map['inbounds'] as List).first as Map<String, dynamic>;
      expect(inbound['port'], port);
      expect(inbound['protocol'], 'socks');
      expect((inbound['settings'] as Map)['auth'], 'noauth');
      expect(map['inbounds'].length, 1);
    });

    test('injects xmux into xhttp extra when enabled', () {
      Socks5Credentials().init('u', 'p');
      const core = XrayCoreSettings(
        xmuxEnabled: true,
        xmuxMaxConcurrency: '16-32',
        xmuxHMaxRequestTimes: '600-900',
      );
      final config = ConfigGeneratorV2.generateConfig(
        'vless://uuid@example.com:443?type=xhttp&path=/xhttp&mode=auto',
        const AppSettings(xrayCore: core),
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final stream =
          ((map['outbounds'] as List).first as Map)['streamSettings'] as Map;
      final xhttp = stream['xhttpSettings'] as Map<String, dynamic>;
      final extra = xhttp['extra'] as Map<String, dynamic>;
      final xmux = extra['xmux'] as Map<String, dynamic>;
      expect(xmux['maxConcurrency'], '16-32');
      expect(xmux['hMaxRequestTimes'], '600-900');
    });
  });
}

