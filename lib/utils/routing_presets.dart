// голое слово без точки (ru) это суффикс домена: ловит все *.ru без geo-базы

enum RoutingField { direct, proxy, blocked }

class RoutingPreset {
  const RoutingPreset({
    required this.id,
    required this.field,
    required this.values,
    this.unmatched,
    this.offRunetDirect = false,
  });

  final String id;

  final RoutingField field;

  final List<String> values;

  // через VPN сам по себе ничего не меняет, пока остальное и так идёт в VPN
  final RoutingField? unmatched;

  // выключает маршруты, которые пускают напрямую весь рунет: с ними русский сайт не из списка ушёл бы мимо VPN
  final bool offRunetDirect;
}

class RoutingPresets {
  RoutingPresets._();

  // единственный источник дефолтов: на них ссылаются AppSettings и сброс экрана
  static const String defaultDirectRules = 'ru, yandex.ru, vk.com';
  static const String defaultProxyRules = '';
  static const String defaultBlockedRules = '';

  // category-ru уже несёт зоны ru, su, рф и около тысячи российских сервисов на чужих доменах.
  // geoip:ru не входит намеренно: российскими по адресу выглядят и кэши у провайдера (TikTok через Akamai в Дом.ру)
  static const List<String> russia = ['geosite:category-ru'];

  // Chocolate4U/Iran-v2ray-rules, домержен через tool/fetch_xray_geo.ps1. geoip вместе с иранскими CDN, как в их образце:
  // часть иранских сайтов не пускает зарубежные адреса, а внутри страны иностранные CDN своих узлов не держат
  static const List<String> iran = [
    'geosite:ir',
    'geoip:ir',
    'geoip:arvancloud',
    'geoip:derakcloud',
    'geoip:iranserver',
    'geoip:parspack',
  ];

  // этих шести адресов во вшитой category-ads-all нет
  static const List<String> ads = [
    'geosite:category-ads-all',
    'scorecardresearch.com',
    'criteo.com',
    'criteo.net',
    'outbrain.com',
    'rubiconproject.com',
    'adsrvr.org',
  ];

  // Re-filter (1andrevich) домержен в базы через tool/fetch_xray_geo.ps1. оба кода: часть сервисов ходит по IP без домена
  static const List<String> reFilter = [
    'geosite:refilter',
    'geoip:refilter',
  ];

  // hxehex/russia-mobile-internet-whitelist, домержен тем же скриптом. подсети оттуда не берём:
  // под TUN правило по подсети пустит напрямую любой сайт в диапазоне, а на net4people в октябре 2026 их списки ошибались в обе стороны
  static const List<String> whitelist = ['geosite:ru-whitelist'];

  static const List<RoutingPreset> all = [
    RoutingPreset(
      id: 'ru',
      field: RoutingField.direct,
      values: russia,
    ),
    RoutingPreset(
      id: 'ir',
      field: RoutingField.direct,
      values: iran,
    ),
    RoutingPreset(
      id: 'ads',
      field: RoutingField.blocked,
      values: ads,
    ),
    RoutingPreset(
      id: 'refilter',
      field: RoutingField.proxy,
      values: reFilter,
      unmatched: RoutingField.direct,
    ),
    RoutingPreset(
      id: 'whitelist',
      field: RoutingField.direct,
      values: whitelist,
      unmatched: RoutingField.proxy,
      offRunetDirect: true,
    ),
  ];

  static String mergeValues(String existing, List<String> additions) {
    final result = <String>[];
    final seen = <String>{};

    void addAll(Iterable<String> items) {
      for (final raw in items) {
        final v = raw.trim();
        if (v.isEmpty) continue;
        final key = v.toLowerCase();
        if (seen.add(key)) result.add(v);
      }
    }

    addAll(existing.split(RegExp(r'[\n,]')));
    addAll(additions);
    return result.join(', ');
  }
}
