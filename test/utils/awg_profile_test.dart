import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/awg_profile.dart';

void main() {
  // Валидные 32-байтные ключи (base64) для проверки base64→hex.
  const privBlock = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEA=';
  const pubBlock = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIA=';

  const sample = '''
# Name = Test AWG
[Interface]
PrivateKey = $privBlock
Address = 10.8.1.2/32, fd00::2/128
DNS = 1.1.1.1, 8.8.8.8
MTU = 1280
Jc = 4
Jmin = 40
Jmax = 70
S1 = 86
S2 = 574
H1 = 1
H2 = 2
H3 = 3
H4 = 4

[Peer]
PublicKey = $pubBlock
Endpoint = 203.0.113.10:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
''';

  test('detects AWG config by [Interface] header', () {
    expect(AwgProfile.isAwgConfig(sample), isTrue);
    expect(AwgProfile.isAwgConfig('vless://abc'), isFalse);
  });

  test('parses interface, peer and AWG params', () {
    final p = AwgProfile.parse(sample);
    expect(p.remark, 'Test AWG');
    expect(p.iface.addresses, ['10.8.1.2/32', 'fd00::2/128']);
    expect(p.iface.dns, ['1.1.1.1', '8.8.8.8']);
    expect(p.iface.mtu, 1280);
    expect(p.iface.awgParams['jc'], '4');
    expect(p.iface.awgParams['s2'], '574');
    expect(p.iface.awgParams['h4'], '4');
    expect(p.peer.endpoint, '203.0.113.10:51820');
    expect(p.peer.allowedIps, ['0.0.0.0/0', '::/0']);
    expect(p.peer.persistentKeepalive, 25);
  });

  test('extracts endpoint host/port for ping', () {
    final p = AwgProfile.parse(sample);
    expect(p.endpointHost, '203.0.113.10');
    expect(p.endpointPort, 51820);
  });

  test('parses IPv6 bracketed endpoint', () {
    final conf = sample.replaceFirst(
        'Endpoint = 203.0.113.10:51820', 'Endpoint = [2001:db8::1]:443');
    final p = AwgProfile.parse(conf);
    expect(p.endpointHost, '2001:db8::1');
    expect(p.endpointPort, 443);
  });

  test('toUapi emits hex keys and lowercase AWG params', () {
    final uapi = AwgProfile.parse(sample).toUapi();
    expect(uapi, contains('private_key='));
    expect(uapi, contains('public_key='));
    expect(uapi, contains('jc=4'));
    expect(uapi, contains('s2=574'));
    expect(uapi, contains('endpoint=203.0.113.10:51820'));
    expect(uapi, contains('allowed_ip=0.0.0.0/0'));
    expect(uapi, contains('persistent_keepalive_interval=25'));
    // hex, не base64
    expect(uapi, isNot(contains(privBlock)));
  });

  test('toUapi substitutes resolved endpoint for domain hosts', () {
    final conf = sample.replaceFirst(
        'Endpoint = 203.0.113.10:51820', 'Endpoint = vpn.example.com:945');
    final p = AwgProfile.parse(conf);
    expect(AwgProfile.splitEndpoint(p.peer.endpoint),
        ('vpn.example.com', 945));
    final uapi = p.toUapi(
      endpointOverrides: {'vpn.example.com:945': '198.51.100.7:945'},
    );
    // amneziawg-go UAPI не резолвит DNS — в endpoint обязан уйти IP.
    expect(uapi, contains('endpoint=198.51.100.7:945'));
    expect(uapi, isNot(contains('endpoint=vpn.example.com:945')));
  });

  test('tunnelName produces safe slug', () {
    expect(AwgProfile.parse(sample).tunnelName(), 'Test_AWG');
  });

  test('rejects non-AWG and incomplete configs', () {
    expect(() => AwgProfile.parse('vless://x'), throwsArgumentError);
    expect(
      () => AwgProfile.parse('[Interface]\nPrivateKey = $privBlock\n'),
      throwsArgumentError, // нет [Peer]
    );
  });
}
