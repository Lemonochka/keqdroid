import 'dart:convert';
import 'dart:io';

class XrayCoreSettings {
  final String logLevel;
  final String routingDomainStrategy;

  final bool dnsUseCustom;
  final String dnsServers;
  final String dnsQueryStrategy;
  final bool dnsDisableCache;
  final bool dnsSplitDirectDomains;

  final bool muxEnabled;

  final int muxConcurrency;

  final int muxXudpConcurrency;

  final String muxXudpProxyUDP443;

  final bool xmuxEnabled;
  final String xmuxMaxConcurrency;
  final String xmuxMaxConnections;
  final String xmuxCMaxReuseTimes;
  final String xmuxHMaxRequestTimes;
  final String xmuxHMaxReusableSecs;
  final int xmuxHKeepAlivePeriod;

  final bool fragmentEnabled;

  final String fragmentPackets;

  final String fragmentLength;

  final String fragmentInterval;

  final bool noiseEnabled;

  final String noiseKind;

  final String noisePacket;

  final String noiseRandLength;

  final String noiseRandBytes;

  final String noiseDelay;

  final String noiseReset;

  final bool sniffingEnabled;

  // по умолчанию false: с routeOnly ру-сайты шли на IP CDN у выхода туннеля и не грузились
  final bool sniffingRouteOnly;

  final bool concurrentDial;

  // выход для UDP по правилу каждого адреса, а не первого пакета сокета; ядра читают метку keq-udp-per-exit
  final bool udpPerAddress;

  final String dnsHosts;

  final String dnsPolicy;



  const XrayCoreSettings({
    this.logLevel = 'warning',
    this.routingDomainStrategy = 'AsIs',
    this.dnsUseCustom = false,
    this.dnsServers = 'https+local://1.1.1.1/dns-query\nhttps+local://8.8.8.8/dns-query',
    this.dnsQueryStrategy = 'UseIPv4',
    this.dnsDisableCache = false,
    this.dnsSplitDirectDomains = true,
    this.muxEnabled = false,
    this.muxConcurrency = defaultMuxConcurrency,
    this.muxXudpConcurrency = defaultMuxXudpConcurrency,
    this.muxXudpProxyUDP443 = muxUdp443Reject,
    this.xmuxEnabled = false,
    this.xmuxMaxConcurrency = '',
    this.xmuxMaxConnections = '',
    this.xmuxCMaxReuseTimes = '',
    this.xmuxHMaxRequestTimes = '',
    this.xmuxHMaxReusableSecs = '',
    this.xmuxHKeepAlivePeriod = 0,
    this.fragmentEnabled = false,
    this.fragmentPackets = fragmentPacketsTlsHello,
    this.fragmentLength = defaultFragmentLength,
    this.fragmentInterval = defaultFragmentInterval,
    this.noiseEnabled = false,
    this.noiseKind = noiseRandom,
    this.noisePacket = '',
    this.noiseRandLength = defaultNoiseRandLength,
    this.noiseRandBytes = '',
    this.noiseDelay = '',
    this.noiseReset = '',
    this.sniffingEnabled = true,
    this.sniffingRouteOnly = false,
    this.concurrentDial = false,
    this.udpPerAddress = false,
    this.dnsHosts = '',
    this.dnsPolicy = '',
  });

  static const logLevels = ['none', 'error', 'warning', 'info', 'debug'];

  static const fragmentPacketsTlsHello = 'tlshello';

  static const fragmentPacketsFirstPackets = '1-3';

  // другие значения xray не понимает, и подключение падает с SOCKS port not ready
  static const fragmentPacketModes = [
    fragmentPacketsTlsHello,
    fragmentPacketsFirstPackets,
  ];

  static const defaultFragmentLength = '100-200';
  static const defaultFragmentInterval = '10-20';

  static const muxUdp443Reject = 'reject';

  static const muxUdp443Allow = 'allow';

  static const muxUdp443Skip = 'skip';

  // четвёртое значение роняет разбор всего конфига
  static const muxUdp443Modes = [
    muxUdp443Reject,
    muxUdp443Allow,
    muxUdp443Skip,
  ];

  // rand и packet вместе xray не принимает и роняет весь конфиг
  static const noiseRandom = 'rand';

  static const noiseStr = 'str';
  static const noiseHex = 'hex';
  static const noiseBase64 = 'base64';

  static const noiseKinds = [noiseRandom, noiseStr, noiseHex, noiseBase64];

  // пустой rand у ядра значит ноль байт, то есть шума нет
  static const defaultNoiseRandLength = '50-100';

  static const defaultMuxConcurrency = 8;

  static const defaultMuxXudpConcurrency = 16;
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
        'muxEnabled': muxEnabled,
        'muxConcurrency': muxConcurrency,
        'muxXudpConcurrency': muxXudpConcurrency,
        'muxXudpProxyUDP443': muxXudpProxyUDP443,
        'xmuxEnabled': xmuxEnabled,
        'xmuxMaxConcurrency': xmuxMaxConcurrency,
        'xmuxMaxConnections': xmuxMaxConnections,
        'xmuxCMaxReuseTimes': xmuxCMaxReuseTimes,
        'xmuxHMaxRequestTimes': xmuxHMaxRequestTimes,
        'xmuxHMaxReusableSecs': xmuxHMaxReusableSecs,
        'xmuxHKeepAlivePeriod': xmuxHKeepAlivePeriod,
        'fragmentEnabled': fragmentEnabled,
        'fragmentPackets': fragmentPackets,
        'fragmentLength': fragmentLength,
        'fragmentInterval': fragmentInterval,
        'noiseEnabled': noiseEnabled,
        'noiseKind': noiseKind,
        'noisePacket': noisePacket,
        'noiseRandLength': noiseRandLength,
        'noiseRandBytes': noiseRandBytes,
        'noiseDelay': noiseDelay,
        'noiseReset': noiseReset,
        'sniffingEnabled': sniffingEnabled,
        'sniffingRouteOnly': sniffingRouteOnly,
        'concurrentDial': concurrentDial,
        'udpPerAddress': udpPerAddress,
        'dnsHosts': dnsHosts,
        'dnsPolicy': dnsPolicy,
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
    // у mux минус значит не мультиплексировать, общий i срезал бы его в ноль
    int signed(String k, int def, int min, int max) {
      final v = (json[k] as num?)?.toInt() ?? def;
      return v < min ? min : (v > max ? max : v);
    }
    final log = str('logLevel', 'warning');
    final domain = str('routingDomainStrategy', 'AsIs');
    final query = str('dnsQueryStrategy', 'UseIPv4');
    final packets = str('fragmentPackets', fragmentPacketsTlsHello);
    final udp443 = str('muxXudpProxyUDP443', muxUdp443Reject);
    final noiseKind = str('noiseKind', noiseRandom);
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
      muxEnabled: b('muxEnabled', false),
      muxConcurrency: signed('muxConcurrency', defaultMuxConcurrency, -1, 128),
      muxXudpConcurrency:
          signed('muxXudpConcurrency', defaultMuxXudpConcurrency, -1, 1024),
      muxXudpProxyUDP443: muxUdp443Modes.contains(udp443)
          ? udp443
          : muxUdp443Reject,
      xmuxEnabled: b('xmuxEnabled', false),
      xmuxMaxConcurrency: json['xmuxMaxConcurrency'] as String? ?? '',
      xmuxMaxConnections: json['xmuxMaxConnections'] as String? ?? '',
      xmuxCMaxReuseTimes: json['xmuxCMaxReuseTimes'] as String? ?? '',
      xmuxHMaxRequestTimes: json['xmuxHMaxRequestTimes'] as String? ?? '',
      xmuxHMaxReusableSecs: json['xmuxHMaxReusableSecs'] as String? ?? '',
      xmuxHKeepAlivePeriod: i('xmuxHKeepAlivePeriod', 0),
      fragmentEnabled: b('fragmentEnabled', false),
      fragmentPackets: fragmentPacketModes.contains(packets)
          ? packets
          : fragmentPacketsTlsHello,
      fragmentLength: str('fragmentLength', defaultFragmentLength),
      fragmentInterval: str('fragmentInterval', defaultFragmentInterval),
      noiseEnabled: b('noiseEnabled', false),
      noiseKind: noiseKinds.contains(noiseKind) ? noiseKind : noiseRandom,
      noisePacket: json['noisePacket'] as String? ?? '',
      noiseRandLength: str('noiseRandLength', defaultNoiseRandLength),
      noiseRandBytes: json['noiseRandBytes'] as String? ?? '',
      noiseDelay: json['noiseDelay'] as String? ?? '',
      noiseReset: json['noiseReset'] as String? ?? '',
      sniffingEnabled: b('sniffingEnabled', true),
      sniffingRouteOnly: b('sniffingRouteOnly', false),
      concurrentDial: b('concurrentDial', false),
      udpPerAddress: b('udpPerAddress', false),
      dnsHosts: json['dnsHosts'] as String? ?? '',
      dnsPolicy: json['dnsPolicy'] as String? ?? '',
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
    bool? muxEnabled,
    int? muxConcurrency,
    int? muxXudpConcurrency,
    String? muxXudpProxyUDP443,
    bool? xmuxEnabled,
    String? xmuxMaxConcurrency,
    String? xmuxMaxConnections,
    String? xmuxCMaxReuseTimes,
    String? xmuxHMaxRequestTimes,
    String? xmuxHMaxReusableSecs,
    int? xmuxHKeepAlivePeriod,
    bool? fragmentEnabled,
    String? fragmentPackets,
    String? fragmentLength,
    String? fragmentInterval,
    bool? noiseEnabled,
    String? noiseKind,
    String? noisePacket,
    String? noiseRandLength,
    String? noiseRandBytes,
    String? noiseDelay,
    String? noiseReset,
    bool? sniffingEnabled,
    bool? sniffingRouteOnly,
    bool? concurrentDial,
    bool? udpPerAddress,
    String? dnsHosts,
    String? dnsPolicy,
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
        muxEnabled: muxEnabled ?? this.muxEnabled,
        muxConcurrency: muxConcurrency ?? this.muxConcurrency,
        muxXudpConcurrency: muxXudpConcurrency ?? this.muxXudpConcurrency,
        muxXudpProxyUDP443: muxXudpProxyUDP443 ?? this.muxXudpProxyUDP443,
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
        fragmentEnabled: fragmentEnabled ?? this.fragmentEnabled,
        fragmentPackets: fragmentPackets ?? this.fragmentPackets,
        fragmentLength: fragmentLength ?? this.fragmentLength,
        fragmentInterval: fragmentInterval ?? this.fragmentInterval,
        noiseEnabled: noiseEnabled ?? this.noiseEnabled,
        noiseKind: noiseKind ?? this.noiseKind,
        noisePacket: noisePacket ?? this.noisePacket,
        noiseRandLength: noiseRandLength ?? this.noiseRandLength,
        noiseRandBytes: noiseRandBytes ?? this.noiseRandBytes,
        noiseDelay: noiseDelay ?? this.noiseDelay,
        noiseReset: noiseReset ?? this.noiseReset,
        sniffingEnabled: sniffingEnabled ?? this.sniffingEnabled,
        sniffingRouteOnly: sniffingRouteOnly ?? this.sniffingRouteOnly,
        concurrentDial: concurrentDial ?? this.concurrentDial,
        udpPerAddress: udpPerAddress ?? this.udpPerAddress,
        dnsHosts: dnsHosts ?? this.dnsHosts,
        dnsPolicy: dnsPolicy ?? this.dnsPolicy,
      );

  static ({Map<String, List<String>> entries, List<String> dropped})
      parseDnsHosts(String raw) {
    final entries = <String, List<String>>{};
    final dropped = <String>[];
    for (final line in raw.split(RegExp(r'[\n;]+'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final parts = trimmed
          .split(RegExp(r'[\s:=]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.length < 2) {
        dropped.add(trimmed);
        continue;
      }
      final reversed = _isIpAddress(parts.first) && !_isIpAddress(parts[1]);
      final key = reversed ? parts[1] : parts.first;
      final rest = reversed
          ? [parts.first, ...parts.skip(2)]
          : parts.skip(1).toList();
      final values = <String>[];
      for (final chunk in rest) {
        values.addAll(
          chunk.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
        );
      }
      final domainKey = key.toLowerCase();
      if (values.isEmpty || !_isHostMask(domainKey)) {
        dropped.add(trimmed);
        continue;
      }
      final allIps = values.every(_isIpAddress);
      final alias = values.length == 1 && _isHostMask(values.single);
      if (!allIps && !alias) {
        dropped.add(trimmed);
        continue;
      }
      entries[domainKey] = values;
    }
    return (entries: entries, dropped: dropped);
  }

  static ({Map<String, List<String>> entries, List<String> dropped})
      parseDnsPolicy(String raw) {
    final entries = <String, List<String>>{};
    final dropped = <String>[];
    for (final line in raw.split(RegExp(r'[\n;]+'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      // двоеточие не разделитель: оно внутри адресов (https://, :53)
      final parts = trimmed
          .split(RegExp(r'[\s=]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.length < 2) {
        dropped.add(trimmed);
        continue;
      }
      var key = parts.first.toLowerCase();
      if (key.endsWith(':')) key = key.substring(0, key.length - 1);
      final servers = <String>[];
      for (final chunk in parts.skip(1)) {
        for (final value in chunk.split(',')) {
          final address = value.trim();
          if (address.isEmpty) continue;
          if (xrayDnsEntry(address) == null) continue;
          servers.add(address);
        }
      }
      if (!_isHostMask(key) || servers.isEmpty) {
        dropped.add(trimmed);
        continue;
      }
      entries[key] = servers;
    }
    return (entries: entries, dropped: dropped);
  }

  static bool _isIpAddress(String value) {
    final bare = value.startsWith('[') && value.endsWith(']')
        ? value.substring(1, value.length - 1)
        : value;
    return InternetAddress.tryParse(bare) != null;
  }

  static bool _isHostMask(String value) {
    final bare = value.startsWith('*.') ? value.substring(2) : value;
    if (bare.isEmpty || bare.contains('/') || bare.contains(' ')) return false;
    return RegExp(r'^[a-z0-9_-]+(\.[a-z0-9_-]+)*$', caseSensitive: false)
        .hasMatch(bare);
  }

  static List<String> _parseServerLines(String raw) => raw
      .split(RegExp(r'[\n,;]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  // [v6]:53 xray не разбирает, а tls://, sdns:// и dhcp:// молча становятся мёртвым
  // UDP-резолвером. DoQ у него есть только как quic+local
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

  static ({String address, int? port})? _hostPort(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final bracketed = RegExp(r'^\[([0-9a-fA-F:.]+)\](?::(\d+))?$').firstMatch(trimmed);
    if (bracketed != null) {
      final port = int.tryParse(bracketed.group(2) ?? '');
      return (address: bracketed.group(1)!, port: port);
    }
    final hostPort = RegExp(r'^([^:]+):(\d+)$').firstMatch(trimmed);
    if (hostPort != null) {
      return (address: hostPort.group(1)!, port: int.tryParse(hostPort.group(2)!));
    }
    return (address: trimmed, port: null);
  }

  // как в buildDnsBlock: со своим DNS из одного сервера сплит не делается, переключатель был бы мёртвым
  bool get dnsSplitApplies =>
      !dnsUseCustom || xrayDnsServers(dnsServers).servers.length != 1;

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

  // голый домен в domains xray понимает как подстроку: example.com поймал бы notexample.community
  static String xrayDomainRule(String mask) => mask.startsWith('*.')
      ? 'domain:${mask.substring(2)}'
      : 'full:$mask';

  // голый ключ в hosts xray сравнивает целиком, поэтому *.x переводим в domain:
  Map<String, dynamic> buildHostsMap() {
    final parsed = parseDnsHosts(dnsHosts).entries;
    return {
      for (final entry in parsed.entries)
        (entry.key.startsWith('*.')
                ? 'domain:${entry.key.substring(2)}'
                : entry.key):
            entry.value.length == 1 ? entry.value.single : entry.value,
    };
  }

  Map<String, dynamic> buildDnsBlock({
    required List<String> directDomains,
    List<String> bootstrapDomains = const [],
    bool proxiedDoh = false,
  }) {
    final servers = <Map<String, dynamic>>[];

    final dohScheme = proxiedDoh ? 'https' : 'https+local';

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

    // раньше общего списка: xray опрашивает сверху вниз, и запись выше перехватила бы домен
    for (final policy in parseDnsPolicy(dnsPolicy).entries.entries) {
      final domains = [xrayDomainRule(policy.key)];
      for (final address in policy.value) {
        final entry = xrayDnsEntry(address);
        if (entry == null) continue;
        servers.add({
          'address': entry.address,
          if (entry.port != null) 'port': entry.port,
          'domains': domains,
          'skipFallback': true,
        });
      }
    }

    if (custom.isNotEmpty) {
      // length > 1: с одним сервером сплит оставил бы всё, кроме Direct, без резолвера
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
      // второй клиент тем же адресом: DoH по POST на оборванном соединении ядро не повторяет,
      // и единственный резолвер падает на EOF. дубль только здесь, после развилки про сплит
      if (custom.length == 1) servers.add(custom.single);
    } else {
      if (dnsSplitDirectDomains && directDomains.isNotEmpty) {
        servers.add({
          // системный резолвер: корпоративных и LAN-зон из Direct публичный DoH не знает
          'address': 'localhost',
          'domains': directDomains,
          'skipFallback': true,
        });
      }
      servers.add({'address': '$dohScheme://1.1.1.1/dns-query'});
      servers.add({'address': '$dohScheme://8.8.8.8/dns-query'});
      // системный последним: UDP-53 у части провайдеров подменяют, но где режут DoH,
      // без него не найти даже адрес сервера
      servers.add({'address': 'localhost'});
    }

    if (servers.isEmpty) {
      servers.add({'address': 'https+local://1.1.1.1/dns-query'});
    }

    final hosts = buildHostsMap();
    return {
      if (hosts.isNotEmpty) 'hosts': hosts,
      'servers': [for (final server in servers) _withDnsLimits(server)],
      'queryStrategy': dnsQueryStrategy,
      if (dnsDisableCache) 'disableCache': true,
    };
  }

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

  // fakedns вернул бы адрес из fake-диапазона, и подключение ушло бы в никуда
  static String? _forceLocalScheme(String address) {
    final lower = address.toLowerCase();
    if (lower == 'localhost' || lower == 'fakedns') return null;
    final scheme = RegExp(r'^([a-z][a-z0-9.+-]*)://').firstMatch(lower);
    if (scheme == null) return address;
    final name = scheme.group(1)!;
    if (name.endsWith('+local')) return address;
    return '$name+local://${address.substring(scheme.end)}';
  }

  // без этого один потерянный пакет к DoH стоил десятка секунд без новых соединений
  static Map<String, dynamic> _withDnsLimits(Map<String, dynamic> server) => {
        ...server,
        if (!server.containsKey('timeoutMs')) 'timeoutMs': _dnsTimeoutMs,
        if (!server.containsKey('serveStale')) 'serveStale': true,
      };

  static const _dnsTimeoutMs = 2500;

  // finalmask строчными, как json-тег в xray: неизвестный ключ ядро молча выбрасывает
  Map<String, dynamic>? buildNoiseItem() {
    if (!noiseEnabled) return null;
    final item = <String, dynamic>{};
    if (noiseKind == noiseRandom) {
      item['rand'] = _parseRangeValue(
        _rangeOrFallback(noiseRandLength, defaultNoiseRandLength),
      );
      final bytes = noiseRandBytes.trim();
      if (RegExp(r'^\d+(-\d+)?$').hasMatch(bytes)) {
        item['randRange'] = _parseRangeValue(bytes);
      }
    } else {
      final packet = noisePacket.trim();
      if (packet.isEmpty) {
        item['rand'] = _parseRangeValue(defaultNoiseRandLength);
      } else {
        item['type'] = noiseKind;
        item['packet'] = packet;
      }
    }
    final delay = noiseDelay.trim();
    if (RegExp(r'^\d+(-\d+)?$').hasMatch(delay)) {
      item['delay'] = _parseRangeValue(delay);
    }
    return {
      'type': 'noise',
      'settings': {
        if (RegExp(r'^\d+(-\d+)?$').hasMatch(noiseReset.trim()))
          'reset': _parseRangeValue(noiseReset.trim()),
        'noise': [item],
      },
    };
  }

  static String _rangeOrFallback(String raw, String fallback) {
    final v = raw.trim();
    return RegExp(r'^\d+(-\d+)?$').hasMatch(v) ? v : fallback;
  }

  Map<String, dynamic>? buildMuxMap() {
    if (!muxEnabled) return null;
    return {
      'enabled': true,
      'concurrency': muxConcurrency.clamp(-1, 128),
      'xudpConcurrency': muxXudpConcurrency.clamp(-1, 1024),
      'xudpProxyUDP443': muxUdp443Modes.contains(muxXudpProxyUDP443)
          ? muxXudpProxyUDP443
          : muxUdp443Reject,
    };
  }

  Map<String, dynamic>? buildXmuxMap() {
    if (!xmuxEnabled) return null;
    final map = <String, dynamic>{};
    void range(String key, String raw) {
      final v = raw.trim();
      if (v.isNotEmpty) map[key] = _parseRangeValue(v);
    }

    range('maxConcurrency', xmuxMaxConcurrency);
    // с обоими xray не разбирает конфиг: maxConnections cannot be specified together with maxConcurrency
    if (xmuxMaxConcurrency.trim().isEmpty) {
      range('maxConnections', xmuxMaxConnections);
    }
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

  // length и interval нужны оба: freedom с одним packets не поднимается
  Map<String, dynamic>? buildFragmentMap() {
    if (!fragmentEnabled) return null;
    final packets = fragmentPackets.trim();
    return {
      'packets': fragmentPacketModes.contains(packets)
          ? packets
          : fragmentPacketsTlsHello,
      'length': _fragmentRange(fragmentLength, defaultFragmentLength),
      'interval': _fragmentRange(fragmentInterval, defaultFragmentInterval),
    };
  }

  // 100- ядро не принимает, поэтому регексп строгий с обеих сторон
  static Object _fragmentRange(String raw, String fallback) {
    final v = raw.trim();
    return _parseRangeValue(
      RegExp(r'^\d+(-\d+)?$').hasMatch(v) ? v : fallback,
    );
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
          muxEnabled == other.muxEnabled &&
          muxConcurrency == other.muxConcurrency &&
          muxXudpConcurrency == other.muxXudpConcurrency &&
          muxXudpProxyUDP443 == other.muxXudpProxyUDP443 &&
          xmuxEnabled == other.xmuxEnabled &&
          xmuxMaxConcurrency == other.xmuxMaxConcurrency &&
          xmuxMaxConnections == other.xmuxMaxConnections &&
          xmuxCMaxReuseTimes == other.xmuxCMaxReuseTimes &&
          xmuxHMaxRequestTimes == other.xmuxHMaxRequestTimes &&
          xmuxHMaxReusableSecs == other.xmuxHMaxReusableSecs &&
          xmuxHKeepAlivePeriod == other.xmuxHKeepAlivePeriod &&
          fragmentEnabled == other.fragmentEnabled &&
          fragmentPackets == other.fragmentPackets &&
          fragmentLength == other.fragmentLength &&
          fragmentInterval == other.fragmentInterval &&
          noiseEnabled == other.noiseEnabled &&
          noiseKind == other.noiseKind &&
          noisePacket == other.noisePacket &&
          noiseRandLength == other.noiseRandLength &&
          noiseRandBytes == other.noiseRandBytes &&
          noiseDelay == other.noiseDelay &&
          noiseReset == other.noiseReset &&
          sniffingEnabled == other.sniffingEnabled &&
          sniffingRouteOnly == other.sniffingRouteOnly &&
          concurrentDial == other.concurrentDial &&
          udpPerAddress == other.udpPerAddress &&
          dnsHosts == other.dnsHosts &&
          dnsPolicy == other.dnsPolicy;

  @override
  int get hashCode => Object.hashAll([
        logLevel,
        routingDomainStrategy,
        dnsUseCustom,
        dnsServers,
        dnsQueryStrategy,
        dnsDisableCache,
        dnsSplitDirectDomains,
        muxEnabled,
        muxConcurrency,
        muxXudpConcurrency,
        muxXudpProxyUDP443,
        xmuxEnabled,
        xmuxMaxConcurrency,
        xmuxMaxConnections,
        xmuxCMaxReuseTimes,
        xmuxHMaxRequestTimes,
        xmuxHMaxReusableSecs,
        xmuxHKeepAlivePeriod,
        fragmentEnabled,
        fragmentPackets,
        fragmentLength,
        fragmentInterval,
        noiseEnabled,
        noiseKind,
        noisePacket,
        noiseRandLength,
        noiseRandBytes,
        noiseDelay,
        noiseReset,
        sniffingEnabled,
        sniffingRouteOnly,
        concurrentDial,
        udpPerAddress,
        dnsHosts,
        dnsPolicy,
      ]);

  String toJsonString() => jsonEncode(toJson());

  factory XrayCoreSettings.fromJsonString(String s) =>
      XrayCoreSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
