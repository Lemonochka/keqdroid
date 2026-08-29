import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

void main() {
  const settings = AppSettings();

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

    test('VMess TLS omits empty fingerprint (Xray 26 TLSConfig)', () {
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
      expect(tls.containsKey('fingerprint'), isFalse);
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

    // Пустое поле ядро само читает как HelloChrome_Auto (`GetFingerprint("")`),
    // так что дописывать сюда `chrome` нечего — это ровно дефолт ядра.
    test('VLESS TLS omits fingerprint when fp not set (Xray 26)', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'vless://5783a3e7-e373-51cd-8642-c83782b807c5@example.com:443?encryption=none&security=tls&sni=example.com&type=tcp',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final stream = ((map['outbounds'] as List).first as Map)['streamSettings'] as Map<String, dynamic>;
      final tls = stream['tlsSettings'] as Map<String, dynamic>;
      expect(tls.containsKey('fingerprint'), isFalse);
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

