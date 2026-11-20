import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/mieru_uri.dart';
import 'package:keqdroid/utils/proxy_chain.dart';
import 'package:keqdroid/utils/same_server_key.dart';

const _vless =
    'vless://00000000-0000-4000-8000-000000000000@198.51.100.10:443'
    '?security=tls&sni=a.example&type=ws&path=%2Fws';

String _vmess(Map<String, Object> fields) =>
    'vmess://${base64.encode(utf8.encode(jsonEncode(fields)))}';

const _vmessFields = <String, Object>{
  'v': '2',
  'add': '198.51.100.20',
  'port': '443',
  'id': '00000000-0000-4000-8000-000000000001',
  'net': 'ws',
  'path': '/ws',
  'tls': 'tls',
};

void main() {
  test('ссылки, разные только именем, это один сервер', () {
    expect(
      sameServerKeyOf('$_vless#A'),
      sameServerKeyOf('$_vless#%40channel%20B'),
    );
    expect(sameServerKeyOf('$_vless#A'), sameServerKeyOf(_vless));
  });

  test('другой SNI, путь, порт или UUID это другой сервер', () {
    final base = sameServerKeyOf('$_vless#A');
    for (final other in [
      _vless.replaceFirst('sni=a.example', 'sni=b.example'),
      _vless.replaceFirst('path=%2Fws', 'path=%2Fother'),
      _vless.replaceFirst(':443', ':8443'),
      _vless.replaceFirst(
        '00000000-0000-4000-8000-000000000000',
        '00000000-0000-4000-8000-0000000000ff',
      ),
    ]) {
      expect(sameServerKeyOf('$other#A'), isNot(base), reason: other);
    }
  });

  test('vmess: имя внутри base64 не мешает узнать копию', () {
    final a = _vmess({..._vmessFields, 'ps': 'A'});
    final b = _vmess({..._vmessFields, 'ps': '@channel B'});
    final otherPath = _vmess({..._vmessFields, 'ps': 'A', 'path': '/other'});
    expect(sameServerKeyOf(a), sameServerKeyOf(b));
    expect(sameServerKeyOf(a), isNot(sameServerKeyOf(otherPath)));
  });

  test('vmess ссылкой, а не base64, режется по #', () {
    const link =
        'vmess://00000000-0000-4000-8000-000000000001@198.51.100.20:443?type=ws';
    expect(sameServerKeyOf('$link#A'), sameServerKeyOf('$link#B'));
  });

  test('JSON xray: другие remarks это та же копия, другой адрес нет', () {
    String json(String remarks, String address) => jsonEncode({
      'remarks': remarks,
      'outbounds': [
        {
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {'address': address, 'port': 443},
            ],
          },
        },
      ],
    });
    expect(
      sameServerKeyOf(json('A', '198.51.100.30')),
      sameServerKeyOf(json('B', '198.51.100.30')),
    );
    expect(
      sameServerKeyOf(json('A', '198.51.100.30')),
      isNot(sameServerKeyOf(json('A', '198.51.100.31'))),
    );
  });

  test('конфиг AWG не режется по # из комментариев', () {
    const a =
        '[Interface]\nPrivateKey = a\n# home\n[Peer]\nEndpoint = 198.51.100.40:51820';
    const b =
        '[Interface]\nPrivateKey = a\n# work\n[Peer]\nEndpoint = 198.51.100.40:51820';
    expect(sameServerKeyOf(a), isNot(sameServerKeyOf(b)));
  });

  test('цепочка сравнивается целиком', () {
    const a = '${ProxyChainConfig.scheme}://abc#A';
    const b = '${ProxyChainConfig.scheme}://abc#B';
    expect(sameServerKeyOf(a), isNot(sameServerKeyOf(b)));
  });

  test('mieru на нескольких портах остаётся разными серверами', () {
    final links = MieruLink.expand(
      'mierus://user:pass@198.51.100.50?port=2000&protocol=TCP&port=3000&protocol=UDP#M',
    );
    expect(links, hasLength(2));
    expect(sameServerKeyOf(links[0]), isNot(sameServerKeyOf(links[1])));
  });

  group('withoutNameCopies', () {
    test('остаётся первая копия на месте первой', () {
      expect(
        withoutNameCopies([
          '$_vless#A',
          'trojan://p@198.51.100.60:443#T',
          '$_vless#B',
        ]),
        ['$_vless#A', 'trojan://p@198.51.100.60:443#T'],
      );
    });

    test('копия с большим rank встаёт на место первой', () {
      expect(
        withoutNameCopies([
          '$_vless#A',
          'trojan://p@198.51.100.60:443#T',
          '$_vless#B',
        ], rank: (c) => c.endsWith('#B') ? 1 : 0),
        ['$_vless#B', 'trojan://p@198.51.100.60:443#T'],
      );
    });
  });
}
