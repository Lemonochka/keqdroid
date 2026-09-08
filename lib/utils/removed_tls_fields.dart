/// Чистка полей TLS, которые ядро больше не принимает.
///
/// Пока такое поле одно — `allowInsecure`. Ядро снесло его насмерть, и разбор
/// падает целиком: инбаунды не поднимаются, а пользователь видит «SOCKS port
/// not ready» без намёка на причину. Тот же класс аварии, что и неизвестный
/// `geosite:`-код (см. geo_rule_sanitizer).
///
/// Из ссылок поле не эмитит сам генератор; сюда оно приезжает из готовых
/// конфигов, которые мы отдаём ядру почти как есть, — одного авторского
/// `"allowInsecure": true` в любом аутбаунде хватает, чтобы положить весь
/// конфиг. Замену подставить нечем: и пиннинг, и проверка по другому имени
/// требуют данных, которых в таком конфиге нет. Поле просто выбрасывается.
library;

/// Поля, которые ядро отвергает; ключ — имя в json.
const _removedTlsKeys = {'allowInsecure'};

/// Выбрасывает [_removedTlsKeys] из всего дерева [config] на месте.
///
/// Идём по всему json, а не только по `outbounds[].streamSettings.tlsSettings`:
/// у автора эти же настройки встречаются и в инбаундах-фолбэках, и внутри
/// `sockopt.dialerProxy`-цепочек, и в `realitySettings` рядом — а ядру
/// достаточно одного вхождения в любом месте.
///
/// Возвращает число выброшенных полей: ноль — конфиг чистый.
int stripRemovedTlsFields(Object? config) {
  var dropped = 0;

  void walk(Object? node) {
    if (node is Map) {
      for (final key in _removedTlsKeys) {
        if (node.remove(key) != null) dropped++;
      }
      for (final value in node.values.toList()) {
        walk(value);
      }
    } else if (node is List) {
      for (final value in node) {
        walk(value);
      }
    }
  }

  walk(config);
  return dropped;
}
