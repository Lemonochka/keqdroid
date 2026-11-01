// new-url целиком, new-domain меняет только хост, порт по желанию. с https на http не переезжаем: там пароли серверов
String? movedSubscriptionUrl(
  String current, {
  String? newUrl,
  String? newDomain,
}) {
  final from = Uri.tryParse(current.trim());
  if (from == null) return null;
  Uri? to;
  if (newUrl != null && newUrl.trim().isNotEmpty) {
    to = Uri.tryParse(newUrl.trim());
  } else if (newDomain != null && newDomain.trim().isNotEmpty) {
    var domain = newDomain.trim();
    final scheme = domain.indexOf('://');
    if (scheme >= 0) domain = domain.substring(scheme + 3);
    domain = domain.split('/').first;
    final at = Uri.tryParse('${from.scheme}://$domain');
    if (at == null || !RegExp(r'^[a-z0-9.-]+\.[a-z0-9-]+$').hasMatch(at.host)) {
      return null;
    }
    to = from.replace(host: at.host, port: at.hasPort ? at.port : null);
  }
  if (to == null || !to.hasAuthority || to.host.isEmpty) return null;
  if (to.scheme != 'https' && to.scheme != 'http') return null;
  if (from.scheme == 'https' && to.scheme != 'https') return null;
  final result = to.toString();
  return normalizeSubscriptionUrl(result) == normalizeSubscriptionUrl(current)
      ? null
      : result;
}

String normalizeSubscriptionUrl(String url) {
  final trimmed = url.trim();
  try {
    final uri = Uri.parse(trimmed);
    final normalizedPath = uri.path.length > 1 && uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return uri
        .replace(
          scheme: uri.scheme.toLowerCase(),
          host: uri.host.toLowerCase(),
          path: normalizedPath,
        )
        .toString();
  } catch (_) {
    return trimmed;
  }
}
