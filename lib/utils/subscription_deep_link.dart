/// Разбор deep link, которым панель открывает приложение на добавление подписки.
///
/// Панели (Remnawave и подобные) дают собрать на странице подписки кнопку вида
/// `<схема клиента>://install-config?url={{SUBSCRIPTION_LINK}}` — так работают
/// FlClashX, v2rayNG и прочие. Наши схемы — `keqdroid://` и `keqdis://`.
///
/// Схема и имя параметра — **внешний контракт**: они вписаны в настройки уже
/// существующих панелей, поэтому переименование ломает кнопки, которые кто-то
/// настроил месяц назад.
library;

const _appSchemes = {'keqdroid', 'keqdis'};

/// Адрес подписки из ссылки, либо null — если это не наш deep link.
///
/// Хост не проверяем: панели пишут туда что угодно (`install-config`, `add`,
/// `subscribe`), значение имеет только параметр `url`.
String? subscriptionUrlFromDeepLink(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !_appSchemes.contains(uri.scheme.toLowerCase())) return null;

  final url = uri.queryParameters['url']?.trim();
  if (url == null || url.isEmpty) return null;

  // Внутри должен лежать http(s)-адрес. Панель может отдать его незакодированным,
  // и тогда Uri разберёт хвост как свой query — но параметр `url` всё равно
  // донесёт строку целиком, так что проверяем именно её.
  final inner = Uri.tryParse(url);
  if (inner == null || (inner.scheme != 'http' && inner.scheme != 'https')) {
    return null;
  }
  return url;
}
