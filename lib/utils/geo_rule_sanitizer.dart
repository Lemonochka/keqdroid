import '../models/app_settings.dart';
import 'geo_asset_index.dart';

/// Результат чистки: настройки для генераторов конфига и то, что выкинули.
typedef GeoSanitizeResult = ({AppSettings settings, List<String> dropped});

/// Убирает из списков маршрутизации `geoip:`/`geosite:` токены, которых нет в
/// поставляемых базах.
///
/// Один такой токен (`geosite:sberbank`, `geoip:telegram` — их нет в сборке
/// v2fly) роняет ВЕСЬ конфиг xray на разборе: ядро выходит сразу, SOCKS-инбаунд
/// не поднимается, и пользователь видит «Xray SOCKS5 port 2080 not ready» без
/// намёка на настоящую причину. Одна опечатка в списке не должна лишать связи,
/// поэтому неизвестное правило просто не доезжает до ядра.
///
/// Результат уходит только в генераторы конфига — сохранённые настройки не
/// трогаем, иначе правило молча исчезло бы из UI (а с другой geo-базой оно
/// может быть вполне рабочим).
GeoSanitizeResult stripUnknownGeoTokens(
  AppSettings settings,
  GeoAssetIndex index,
) {
  if (index.isEmpty) return (settings: settings, dropped: const []);

  final dropped = <String>[];

  String clean(String raw) {
    final kept = <String>[];
    for (final token in raw.split(RegExp(r'[\r\n,]+'))) {
      final trimmed = token.trim();
      if (trimmed.isEmpty) continue;
      if (isKnownGeoToken(trimmed, index)) {
        kept.add(trimmed);
      } else {
        dropped.add(trimmed);
      }
    }
    return kept.join(', ');
  }

  final direct = clean(settings.directRules);
  final proxy = clean(settings.proxyRules);
  final blocked = clean(settings.blockedRules);

  if (dropped.isEmpty) return (settings: settings, dropped: const []);

  return (
    settings: settings.copyWith(
      directRules: direct,
      proxyRules: proxy,
      blockedRules: blocked,
    ),
    dropped: dropped,
  );
}

/// geo-токены из текстового списка правил, которых нет в поставляемых базах.
///
/// Тот же критерий, по которому [stripUnknownGeoTokens] выкидывает правило перед
/// стартом ядра — но для UI: пользователь должен видеть, что `geoip:telegram`
/// (в v2fly его нет) не сработает, а не гадать, почему «ТГ не учитывается».
/// Порядок сохраняем, дубликаты убираем.
List<String> unknownGeoTokens(String raw, GeoAssetIndex index) {
  if (index.isEmpty) return const [];
  final seen = <String>{};
  final unknown = <String>[];
  for (final token in raw.split(RegExp(r'[\r\n,]+'))) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) continue;
    if (isKnownGeoToken(trimmed, index)) continue;
    if (seen.add(trimmed.toLowerCase())) unknown.add(trimmed);
  }
  return unknown;
}

/// true для всего, что не `geoip:`/`geosite:`, и для тех кодов, которые есть в
/// базе. Понимает синтаксис xray: отрицание (`geoip:!ru`) и атрибут
/// (`geosite:google@ads`) — проверяем сам код.
bool isKnownGeoToken(String token, GeoAssetIndex index) {
  final lower = token.trim().toLowerCase();
  final isGeoip = lower.startsWith('geoip:');
  final isGeosite = lower.startsWith('geosite:');
  if (!isGeoip && !isGeosite) return true;

  var code = lower.substring(lower.indexOf(':') + 1).trim();
  if (code.startsWith('!')) code = code.substring(1).trim();
  final attr = code.indexOf('@');
  if (attr >= 0) code = code.substring(0, attr).trim();
  if (code.isEmpty) return false;

  final known = isGeoip ? index.geoipCodes : index.geositeCodes;
  // База не прочиталась — не нам решать, что этот код неверный.
  if (known.isEmpty) return true;
  return known.contains(code);
}
