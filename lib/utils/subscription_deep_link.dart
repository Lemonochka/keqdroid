// схема и имя параметра вписаны в настройки чужих панелей, переименование сломает их кнопки
library;

const _appSchemes = {'keqdroid', 'keqdis'};

// хост не проверяем: панели пишут туда что угодно (install-config, add, subscribe)
String? subscriptionUrlFromDeepLink(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !_appSchemes.contains(uri.scheme.toLowerCase())) {
    return null;
  }

  final url = uri.queryParameters['url']?.trim();
  if (url == null || url.isEmpty) return null;

  final inner = Uri.tryParse(url);
  if (inner == null || (inner.scheme != 'http' && inner.scheme != 'https')) {
    return null;
  }
  return url;
}
