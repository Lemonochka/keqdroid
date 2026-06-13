// routing presets for the routing settings screen.
// three mixed lists in AppSettings drive routing: directRules bypasses the vpn,
// proxyRules forces traffic through it, blockedRules gets dropped. each list may
// hold domains, ip/cidr ranges and prefixed rules; the config generators split
// them. a bare token without a dot (e.g. `ru`) is treated as a domain suffix, so
// it matches every *.ru host without shipping a geosite/geoip db.

/// which of the three routing lists a preset writes into.
enum RoutingField { direct, proxy, blocked }

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
  static const String defaultDirectRules = 'ru, yandex.ru, vk.com';
  static const String defaultProxyRules = '';
  static const String defaultBlockedRules = '';

  /// private / LAN ranges — offered as a preset so users can discover that the
  /// Direct list accepts IPs and CIDRs, not only domains.
  static const List<String> lanIps = [
    '192.168.0.0/16',
    '10.0.0.0/8',
    '172.16.0.0/12',
    '127.0.0.0/8',
  ];

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
      field: RoutingField.direct,
      values: russianSites,
    ),
    RoutingPreset(
      id: 'ru_geoip',
      field: RoutingField.direct,
      // geoip:ru is resolved by xray from geoip.dat (Proxy mode); covers RU
      // traffic by ip, complementing the domain-suffix `ru` preset.
      values: ['geoip:ru'],
    ),
    RoutingPreset(
      id: 'banks',
      field: RoutingField.direct,
      values: banksAndGov,
    ),
    RoutingPreset(
      id: 'lan_ips',
      field: RoutingField.direct,
      values: lanIps,
    ),
    RoutingPreset(
      id: 'ads',
      field: RoutingField.blocked,
      values: adsAndTrackers,
    ),
    RoutingPreset(
      id: 'streaming',
      field: RoutingField.proxy,
      values: streaming,
    ),
    RoutingPreset(
      id: 'messengers',
      field: RoutingField.proxy,
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
