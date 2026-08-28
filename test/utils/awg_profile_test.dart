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
    expect(p.peer.persistentKeepalive, '25');
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

  group('AmneziaWG 3.1', () {
    // Ключ защиты заголовков — такой же 32-байтный base64, как ключи WG.
    const hpkBlock = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAMA=';

    String withAwg31(String extra) => sample
        .replaceFirst('S1 = 86', 'S1 = 86\n$extra')
        .replaceFirst('PersistentKeepalive = 25', 'PersistentKeepalive = 22-30');

    const params = '''
HeaderProtectionKey = $hpkBlock
ContentPaddingAddition = 2-10
RekeyAfterTime = 100-140
RekeyTimeout = 5
RejectAfterTime = 180-220
KeepaliveTimeout = 10-15
MaxHandshakeAttempts = 18
RandomTrailers = true
DisableCookies = false''';

    test('parses the 3.1 interface keys as AWG params', () {
      final p = AwgProfile.parse(withAwg31(params));
      expect(p.iface.awgParams['headerprotectionkey'], hpkBlock);
      expect(p.iface.awgParams['contentpaddingaddition'], '2-10');
      expect(p.iface.awgParams['maxhandshakeattempts'], '18');
      expect(p.iface.awgParams['randomtrailers'], 'true');
      // Старые ключи на месте, а сетевые в awgParams не попали.
      expect(p.iface.awgParams['jc'], '4');
      expect(p.iface.awgParams.containsKey('mtu'), isFalse);
    });

    test('toUapi renames the 3.1 keys and converts their values', () {
      final uapi = AwgProfile.parse(withAwg31(params)).toUapi();
      // В UAPI имена snake_case, а не то, что написано в .conf.
      expect(uapi, isNot(contains('headerprotectionkey=')));
      expect(uapi, contains('content_padding_addition=2-10'));
      expect(uapi, contains('rekey_after_time=100-140'));
      expect(uapi, contains('rekey_timeout=5'));
      expect(uapi, contains('reject_after_time=180-220'));
      expect(uapi, contains('keepalive_timeout=10-15'));
      expect(uapi, contains('max_handshake_attempts=18'));
      expect(uapi, contains('random_trailers=true'));
      expect(uapi, contains('disable_cookies=false'));
      // Ключ уходит в hex, как private_key, а не строкой из конфига.
      expect(uapi, isNot(contains(hpkBlock)));
      expect(
        RegExp(r'^header_protection_key=[0-9a-f]{64}$', multiLine: true)
            .hasMatch(uapi),
        isTrue,
      );
    });

    test('keepalive keeps a range and turns off into 0', () {
      final ranged = AwgProfile.parse(withAwg31(params));
      expect(ranged.peer.persistentKeepalive, '22-30');
      expect(ranged.toUapi(), contains('persistent_keepalive_interval=22-30'));

      final off = AwgProfile.parse(
        sample.replaceFirst('PersistentKeepalive = 25', 'PersistentKeepalive = off'),
      );
      // `off` понимает wg-quick, но не UAPI — иначе ядро уронит весь IpcSet.
      expect(off.peer.persistentKeepalive, '0');
      expect(off.toUapi(), contains('persistent_keepalive_interval=0'));
    });

    test('accepts yes/no spellings for the 3.1 flags', () {
      final uapi = AwgProfile.parse(
        withAwg31('RandomTrailers = yes\nDisableCookies = off'),
      ).toUapi();
      expect(uapi, contains('random_trailers=true'));
      expect(uapi, contains('disable_cookies=false'));
    });

    test('rejects malformed 3.1 values at import', () {
      expect(
        () => AwgProfile.parse(withAwg31('RandomTrailers = maybe')),
        throwsArgumentError,
      );
      expect(
        () => AwgProfile.parse(withAwg31('ContentPaddingAddition = 10-2')),
        throwsArgumentError, // верхняя граница ниже нижней
      );
      expect(
        () => AwgProfile.parse(withAwg31('RekeyTimeout = 5s')),
        throwsArgumentError,
      );
      expect(
        () => AwgProfile.parse(withAwg31('HeaderProtectionKey = nope')),
        throwsArgumentError,
      );
      expect(
        () => AwgProfile.parse(
          sample.replaceFirst('PersistentKeepalive = 25', 'PersistentKeepalive = 30-22'),
        ),
        throwsArgumentError,
      );
    });

    test('never puts an unknown interface key into UAPI', () {
      // Itime жил в AWG 2.0 и из v3 пропал: незнакомый ключ ядро не игнорирует,
      // а отвечает `invalid UAPI device key` и не поднимает устройство вовсе.
      final uapi = AwgProfile.parse(withAwg31('Itime = 60\nTable = off')).toUapi();
      expect(uapi, isNot(contains('itime')));
      expect(uapi, isNot(contains('table')));
    });
  });
}
