import 'dart:convert';

// всё после схемы закодировано base64, и хоста с портом там, где их ищет Uri, нет; разбор сверен с converter.go mihomo
class SsrLink {
  const SsrLink({
    required this.host,
    required this.port,
    required this.protocol,
    required this.method,
    required this.obfs,
    required this.password,
    required this.obfsParam,
    required this.protocolParam,
    required this.remarks,
  });

  final String host;
  final int port;

  // обфускация SSR вроде auth_aes128_md5, протокол сервера тут всегда ssr
  final String protocol;
  final String method;
  final String obfs;
  final String password;
  final String obfsParam;
  final String protocolParam;

  // имя у SSR внутри base64, не во фрагменте
  final String remarks;

  static SsrLink? tryParse(String link) {
    final trimmed = link.trim();
    if (!trimmed.toLowerCase().startsWith('ssr://')) return null;
    final decoded = _decodeBase64(trimmed.substring('ssr://'.length));
    if (decoded == null) return null;

    // ссылки без /? встречаются: ядро их пропускает, мы берём, сервер описан и без параметров
    final cut = decoded.indexOf('/?');
    final head = cut >= 0 ? decoded.substring(0, cut) : decoded;
    final query = cut >= 0 ? decoded.substring(cut + 2) : '';

    final parts = head.split(':');
    if (parts.length != 6) return null;
    final port = int.tryParse(parts[1].trim());
    if (port == null || port <= 0) return null;

    final params = _params(query);
    return SsrLink(
      host: parts[0],
      port: port,
      protocol: parts[2],
      method: parts[3],
      obfs: parts[4],
      password: _decodeBase64(parts[5]) ?? '',
      obfsParam: _decodeBase64(params['obfsparam'] ?? '') ?? '',
      protocolParam: _decodeBase64(params['protoparam'] ?? '') ?? '',
      remarks: _decodeBase64(params['remarks'] ?? '') ?? '',
    );
  }

  // url-safe и без =, как в подписках
  String encode() {
    String b64(String value) =>
        base64Url.encode(utf8.encode(value)).replaceAll('=', '');
    final query = [
      if (obfsParam.isNotEmpty) 'obfsparam=${b64(obfsParam)}',
      if (protocolParam.isNotEmpty) 'protoparam=${b64(protocolParam)}',
      if (remarks.isNotEmpty) 'remarks=${b64(remarks)}',
    ].join('&');
    final payload =
        '$host:$port:$protocol:$method:$obfs:${b64(password)}/?$query';
    return 'ssr://${b64(payload)}';
  }

  // без percent-декода: в значениях base64
  static Map<String, String> _params(String query) {
    final out = <String, String>{};
    for (final pair in query.split('&')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      out[pair.substring(0, eq).toLowerCase()] = pair.substring(eq + 1);
    }
    return out;
  }

  // ссылки приходят в обоих алфавитах, с дополнением и без, ядро тоже перебирает все четыре
  static String? _decodeBase64(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    final normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    try {
      return utf8.decode(base64.decode(base64.normalize(normalized)));
    } catch (_) {
      return null;
    }
  }
}
