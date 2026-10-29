import 'dart:convert';

// три вида, как у v2rayN (SocksFmt.cs) и converter.go mihomo: base64(user:pass)@host:port,
// user:pass@host:port в percent-кодировке и старый base64(user:pass@host:port)
class SocksLink {
  const SocksLink({
    required this.host,
    required this.port,
    this.username = '',
    this.password = '',
    this.name = '',
  });

  final String host;
  final int port;
  final String username;
  final String password;
  final String name;

  static final _scheme = RegExp(r'^(socks|socks5|socks5h)://', caseSensitive: false);

  static bool isSocks(String config) => _scheme.hasMatch(config.trimLeft());

  static SocksLink? tryParse(String config) {
    final trimmed = config.trim();
    final m = _scheme.firstMatch(trimmed);
    if (m == null) return null;
    var rest = trimmed.substring(m.end);

    var name = '';
    final hash = rest.indexOf('#');
    if (hash >= 0) {
      name = _decode(rest.substring(hash + 1));
      rest = rest.substring(0, hash);
    }
    final query = rest.indexOf('?');
    if (query >= 0) rest = rest.substring(0, query);
    if (rest.endsWith('/')) rest = rest.substring(0, rest.length - 1);

    if (!rest.contains('@')) {
      final whole = _base64(rest);
      if (whole != null && whole.contains('@')) rest = whole;
    }
    final at = rest.lastIndexOf('@');
    final userInfo = at < 0 ? '' : rest.substring(0, at);
    final hostPort = rest.substring(at + 1);

    final colon = hostPort.lastIndexOf(':');
    if (colon <= 0) return null;
    var host = hostPort.substring(0, colon);
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    final port = int.tryParse(hostPort.substring(colon + 1));
    if (host.isEmpty || port == null || port <= 0 || port > 65535) return null;

    var username = '';
    var password = '';
    if (userInfo.isNotEmpty) {
      final plain = userInfo.contains(':') ? userInfo : _base64(userInfo);
      if (plain == null) return null;
      final split = plain.indexOf(':');
      username = _decode(split < 0 ? plain : plain.substring(0, split));
      password = split < 0 ? '' : _decode(plain.substring(split + 1));
    }

    return SocksLink(
      host: host,
      port: port,
      username: username,
      password: password,
      name: name,
    );
  }

  static String _decode(String raw) {
    try {
      return Uri.decodeComponent(raw);
    } on ArgumentError {
      return raw;
    }
  }

  static String? _base64(String raw) {
    var n = _decode(raw).replaceAll('-', '+').replaceAll('_', '/');
    while (n.length % 4 != 0) {
      n += '=';
    }
    try {
      return utf8.decode(base64.decode(n));
    } on FormatException {
      return null;
    }
  }
}
