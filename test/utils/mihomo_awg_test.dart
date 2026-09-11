import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// AmneziaWG едет через mihomo: профиль `.conf` → `type: wireguard`.
///
/// Сверено с `adapter/outbound/wireguard.go` mihomo 1.19.30. Незнакомое поле
/// ядро выбрасывает молча, поэтому проверяются имена и типы полей, а не только
/// то, что конфиг собрался.
Map<String, dynamic> _proxy(String conf) =>
    (MihomoConfigGen.build(conf, const AppSettings(), socksPort: 2080)['proxies']
            as List)
        .cast<Map<String, dynamic>>()
        .single;

List<Map<String, dynamic>> _peers(Map<String, dynamic> proxy) =>
    (proxy['peers'] as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _awg(Map<String, dynamic> proxy) =>
    proxy['amnezia-wg-option'] as Map<String, dynamic>;

const _priv = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEA=';
const _pub = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIA=';

String _conf({
  String iface = '',
  String peer = 'AllowedIPs = 0.0.0.0/0, ::/0',
  String address = 'Address = 10.8.1.2/32, fd00::2/128',
}) =>
    '[Interface]\n'
    'PrivateKey = $_priv\n'
    '$address\n'
    '$iface\n'
    '[Peer]\n'
    'PublicKey = $_pub\n'
    'Endpoint = 203.0.113.10:51820\n'
    '$peer\n';

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  test('обычный WireGuard: без amnezia-wg-option, адреса по семействам', () {
    final p = _proxy(_conf());
    expect(p['type'], 'wireguard');
    expect(p['name'], MihomoConfigGen.proxyName);
    expect(p['server'], '203.0.113.10');
    expect(p['port'], 51820);
    expect(p['ip'], '10.8.1.2/32');
    expect(p['ipv6'], 'fd00::2/128');
    expect(p['private-key'], _priv);
    expect(p['udp'], isTrue);
    expect(p.containsKey('amnezia-wg-option'), isFalse);

    final peer = _peers(p).single;
    expect(peer['server'], '203.0.113.10');
    expect(peer['port'], 51820);
    expect(peer['public-key'], _pub);
    expect(peer['allowed-ips'], ['0.0.0.0/0', '::/0']);
  });

  test('параметры AWG — полями и типами ядра, реализация v3', () {
    final p = _proxy(_conf(
      iface: 'Jc = 4\nJmin = 40\nJmax = 70\nS1 = 86\nS2 = 574\nS3 = 20\n'
          'S4 = 10\nH1 = 100-200\nH2 = 2\nH3 = 3\nH4 = 4\n'
          'I1 = <b 0xf6ab3267fa><c><t><r 10>',
    ));
    final awg = _awg(p);
    // Только `version: 3` включает у ядра amneziawg-go v3; без неё профиль
    // уехал бы в старую реализацию.
    expect(awg['version'], 3);
    // Числа — числами: у ядра это int-поля.
    expect(awg['jc'], 4);
    expect(awg['jmax'], 70);
    expect(awg['s2'], 574);
    expect(awg['s4'], 10);
    // H — строкой: с AWG 2.0 это может быть диапазон.
    expect(awg['h1'], '100-200');
    expect(awg['h4'], '4');
    expect(awg['i1'], '<b 0xf6ab3267fa><c><t><r 10>');
  });

  test('AWG 3.1: ключ заголовков как в профиле, флаги булевы', () {
    final p = _proxy(_conf(
      iface: 'Jc = 4\nHeaderProtectionKey = $_pub\n'
          'ContentPaddingAddition = 10-20\nRekeyAfterTime = 110-130\n'
          'RandomTrailers = yes\nDisableCookies = off',
    ));
    final awg = _awg(p);
    // base64, а не hex: в hex ключ переводит само ядро.
    expect(awg['header-protection-key'], _pub);
    expect(awg['content-padding-addition'], '10-20');
    expect(awg['rekey-after-time'], '110-130');
    expect(awg['random-trailers'], isTrue);
    expect(awg['disable-cookies'], isFalse);
  });

  test('keepalive диапазоном — нижняя граница, off — без keepalive', () {
    expect(
      _proxy(_conf(peer: 'AllowedIPs = 0.0.0.0/0\nPersistentKeepalive = 22-30'))[
          'persistent-keepalive'],
      22,
    );
    expect(
      _proxy(_conf(peer: 'AllowedIPs = 0.0.0.0/0\nPersistentKeepalive = 25'))[
          'persistent-keepalive'],
      25,
    );
    expect(
      _proxy(_conf(peer: 'AllowedIPs = 0.0.0.0/0\nPersistentKeepalive = off'))
          .containsKey('persistent-keepalive'),
      isFalse,
    );
  });

  test('без MTU — 1280, без AllowedIPs — весь трафик', () {
    final p = _proxy(_conf(peer: ''));
    expect(p['mtu'], 1280);
    expect(_peers(p).single['allowed-ips'], ['0.0.0.0/0', '::/0']);
    expect(_proxy(_conf(iface: 'MTU = 1420'))['mtu'], 1420);
  });

  test('DNS профиля — через туннель, домены поиска выброшены', () {
    final p = _proxy(_conf(iface: 'DNS = 10.8.0.1, corp.example, 1.1.1.1'));
    expect(p['dns'], ['10.8.0.1', '1.1.1.1']);
    expect(p['remote-dns-resolve'], isTrue);

    final none = _proxy(_conf());
    expect(none.containsKey('dns'), isFalse);
    expect(none.containsKey('remote-dns-resolve'), isFalse);
  });

  test('ключ без паддинга дополняется — ядро декодирует строго', () {
    final conf = _conf().replaceFirst(_priv, _priv.replaceAll('=', ''));
    expect(_proxy(conf)['private-key'], _priv);
  });

  test('пира без адреса интерфейса ядро не поднимет — отказ сразу', () {
    expect(() => _proxy(_conf(address: '')), throwsArgumentError);
  });

  test('несколько пиров — все в peers, верхний server у первого', () {
    final conf = '${_conf()}\n[Peer]\nPublicKey = $_priv\n'
        'Endpoint = [2001:db8::1]:443\nAllowedIPs = 10.0.0.0/8\n';
    final p = _proxy(conf);
    expect(p['server'], '203.0.113.10');
    final peers = _peers(p);
    expect(peers, hasLength(2));
    expect(peers[1]['server'], '2001:db8::1');
    expect(peers[1]['port'], 443);
    expect(peers[1]['allowed-ips'], ['10.0.0.0/8']);
  });

  test('замер собирается из того же профиля', () {
    final ping = jsonDecode(
      MihomoConfigGen.generatePingConfig(
        _conf(iface: 'Jc = 4'),
        const AppSettings(),
        socksPort: 28150,
      ),
    ) as Map<String, dynamic>;
    final proxy = (ping['proxies'] as List).single as Map<String, dynamic>;
    expect(proxy['type'], 'wireguard');
    expect((proxy['amnezia-wg-option'] as Map)['version'], 3);
  });
}
