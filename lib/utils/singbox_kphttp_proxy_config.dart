import 'dart:convert';

/// sing-box bridge: HTTP inbound (system proxy) → local KpHTTP SOCKS5 (no auth).
class SingBoxKphttpProxyConfigGen {
  static String generate({
    required int kphttpSocksPort,
    required int httpPort,
  }) {
    final map = <String, dynamic>{
      'log': {
        'level': 'info',
        'timestamp': true,
      },
      'inbounds': [
        {
          'type': 'http',
          'tag': 'http-in',
          'listen': '127.0.0.1',
          'listen_port': httpPort,
        },
      ],
      'outbounds': [
        {
          'type': 'socks',
          'tag': 'proxy',
          'server': '127.0.0.1',
          'server_port': kphttpSocksPort,
          'version': '5',
        },
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {
        'rules': [
          {'inbound': 'http-in', 'outbound': 'proxy'},
        ],
        'final': 'proxy',
      },
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }
}
