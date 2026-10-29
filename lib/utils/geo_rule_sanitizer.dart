import '../models/app_settings.dart';
import 'geo_asset_index.dart';

typedef GeoSanitizeResult = ({AppSettings settings, List<String> dropped});

// только для генераторов: сохранённые настройки не трогаем, с другой базой правило может работать
GeoSanitizeResult stripUnknownGeoTokens(
  AppSettings settings,
  GeoAssetIndex index,
) {
  final direct = stripUnknownGeoTokensText(settings.directRules, index);
  final proxy = stripUnknownGeoTokensText(settings.proxyRules, index);
  final blocked = stripUnknownGeoTokensText(settings.blockedRules, index);
  final dropped = [...direct.dropped, ...proxy.dropped, ...blocked.dropped];

  if (dropped.isEmpty) return (settings: settings, dropped: const []);

  return (
    settings: settings.copyWith(
      directRules: direct.text,
      proxyRules: proxy.text,
      blockedRules: blocked.text,
    ),
    dropped: dropped,
  );
}

({String text, List<String> dropped}) stripUnknownGeoTokensText(
  String raw,
  GeoAssetIndex index,
) {
  if (index.isEmpty) return (text: raw, dropped: const []);
  final kept = <String>[];
  final dropped = <String>[];
  var replaced = false;
  for (final token in raw.split(RegExp(r'[\r\n,]+'))) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) continue;
    if (isKnownGeoToken(trimmed, index)) {
      kept.add(trimmed);
    } else if (geoSubstitutes(trimmed, index) case final subs?) {
      kept.addAll(subs);
      replaced = true;
    } else {
      dropped.add(trimmed);
    }
  }
  if (dropped.isEmpty && !replaced) return (text: raw, dropped: const []);
  return (text: kept.join(', '), dropped: dropped);
}

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

// замены по составу категории, не по похожему имени: ru-blocked тоже про ru, но это обратное ru-direct
const _geositeAliases = {
  // huzgnm/ru-direct: category-ru v2fly + ru-available-only-inside runetfreedom + зоны .ru .su .рф
  'ru-direct': ['category-ru', 'tld-ru'],
};

// незнакомый код на известные, если для него есть замена и вся она есть в базе. иначе null
List<String>? geoSubstitutes(String token, GeoAssetIndex index) {
  final trimmed = token.trim();
  final colon = trimmed.indexOf(':');
  if (colon < 0) return null;
  if (trimmed.substring(0, colon).toLowerCase() != 'geosite') return null;
  final targets = _geositeAliases[trimmed.substring(colon + 1).trim().toLowerCase()];
  if (targets == null || !targets.every(index.geositeCodes.contains)) return null;
  return [for (final code in targets) 'geosite:$code'];
}

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
  // база не прочиталась, не нам решать, что код неверный
  if (known.isEmpty) return true;
  return known.contains(code);
}
