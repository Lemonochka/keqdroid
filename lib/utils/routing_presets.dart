// routing presets for the routing settings screen.
// four lists in AppSettings drive routing: directDomains/proxyDomains bypass or
// force the vpn, blockedDomains gets dropped, directIps bypasses by ip/cidr.
// a bare token without a dot (e.g. `ru`) is treated as a suffix, so it matches
// every *.ru host without shipping a geosite/geoip db.

/// which of the four routing lists a preset writes into.
enum RoutingField { directDomains, proxyDomains, blockedDomains, directIps }

/// one-tap preset that appends values into a target list.
class RoutingPreset {
  const RoutingPreset({
    required this.id,
    required this.field,
    required this.values,
  });

  /// stable id, also used to look up the localized label/description.
  final String id;

  /// Which routing list this preset contributes to.
  final RoutingField field;

  /// Values to merge into the target list.
  final List<String> values;
}

/// all presets offered in the routing screen, in display order.
class RoutingPresets {
  RoutingPresets._();

  // mirror AppSettings constructor defaults so reset gives a working baseline.
  static const String defaultDirectDomains = 'ru, yandex.ru, vk.com';
  static const String defaultDirectIps =
      '192.168.0.0/16, 10.0.0.0/8, 127.0.0.0/8';
  static const String defaultProxyDomains = '';
  static const String defaultBlockedDomains = '';

  /// *.ru/*.su/*.рф plus major russian services on non-.ru tlds. suffix match
  /// keeps the list short while covering the long tail of .ru domains.
  static const List<String> russianSites = [
    // national tld suffixes, cover most ru sites
    'ru',
    'su',
    'xn--p1ai', // .рф
    'moscow',
    'tatar',
    // yandex (non-.ru hosts/cdns)
    'yandex.net',
    'yastatic.net',
    'yandexcloud.net',
    'ya.cc',
    // vk / mail.ru
    'vk.com',
    'vk-cdn.net',
    'vk-portal.net',
    'userapi.com',
    'mycdn.me',
    'mradio.com',
    // marketplaces on non-.ru tlds
    'ozon.travel',
    'wildberries.am',
    'aliexpress.ru',
    // telecom / banking on non-.ru tlds
    'sberbank.com',
    'gazprombank.com',
    'tbank.ru',
  ];

  /// banks, payments and gov portals — direct so 2fa/sms/push works without
  /// routing all .ru traffic direct.
  static const List<String> banksAndGov = [
    'gosuslugi.ru',
    'nalog.ru',
    'nalog.gov.ru',
    'mos.ru',
    'pfr.gov.ru',
    'sberbank.ru',
    'online.sberbank.ru',
    'sber.ru',
    'tinkoff.ru',
    'tbank.ru',
    'alfabank.ru',
    'vtb.ru',
    'gazprombank.ru',
    'raiffeisen.ru',
    'open.ru',
    'psbank.ru',
    'sbol.ru',
    'mir.ru',
    'nspk.ru',
    'sbp.nspk.ru',
  ];

  /// common ad / tracker / telemetry hosts to drop.
  static const List<String> adsAndTrackers = [
    'doubleclick.net',
    'googlesyndication.com',
    'googleadservices.com',
    'google-analytics.com',
    'googletagmanager.com',
    'googletagservices.com',
    'adservice.google.com',
    'scorecardresearch.com',
    'adnxs.com',
    'criteo.com',
    'criteo.net',
    'taboola.com',
    'outbrain.com',
    'pubmatic.com',
    'rubiconproject.com',
    'moatads.com',
    'adsrvr.org',
    'mc.yandex.ru',
    'an.yandex.ru',
    'top-fwz1.mail.ru',
    'ads.vk.com',
  ];

  /// streaming/video platforms to force through the vpn.
  static const List<String> streaming = [
    'youtube.com',
    'youtu.be',
    'ytimg.com',
    'googlevideo.com',
    'ggpht.com',
    'netflix.com',
    'nflxvideo.net',
    'nflximg.net',
    'twitch.tv',
    'ttvnw.net',
    'spotify.com',
    'scdn.co',
  ];

  /// messengers often blocked locally — force through the vpn.
  static const List<String> messengers = [
    'telegram.org',
    't.me',
    'telegram.me',
    'tdesktop.com',
    'telesco.pe',
    'discord.com',
    'discord.gg',
    'discordapp.com',
    'discordapp.net',
    'discord.media',
    'signal.org',
    'whatsapp.com',
    'whatsapp.net',
  ];

  static const List<RoutingPreset> all = [
    RoutingPreset(
      id: 'ru',
      field: RoutingField.directDomains,
      values: russianSites,
    ),
    RoutingPreset(
      id: 'banks',
      field: RoutingField.directDomains,
      values: banksAndGov,
    ),
    RoutingPreset(
      id: 'ads',
      field: RoutingField.blockedDomains,
      values: adsAndTrackers,
    ),
    RoutingPreset(
      id: 'streaming',
      field: RoutingField.proxyDomains,
      values: streaming,
    ),
    RoutingPreset(
      id: 'messengers',
      field: RoutingField.proxyDomains,
      values: messengers,
    ),
  ];

  /// merge additions into a comma/newline list, keeping order and skipping
  /// case-insensitive dupes. returns a clean comma-separated string.
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
