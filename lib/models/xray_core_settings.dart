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
    this.sniffingRouteOnly = true,
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
      sniffingRouteOnly: b('sniffingRouteOnly', true),
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

  /// Builds the `dns` object for Xray config.
  Map<String, dynamic> buildDnsBlock({required List<String> directDomains}) {
    final servers = <Map<String, dynamic>>[];

    if (dnsUseCustom) {
      final lines = _parseServerLines(dnsServers);
      if (dnsSplitDirectDomains && directDomains.isNotEmpty && lines.isNotEmpty) {
        servers.add({
          'address': lines.first,
          'domains': directDomains,
          'skipFallback': true,
        });
        for (var i = 1; i < lines.length; i++) {
          servers.add({'address': lines[i]});
        }
      } else {
        for (final addr in lines) {
          servers.add({'address': addr});
        }
      }
    } else {
      if (dnsSplitDirectDomains && directDomains.isNotEmpty) {
        servers.add({
          'address': 'https+local://1.1.1.1/dns-query',
          'domains': directDomains,
          'skipFallback': true,
        });
      }
      servers.add({'address': 'https+local://1.1.1.1/dns-query'});
      servers.add({'address': 'https+local://8.8.8.8/dns-query'});
    }

    if (servers.isEmpty) {
      servers.add({'address': 'https+local://1.1.1.1/dns-query'});
    }

    return {
      'servers': servers,
      'queryStrategy': dnsQueryStrategy,
      if (dnsDisableCache) 'disableCache': true,
    };
  }

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
