import 'dart:convert';

/// Разобранная ссылка ShadowsocksR.
///
/// Формат старый и своеобразный: всё после схемы — base64 от строки
/// `host:port:protocol:method:obfs:base64(пароль)/?obfsparam=…&protoparam=…`,
/// где параметры внутри тоже base64, и в url-safe алфавите. Отсюда и отдельный
/// разборщик: ни `Uri.parse`, ни разбор ss-ссылки такое не берут — у ссылки нет
/// ни хоста, ни порта в том месте, где их ищет `Uri`.
///
/// Разбор сверен с `common/convert/converter.go` mihomo.
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

  /// Протокол обфускации SSR (`auth_aes128_md5` и подобные) — не путать с
  /// протоколом сервера в смысле приложения, тот всегда `ssr`.
  final String protocol;
  final String method;
  final String obfs;
  final String password;
  final String obfsParam;
  final String protocolParam;

  /// Имя узла. У SSR оно внутри base64, а не во фрагменте ссылки.
  final String remarks;

  static SsrLink? tryParse(String link) {
    final trimmed = link.trim();
    if (!trimmed.toLowerCase().startsWith('ssr://')) return null;
    final decoded = _decodeBase64(trimmed.substring('ssr://'.length));
    if (decoded == null) return null;

    // Часть с параметрами необязательна: сервер описан уже первой половиной, а
    // ссылки без `/?` встречаются. Ядро такую пропускает, мы — берём.
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

  /// Обратно в ссылку — для перевода узла Clash, у которого поля лежат россыпью.
  ///
  /// Алфавит url-safe и без `=`: так эти ссылки и выглядят в подписках, и так
  /// их читает [tryParse].
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

  /// Значения параметров без percent-декодирования: там base64, а не текст.
  static Map<String, String> _params(String query) {
    final out = <String, String>{};
    for (final pair in query.split('&')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      out[pair.substring(0, eq).toLowerCase()] = pair.substring(eq + 1);
    }
    return out;
  }

  /// base64 в любом из четырёх видов: два алфавита на два варианта дополнения.
  /// Ссылки приходят и такими, и такими — ядро точно так же пробует по кругу.
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
