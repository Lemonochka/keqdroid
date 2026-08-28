import 'dart:convert';

/// клиентские опции xray (dns, routing, xhttp/xmux, sniffing)
class XrayCoreSettings {
  final String logLevel;
  final String routingDomainStrategy;

  final bool dnsUseCustom;
  /// One DNS server address per line (e.g. `https+local://1.1.1.1/dns-query`).
  final String dnsServers;
  final String dnsQueryStrategy;
  final bool dnsDisableCache;
  /// When true, first resolver uses [directDomains] with skipFallback (legacy behavior).
  final bool dnsSplitDirectDomains;

  final bool xmuxEnabled;
  final String xmuxMaxConcurrency;
  final String xmuxMaxConnections;
  final String xmuxCMaxReuseTimes;
  final String xmuxHMaxRequestTimes;
  final String xmuxHMaxReusableSecs;
  final int xmuxHKeepAlivePeriod;

  final bool sniffingEnabled;

  /// `true` — снифер только подсказывает роутингу домен, соединение уходит на
  /// ТОТ адрес, который подставило приложение. `false` (умолчание, как у
  /// v2rayNG/Happ) — адресом назначения становится сам домен.
  ///
  /// Разница видна ровно там, где IP от приложения «неправильный». Домен для
  /// прямого маршрута приложение резолвит своим DNS, и если этот DNS ушёл через
  /// туннель (готовый конфиг провайдера без перехвата DNS, DoH внутри браузера,
  /// кеш до подключения), в ответе будет узел CDN, ближний к ВЫХОДУ туннеля.
  /// С `routeOnly` мы к нему и дозваниваемся — напрямую, из России, в обход
  /// туннеля: «ру-сайты не грузятся, пока не выключишь снифинг». Подмена
  /// адреса заставляет резолвить домен заново и на месте: прямой маршрут
  /// получает локальный IP, проксируемый — резолв на стороне сервера.
  final bool sniffingRouteOnly;

  const XrayCoreSettings({
    this.logLevel = 'warning',
    this.routingDomainStrategy = 'AsIs',
    this.dnsUseCustom = false,
    this.dnsServers = 'https+local://1.1.1.1/dns-query\nhttps+local://8.8.8.8/dns-query',
    this.dnsQueryStrategy = 'UseIPv4',
    this.dnsDisableCache = false,
    this.dnsSplitDirectDomains = true,
    this.xmuxEnabled = false,
    this.xmuxMaxConcurrency = '',
    this.xmuxMaxConnections = '',
    this.xmuxCMaxReuseTimes = '',
    this.xmuxHMaxRequestTimes = '',
    this.xmuxHMaxReusableSecs = '',
    this.xmuxHKeepAlivePeriod = 0,
    this.sniffingEnabled = true,
    this.sniffingRouteOnly = false,
  });

  static const logLevels = ['none', 'error', 'warning', 'info', 'debug'];
  static const dnsQueryStrategies = [
    'UseIPv4',
    'UseIPv6',
    'UseIP',
    'PreferIPv4',
    'PreferIPv6',
  ];
  static const routingDomainStrategies = ['AsIs', 'IPIfNonMatch', 'IPOnDemand'];

  Map<String, dynamic> toJson() => {
        'logLevel': logLevel,
        'routingDomainStrategy': routingDomainStrategy,
        'dnsUseCustom': dnsUseCustom,
        'dnsServers': dnsServers,
        'dnsQueryStrategy': dnsQueryStrategy,
        'dnsDisableCache': dnsDisableCache,
        'dnsSplitDirectDomains': dnsSplitDirectDomains,
        'xmuxEnabled': xmuxEnabled,
        'xmuxMaxConcurrency': xmuxMaxConcurrency,
        'xmuxMaxConnections': xmuxMaxConnections,
        'xmuxCMaxReuseTimes': xmuxCMaxReuseTimes,
        'xmuxHMaxRequestTimes': xmuxHMaxRequestTimes,
        'xmuxHMaxReusableSecs': xmuxHMaxReusableSecs,
        'xmuxHKeepAlivePeriod': xmuxHKeepAlivePeriod,
        'sniffingEnabled': sniffingEnabled,
        'sniffingRouteOnly': sniffingRouteOnly,
      };

  factory XrayCoreSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const XrayCoreSettings();
    String str(String k, String def) => (json[k] as String?)?.trim().isNotEmpty == true
        ? (json[k] as String).trim()
        : def;
    bool b(String k, bool def) => json[k] as bool? ?? def;
    int i(String k, int def) {
      final v = (json[k] as num?)?.toInt() ?? def;
      return v < 0 ? 0 : v;
    }
    final log = str('logLevel', 'warning');
    final domain = str('routingDomainStrategy', 'AsIs');
    final query = str('dnsQueryStrategy', 'UseIPv4');
    return XrayCoreSettings(
      logLevel: logLevels.contains(log) ? log : 'warning',
      routingDomainStrategy:
          routingDomainStrategies.contains(domain) ? domain : 'AsIs',
      dnsUseCustom: b('dnsUseCustom', false),
      dnsServers: json['dnsServers'] as String? ??
          'https+local://1.1.1.1/dns-query\nhttps+local://8.8.8.8/dns-query',
      dnsQueryStrategy: dnsQueryStrategies.contains(query) ? query : 'UseIPv4',
      dnsDisableCache: b('dnsDisableCache', false),
      dnsSplitDirectDomains: b('dnsSplitDirectDomains', true),
      xmuxEnabled: b('xmuxEnabled', false),
      xmuxMaxConcurrency: json['xmuxMaxConcurrency'] as String? ?? '',
      xmuxMaxConnections: json['xmuxMaxConnections'] as String? ?? '',
      xmuxCMaxReuseTimes: json['xmuxCMaxReuseTimes'] as String? ?? '',
      xmuxHMaxRequestTimes: json['xmuxHMaxRequestTimes'] as String? ?? '',
      xmuxHMaxReusableSecs: json['xmuxHMaxReusableSecs'] as String? ?? '',
      xmuxHKeepAlivePeriod: i('xmuxHKeepAlivePeriod', 0),
      sniffingEnabled: b('sniffingEnabled', true),
      sniffingRouteOnly: b('sniffingRouteOnly', false),
    );
  }

  XrayCoreSettings copyWith({
    String? logLevel,
    String? routingDomainStrategy,
    bool? dnsUseCustom,
    String? dnsServers,
    String? dnsQueryStrategy,
    bool? dnsDisableCache,
    bool? dnsSplitDirectDomains,
    bool? xmuxEnabled,
    String? xmuxMaxConcurrency,
    String? xmuxMaxConnections,
    String? xmuxCMaxReuseTimes,
    String? xmuxHMaxRequestTimes,
    String? xmuxHMaxReusableSecs,
    int? xmuxHKeepAlivePeriod,
    bool? sniffingEnabled,
    bool? sniffingRouteOnly,
  }) =>
      XrayCoreSettings(
        logLevel: logLevel ?? this.logLevel,
        routingDomainStrategy:
            routingDomainStrategy ?? this.routingDomainStrategy,
        dnsUseCustom: dnsUseCustom ?? this.dnsUseCustom,
        dnsServers: dnsServers ?? this.dnsServers,
        dnsQueryStrategy: dnsQueryStrategy ?? this.dnsQueryStrategy,
        dnsDisableCache: dnsDisableCache ?? this.dnsDisableCache,
        dnsSplitDirectDomains:
            dnsSplitDirectDomains ?? this.dnsSplitDirectDomains,
        xmuxEnabled: xmuxEnabled ?? this.xmuxEnabled,
        xmuxMaxConcurrency: xmuxMaxConcurrency ?? this.xmuxMaxConcurrency,
        xmuxMaxConnections: xmuxMaxConnections ?? this.xmuxMaxConnections,
        xmuxCMaxReuseTimes: xmuxCMaxReuseTimes ?? this.xmuxCMaxReuseTimes,
        xmuxHMaxRequestTimes:
            xmuxHMaxRequestTimes ?? this.xmuxHMaxRequestTimes,
        xmuxHMaxReusableSecs:
            xmuxHMaxReusableSecs ?? this.xmuxHMaxReusableSecs,
        xmuxHKeepAlivePeriod:
            xmuxHKeepAlivePeriod ?? this.xmuxHKeepAlivePeriod,
        sniffingEnabled: sniffingEnabled ?? this.sniffingEnabled,
        sniffingRouteOnly: sniffingRouteOnly ?? this.sniffingRouteOnly,
      );

  static List<String> _parseServerLines(String raw) => raw
      .split(RegExp(r'[\n,;]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  /// Один DNS-адрес в виде, который РЕАЛЬНО исполняет xray, или null — такой
  /// адрес ядро не поднимет и его лучше выбросить.
  ///
  /// Поле `address` у xray — не «строка подключения». Если в ней не узнаётся IP,
  /// строка считается доменом и разбирается как URL (`app/dns.NewServer`), а
  /// дальше сравнивается со списком поддерживаемых схем. Отсюда две ловушки,
  /// каждая из которых оставляет пользователя без DNS:
  ///
  ///  * `[2606:4700:4700::1111]:53` — не IP (скобки и порт), как URL не
  ///    разбирается вовсе: «first path segment in URL cannot contain colon».
  ///    Ядро не стартует, туннель не поднимается. Порт у xray живёт отдельным
  ///    полем `port`, поэтому host и порт мы разделяем сами.
  ///  * `tls://`, `sdns://`, `dhcp://` и прочее вне списка схем ошибки не дают:
  ///    строка молча становится ДОМЕНОМ обычного UDP-резолвера, который никогда
  ///    не резолвится. Такие адреса выбрасываем — работающий дефолт лучше
  ///    сломанного выбора.
  ///  * `quic://` xray тоже не знает: DoQ у него есть только как `quic+local`
  ///    (удалённого режима у QUIC-резолвера нет). Приводим к нему, вместо того
  ///    чтобы терять адрес.
  static ({String address, int? port})? xrayDnsEntry(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    if (lower == 'localhost' || lower == 'fakedns') {
      return (address: lower, port: null);
    }

    final schemeMatch = RegExp(r'^([a-z][a-z0-9.+-]*)://').firstMatch(lower);
    if (schemeMatch != null) {
      final scheme = schemeMatch.group(1)!;
      final rest = trimmed.substring(schemeMatch.end);
      switch (scheme) {
        case 'https':
        case 'https+local':
        case 'h2c':
        case 'h2c+local':
        case 'tcp':
        case 'tcp+local':
        case 'quic+local':
          return (address: trimmed, port: null);
        case 'quic':
        case 'doq':
        case 'doq+local':
          return (address: 'quic+local://$rest', port: null);
        // Голый UDP: схему xray не знает, но она и не нужна — это его дефолт.
        case 'udp':
        case 'udp+local':
        case 'dns':
          return _hostPort(rest);
        default:
          return null;
      }
    }

    return _hostPort(trimmed);
  }

  /// `host` / `host:port` / `[v6]:port` / голый IPv6 → адрес и порт отдельно.
  static ({String address, int? port})? _hostPort(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final bracketed = RegExp(r'^\[([0-9a-fA-F:.]+)\](?::(\d+))?$').firstMatch(trimmed);
    if (bracketed != null) {
      final port = int.tryParse(bracketed.group(2) ?? '');
      return (address: bracketed.group(1)!, port: port);
    }
    // Ровно одно двоеточие с числовым портом — иначе это голый IPv6.
    final hostPort = RegExp(r'^([^:]+):(\d+)$').firstMatch(trimmed);
    if (hostPort != null) {
      return (address: hostPort.group(1)!, port: int.tryParse(hostPort.group(2)!));
    }
    return (address: trimmed, port: null);
  }

  /// DNS-адреса пользователя, приведённые под xray. Второй список — то, что
  /// выброшено: вызывающий пишет его в лог, чтобы «мой DNS не применился» имело
  /// объяснение.
  static ({List<Map<String, dynamic>> servers, List<String> dropped})
      xrayDnsServers(String raw) {
    final servers = <Map<String, dynamic>>[];
    final dropped = <String>[];
    for (final line in _parseServerLines(raw)) {
      final entry = xrayDnsEntry(line);
      if (entry == null) {
        dropped.add(line);
        continue;
      }
      servers.add({
        'address': entry.address,
        if (entry.port != null) 'port': entry.port,
      });
    }
    return (servers: servers, dropped: dropped);
  }

  /// Builds the `dns` object for Xray config.
  ///
  /// [bootstrapDomains] — адреса самих прокси-серверов (свой узел и звенья
  /// цепочки). Их НЕЛЬЗЯ резолвить через туннель: адрес сервера нужен, чтобы до
  /// сервера дозвониться, и запрос по нему через прокси означал бы круг. Отсюда
  /// отдельные записи со схемой `+local` — тот же DoH, но запрос идёт напрямую,
  /// минуя роутинг, — и системный резолвер следом.
  ///
  /// Системный резолвер стоит здесь ВТОРЫМ, а не первым, как было раньше:
  /// открытый UDP-53 у части провайдеров подменяется. Ответ при этом приходит с
  /// ПОДСТАВЛЕННЫМ адресом источника, так что ни по конфигу, ни по `dig` подмена
  /// не видна — она ловится только сравнением с TCP/53 или DoH. Пока домены
  /// серверов в реестр не попадают, коннект от этого не ломался, но провайдеру
  /// уходил список узлов, к которым подключается пользователь. Ping-режим
  /// резолвил сервер по DoH уже давно (см. `generatePingConfig`), боевой конфиг
  /// — нет, и «пинг зелёный, а подключения нет» было бы ровно отсюда.
  ///
  /// Перебор обрывает `finalQuery`, а НЕ `skipFallback`. `skipFallback` значит
  /// другое: «не использовать этот сервер для доменов, которые в его `domains`
  /// не попали». В `app/dns.sortClients` сначала идут совпавшие серверы в
  /// порядке конфига, а следом — все остальные без `skipFallback`; свалиться С
  /// записи на другие он не мешает. Без `finalQuery` промах по адресу сервера
  /// уходил бы в общий DoH, а в режиме глобал-прокси тот ведёт в ещё не
  /// поднятый туннель.
  ///
  /// [proxiedDoh] — гнать ли DoH внутрь туннеля (`https://` вместо
  /// `https+local://`). Включаем в режиме глобал-прокси: тогда все DNS-запросы
  /// устройства схлопываются в одно постоянное HTTP/2-соединение до 1.1.1.1
  /// внутри туннеля, вместо отдельного TCP до сервера на каждый запрос. В
  /// режимах «остальное — direct/block» оставляем прямой DoH: там `final` увёл
  /// бы запрос к резолверу мимо прокси (или вовсе в blackhole), да и трафика к
  /// серверу там на порядок меньше.
  Map<String, dynamic> buildDnsBlock({
    required List<String> directDomains,
    List<String> bootstrapDomains = const [],
    bool proxiedDoh = false,
  }) {
    final servers = <Map<String, dynamic>>[];

    final dohScheme = proxiedDoh ? 'https' : 'https+local';

    // Пустой список после чистки (пользователь вписал только то, чего ядро не
    // исполняет) — не повод остаться без резолвера: уходим в ветку дефолта.
    final custom = dnsUseCustom
        ? xrayDnsServers(dnsServers).servers
        : const <Map<String, dynamic>>[];

    if (bootstrapDomains.isNotEmpty) {
      for (final server in _bootstrapResolvers(custom)) {
        servers.add({
          ...server,
          'domains': bootstrapDomains,
          'skipFallback': true,
        });
      }
      servers.add({
        'address': 'localhost',
        'domains': bootstrapDomains,
        'skipFallback': true,
        'finalQuery': true,
      });
    }

    if (custom.isNotEmpty) {
      // `length > 1`, а не `isNotEmpty`: первая строка уходит под
      // Direct-домены со `skipFallback`, то есть общего резолва не касается.
      // Когда сервер в списке ОДИН, такой раскладке не остаётся резолвера
      // вообще — всё, чего нет в Direct-списке, не резолвится ничем, и это
      // выглядит как «прописал свой DNS, и интернет пропал». С одним сервером
      // сплит и не нужен: он и так отвечает на всё, включая Direct-домены.
      if (dnsSplitDirectDomains && directDomains.isNotEmpty && custom.length > 1) {
        servers.add({
          ...custom.first,
          'domains': directDomains,
          'skipFallback': true,
        });
        servers.addAll(custom.skip(1));
      } else {
        servers.addAll(custom);
      }
    } else {
      if (dnsSplitDirectDomains && directDomains.isNotEmpty) {
        servers.add({
          // 'localhost' — системный резолвер xray. Direct-домены включают
          // корпоративные/LAN-зоны сплит-DNS, которых публичный DoH не знает:
          // с ним домен из Direct-списка получал NXDOMAIN при direct-маршруте.
          'address': 'localhost',
          'domains': directDomains,
          'skipFallback': true,
        });
      }
      servers.add({'address': '$dohScheme://1.1.1.1/dns-query'});
      servers.add({'address': '$dohScheme://8.8.8.8/dns-query'});
      // Последним — системный резолвер, на случай сети, где DoH к 1.1.1.1 и
      // 8.8.8.8 просто не пускают. Через него теперь резолвится и адрес самого
      // сервера (streamSettings.sockopt.domainStrategy), так что «DoH не
      // прошёл» означало бы «подключения нет вообще». Спрашивается он только
      // когда оба DoH промолчали.
      servers.add({'address': 'localhost'});
    }

    if (servers.isEmpty) {
      servers.add({'address': 'https+local://1.1.1.1/dns-query'});
    }

    return {
      'servers': [for (final server in servers) _withDnsLimits(server)],
      'queryStrategy': dnsQueryStrategy,
      if (dnsDisableCache) 'disableCache': true,
    };
  }

  /// Чем искать адрес самого сервера, в порядке опроса. Системный резолвер
  /// идёт после них и добавляется вызывающим.
  ///
  /// Не больше двух записей: каждый молчащий резолвер стоит [_dnsTimeoutMs], а
  /// этот список лежит на критическом пути к подключению. В сети, где DoH
  /// режут, цена платится не один раз при старте, а перед каждым коннектом с
  /// истёкшим TTL — поэтому по умолчанию тут ОДИН адрес, а не пара, как в
  /// общем списке.
  static List<Map<String, dynamic>> _bootstrapResolvers(
    List<Map<String, dynamic>> custom,
  ) {
    if (custom.isEmpty) {
      return [
        {'address': 'https+local://1.1.1.1/dns-query'},
      ];
    }
    final out = <Map<String, dynamic>>[];
    for (final server in custom) {
      final address = server['address'];
      if (address is! String) continue;
      final local = _forceLocalScheme(address);
      if (local == null) continue;
      out.add({...server, 'address': local});
      if (out.length == 2) break;
    }
    return out;
  }

  /// `https://` → `https+local://`: тот же резолвер, но запрос идёт напрямую, а
  /// не через outbound-цепочку.
  ///
  /// null — адрес, которым адрес сервера искать нельзя: `localhost` вызывающий
  /// добавляет сам последним, а `fakedns` вернул бы на него ПОДДЕЛЬНЫЙ IP из
  /// fake-диапазона, и подключение ушло бы в никуда.
  static String? _forceLocalScheme(String address) {
    final lower = address.toLowerCase();
    if (lower == 'localhost' || lower == 'fakedns') return null;
    final scheme = RegExp(r'^([a-z][a-z0-9.+-]*)://').firstMatch(lower);
    // Голый хост — это UDP-резолвер, он и так опрашивается напрямую.
    if (scheme == null) return address;
    final name = scheme.group(1)!;
    if (name.endsWith('+local')) return address;
    return '$name+local://${address.substring(scheme.end)}';
  }

  /// Сколько ждать ОДИН резолвер и что делать, когда он молчит.
  ///
  /// Это лечение «интернет отвалился секунд на двадцать и вернулся сам».
  /// Резолверы xray опрашивает ПО ОЧЕРЕДИ, а таймаут у него по умолчанию 4
  /// секунды на каждый (`app/dns/nameserver.go`). В списке их до четырёх —
  /// bootstrap, два DoH, системный, — и один потерянный пакет к первому DoH
  /// стоит 4+4+4 секунд ожидания. Всё это время новые соединения стоят: с
  /// `IPIfNonMatch` (он включается сам, стоит завести хоть одно IP-правило)
  /// резолв нужен КАЖДОМУ соединению до выбора маршрута. Отсюда и «просто
  /// произвольная хуйня, без периодичности»: зависит от того, когда истёк TTL
  /// и повезло ли пакету.
  ///
  /// [_dnsTimeoutMs] режет цену одного молчащего резолвера, `serveStale` —
  /// саму паузу: пока ядро ходит за свежим ответом, оно отдаёт просроченный из
  /// кэша, и пользователь не замечает ничего. Оба поля — на каждом сервере,
  /// потому что у xray они per-server, а не глобальные.
  static Map<String, dynamic> _withDnsLimits(Map<String, dynamic> server) => {
        ...server,
        if (!server.containsKey('timeoutMs')) 'timeoutMs': _dnsTimeoutMs,
        if (!server.containsKey('serveStale')) 'serveStale': true,
      };

  /// 2.5 с: DoH через туннель укладывается в сотни миллисекунд даже на
  /// мобильной сети, а вчетверо больший дефолт ядра существует ради совсем
  /// плохих каналов — ценой той самой двадцатисекундной паузы.
  static const _dnsTimeoutMs = 2500;

  /// XMUX block for XHTTP `extra` (client-only).
  Map<String, dynamic>? buildXmuxMap() {
    if (!xmuxEnabled) return null;
    final map = <String, dynamic>{};
    void range(String key, String raw) {
      final v = raw.trim();
      if (v.isNotEmpty) map[key] = _parseRangeValue(v);
    }

    range('maxConcurrency', xmuxMaxConcurrency);
    range('maxConnections', xmuxMaxConnections);
    range('cMaxReuseTimes', xmuxCMaxReuseTimes);
    range('hMaxRequestTimes', xmuxHMaxRequestTimes);
    range('hMaxReusableSecs', xmuxHMaxReusableSecs);
    if (xmuxHKeepAlivePeriod > 0) {
      map['hKeepAlivePeriod'] = xmuxHKeepAlivePeriod;
    }
    return map.isEmpty ? <String, dynamic>{} : map;
  }

  static Object _parseRangeValue(String v) {
    if (RegExp(r'^\d+$').hasMatch(v)) return int.parse(v);
    return v;
  }

  Map<String, dynamic> buildSniffing() => {
        'enabled': sniffingEnabled,
        'destOverride': ['http', 'tls', 'quic'],
        'routeOnly': sniffingRouteOnly,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is XrayCoreSettings &&
          runtimeType == other.runtimeType &&
          logLevel == other.logLevel &&
          routingDomainStrategy == other.routingDomainStrategy &&
          dnsUseCustom == other.dnsUseCustom &&
          dnsServers == other.dnsServers &&
          dnsQueryStrategy == other.dnsQueryStrategy &&
          dnsDisableCache == other.dnsDisableCache &&
          dnsSplitDirectDomains == other.dnsSplitDirectDomains &&
          xmuxEnabled == other.xmuxEnabled &&
          xmuxMaxConcurrency == other.xmuxMaxConcurrency &&
          xmuxMaxConnections == other.xmuxMaxConnections &&
          xmuxCMaxReuseTimes == other.xmuxCMaxReuseTimes &&
          xmuxHMaxRequestTimes == other.xmuxHMaxRequestTimes &&
          xmuxHMaxReusableSecs == other.xmuxHMaxReusableSecs &&
          xmuxHKeepAlivePeriod == other.xmuxHKeepAlivePeriod &&
          sniffingEnabled == other.sniffingEnabled &&
          sniffingRouteOnly == other.sniffingRouteOnly;

  @override
  int get hashCode => Object.hash(
        logLevel,
        routingDomainStrategy,
        dnsUseCustom,
        dnsServers,
        dnsQueryStrategy,
        dnsDisableCache,
        dnsSplitDirectDomains,
        xmuxEnabled,
        xmuxMaxConcurrency,
        xmuxMaxConnections,
        xmuxCMaxReuseTimes,
        xmuxHMaxRequestTimes,
        xmuxHMaxReusableSecs,
        xmuxHKeepAlivePeriod,
        sniffingEnabled,
        sniffingRouteOnly,
      );

  String toJsonString() => jsonEncode(toJson());

  factory XrayCoreSettings.fromJsonString(String s) =>
      XrayCoreSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
