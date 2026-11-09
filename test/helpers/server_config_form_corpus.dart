import 'dart:convert';

const serverConfigFormGolden =
    'test/fixtures/server_config_form/edited_address.json';

const _id = '716e3485-d4f9-4471-9660-fb4b0b838100';
const _pbk = 'oYXosxG2YU6_mQkkPTS8JUnoRxqvaBaG5mH-y0pc2nA';

String _vmess(Map<String, Object?> json) =>
    'vmess://${base64.encode(utf8.encode(jsonEncode(json)))}';

// каждая ветка разбора и сборки: протокол, безопасность, транспорт, чужой параметр
final serverConfigFormCorpus = <String, String>{
  'vless reality tcp vision':
      'vless://$_id@198.51.100.1:443?type=tcp&security=reality&sni=a.example'
          '&fp=chrome&pbk=$_pbk&sid=9f2c&spx=%2Fx&pqv=abc&pcs=11&vcn=b.example'
          '&flow=xtls-rprx-vision&encryption=none#reality',
  'vless tls ws':
      'vless://$_id@198.51.100.2:443?type=ws&security=tls&sni=a.example&fp=firefox'
          '&alpn=h2%2Chttp%2F1.1&ech=abc&insecure=1&pcs=11&vcn=b.example'
          '&path=%2Fws&host=h.example&ed=2048#ws',
  'vless tls httpupgrade':
      'vless://$_id@198.51.100.3:443?type=httpupgrade&security=tls&sni=a.example'
          '&path=%2Fup&host=h.example#up',
  'vless reality xhttp keeps unknown params':
      'vless://$_id@198.51.100.4:443?type=xhttp&security=reality&sni=a.example'
          '&fp=chrome&pbk=$_pbk&sid=9f2c&mode=stream-one&x_padding_bytes=100-1000'
          '&path=%2Fdl&host=h.example&extra=%7B%22a%22%3A1%7D&foo=bar&Baz=Q%2BW#x',
  'vless grpc':
      'vless://$_id@198.51.100.5:443?type=grpc&security=tls&sni=a.example'
          '&serviceName=svc&mode=multi&authority=auth.example#grpc',
  'vless kcp':
      'vless://$_id@198.51.100.6:443?type=kcp&security=none&headerType=srtp'
          '&seed=hello&mtu=1350&tti=50#kcp',
  'vless tcp http header':
      'vless://$_id@198.51.100.7:443?type=tcp&security=none&headerType=http'
          '&host=h.example&path=%2Fp&method=GET#http',
  'vless bare': 'vless://$_id@198.51.100.8:443#Name%20With%20Space',
  'vless insecure aliases':
      'vless://$_id@198.51.100.9:443?security=tls&allowInsecure=true'
          '&skip-cert-verify=1#ins',
  'vless ipv6 encryption':
      'vless://$_id@[2001:db8::1]:443?encryption=mlkem768x25519plus.native.0rtt.abc'
          '&security=none#v6',
  'trojan plain': 'trojan://pa%40ss@198.51.100.10:443#plain',
  'trojan tls ws insecure':
      'trojan://password@198.51.100.11:443?type=ws&sni=a.example&fp=chrome'
          '&alpn=h2&ech=abc&pcs=11&vcn=b.example&allowInsecure=1&path=%2Fws'
          '&host=h.example#ws',
  'trojan explicit tls grpc':
      'trojan://password@198.51.100.12:443?type=grpc&security=tls&sni=a.example'
          '&serviceName=svc#grpc',
  'trojan reality':
      'trojan://password@198.51.100.13:443?type=tcp&security=reality&sni=a.example'
          '&fp=chrome&pbk=$_pbk&sid=9f2c&spx=%2F&pqv=abc#reality',
  'ss plain password with colon':
      'ss://aes-256-gcm:pa:ss@198.51.100.14:8388#plain',
  'ss base64 with plugin':
      'ss://YWVzLTI1Ni1nY206cGFzcw@198.51.100.15:8388'
          '?plugin=obfs-local%3Bobfs%3Dhttp#b64',
  'hysteria2 userinfo full':
      'hysteria2://pass%40word@198.51.100.16:443?sni=a.example&fp=chrome&alpn=h3'
          '&ech=abc&insecure=1&obfs=salamander&obfs-password=secret&up=50&down=200'
          '&mport=20000-20050&hop-interval=30&pinSHA256=AB%2BCD#full',
  'hy2 auth in query': 'hy2://198.51.100.17:443?auth=secret&sni=a.example#query',
  'hy2 password in query':
      'hy2://198.51.100.18:443?password=secret&obfs=&hop-interval=30#pw',
  'hy2 bad percent in userinfo': 'hy2://100%25@198.51.100.19:443#pct',
  'vmess int port ws tls': _vmess({
    'v': '2',
    'ps': 'node',
    'add': '198.51.100.20',
    'port': 443,
    'id': _id,
    'aid': 0,
    'scy': 'auto',
    'net': 'ws',
    'type': 'none',
    'host': 'h.example',
    'path': '/ws',
    'tls': 'tls',
    'sni': 'a.example',
    'fp': 'chrome',
    'alpn': 'h2',
    'ech': 'abc',
    'extraField': 'kept',
  }),
  'vmess string port security key grpc': _vmess({
    'v': '2',
    'ps': 'node',
    'add': '198.51.100.21',
    'port': '8443',
    'id': _id,
    'security': 'aes-128-gcm',
    'net': 'grpc',
    'serviceName': 'svc',
    'tls': 'tls',
    'allowInsecure': true,
    'skip-cert-verify': '1',
  }),
  'vmess minimal': _vmess({
    'add': '198.51.100.22',
    'port': 80,
    'id': _id,
  }),
};
