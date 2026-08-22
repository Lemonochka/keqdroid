/// Чистка полей TLS, которые ядро больше не принимает.
///
/// Пока такое поле одно — `allowInsecure`. Xray снёс его насмерть:
///
/// ```go
/// if c.AllowInsecure {
///   return nil, errors.PrintRemovedFeatureError(
///     `"allowInsecure"`, `"pinnedPeerCertSha256"(pcs) and "verifyPeerCertByName"(vcn)`)
/// }
/// ```
///
/// (`infra/conf/transport_security.go`). В 26.3.27 отказ был по дате — «после
/// 2026-06-01», — в 26.7.28 стал безусловным. Разбор падает ЦЕЛИКОМ: ядро
/// выходит сразу, инбаунды не поднимаются, и пользователь видит «SOCKS port not
/// ready» без единого намёка на настоящую причину. Тот же класс аварии, что и
/// неизвестный `geosite:`-код (см. geo_rule_sanitizer).
///
/// Для ссылок поле не эмитит сам генератор (см. `_tlsClientSettings`), а сюда
/// оно приезжает из ГОТОВЫХ конфигов: их json мы отдаём ядру почти как есть, и
/// одно авторское `"allowInsecure": true` в любом аутбаунде лишало бы связи
/// весь конфиг.
///
/// Подставить замену нечем: `pinnedPeerCertSha256` хочет отпечаток сертификата,
/// `verifyPeerCertByName` сверяет цепочку с системными корнями по другому имени.
/// Ни того, ни другого в конфиге нет, поэтому поле просто выбрасывается, и
/// сертификат проверяется обычным порядком.
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
