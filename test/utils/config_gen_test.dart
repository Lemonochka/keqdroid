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

    test('kill switch adds 0.0.0.0/1 and 128.0.0.0/1 rules', () {
      Socks5Credentials().init('u', 'p');
      final killSwitchSettings = AppSettings(killSwitch: true);
      final config = ConfigGeneratorV2.generateConfig(
        'vless://uuid@example.com:443',
        killSwitchSettings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final rules = (map['routing'] as Map)['rules'] as List;
      final killSwitchRule = rules.firstWhere(
        (r) => (r['ip'] as List?)?.contains('0.0.0.0/1') == true,
      ) as Map<String, dynamic>;
      expect(killSwitchRule['outboundTag'], 'proxy');
      expect((killSwitchRule['ip'] as List), contains('128.0.0.0/1'));
    });

    test('no kill switch rule when killSwitch is false', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'vless://uuid@example.com:443',
        settings, // killSwitch: false by default
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final rules = (map['routing'] as Map)['rules'] as List;
      final hasKillSwitch = rules.any((r) =>
        (r['ip'] as List?)?.contains('0.0.0.0/1') == true);
      expect(hasKillSwitch, false);
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

    test('Trojan TLS sets allowInsecure when insecure=1', () {
      Socks5Credentials().init('u', 'p');
      final config = ConfigGeneratorV2.generateConfig(
        'trojan://password@example.com:443?sni=example.com&type=tcp&insecure=1',
        settings,
      );
      final map = jsonDecode(config) as Map<String, dynamic>;
      final stream = ((map['outbounds'] as List).first as Map)['streamSettings'] as Map<String, dynamic>;
      final tls = stream['tlsSettings'] as Map<String, dynamic>;
      expect(tls['allowInsecure'], isTrue);
    });

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
      final servers = dns['servers'] as List;
      expect((servers.first as Map)['address'], 'https://dns.google/dns-query');
      expect((map['routing'] as Map)['domainStrategy'], 'IPIfNonMatch');
    });

    test('generatePingConfig uses noauth local SOCKS on ephemeral port', () {
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
      final socksSettings = inbound['settings'] as Map<String, dynamic>;
      expect(socksSettings['auth'], 'noauth');
      expect(map['inbounds'].length, 1);
      expect((map['log'] as Map)['loglevel'], 'none');
      final dns = map['dns'] as Map<String, dynamic>;
      expect(dns['queryStrategy'], 'UseIPv4');
      expect((map['routing'] as Map)['domainStrategy'], 'AsIs');
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

