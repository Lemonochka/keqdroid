import 'dart:convert';
import 'dart:io' show InternetAddress;

import '../models/app_settings.dart';
import '../models/traffic_route.dart';
import '../models/tun_settings.dart';
import '../models/xray_core_settings.dart';
import '../tunnel/app_routing_mode.dart';
import '../utils/custom_xray_config.dart';
import '../utils/desktop_tun.dart';
import '../utils/exit_ip_probe.dart';
import '../utils/fake_ip.dart';
import '../utils/geo_asset_index.dart';
import '../utils/hysteria_uri.dart';
import '../utils/owner_guard.dart';
import '../utils/proxy_chain.dart';
import '../utils/app_routes.dart';
import '../utils/route_servers.dart';
import '../utils/routing_entry.dart';
import '../utils/rule_lists.dart';
import '../utils/socks5_credentials.dart';
import '../utils/socks_uri.dart';
import '../utils/tls_fingerprint.dart';

// причуды xray 26: пустой fingerprint ядро читает как chrome, allowInsecure не пишем вовсе,
// echConfigList строкой, у hysteria2 network hysteria, а не quic
class ConfigGeneratorV2 {
  static String generateConfig(
    String input,
    AppSettings settings, {
    String? resolvedServerIp,
    bool localInboundsNoAuth = false,
    bool nativeTunInbound = false,
    DesktopTunOptions? desktopTun,
    GeoAssetIndex? geoIndex,
    List<RouteServerOutbound> routeServers = const [],
    List<RouteAppRules> appRoutes = const [],
    OwnerGuard ownerGuard = OwnerGuard.off,
  }) {
    return const JsonEncoder.withIndent('  ').convert(
      _buildXrayConfig(
        input,
        settings,
        resolvedServerIp: resolvedServerIp,
        localInboundsNoAuth: localInboundsNoAuth,
        nativeTunInbound: nativeTunInbound,
        desktopTun: desktopTun,
        geoIndex: geoIndex,
        routeServers: routeServers,
        appRoutes: appRoutes,
        ownerGuard: ownerGuard,
      ),
    );
  }

  static String generatePingConfig(
    String input,
    AppSettings settings, {
    required int socksPort,
    String? resolvedServerIp,
    bool httpInbound = false,
    String? outboundInterface,
  }) {
    final config = _buildXrayConfig(
      input,
      settings,
      resolvedServerIp: resolvedServerIp,
      pingSocksPort: socksPort,
      pingHttpInbound: httpInbound,
    );
    if (outboundInterface != null) {
      _bindToInterface(config, outboundInterface);
    }
    return jsonEncode(config);
  }

  // копии, а не правка на месте: свой direct готового JSON собран как Map<String, String>
  static void _bindToInterface(Map<String, dynamic> config, String name) {
    final outbounds = config['outbounds'];
    if (outbounds is! List) return;
    config['outbounds'] = [
      for (final outbound in outbounds) _boundOutbound(outbound, name),
    ];
  }

  // сокет наружу открывает аутбаунд без dialerProxy и proxySettings, остальные едут через него
  static Object? _boundOutbound(Object? outbound, String name) {
    if (outbound is! Map) return outbound;
    final protocol = outbound['protocol'];
    if (protocol == 'blackhole' || protocol == 'loopback') return outbound;
    if (outbound['proxySettings'] != null) return outbound;
    final stream = Map<String, dynamic>.from(
      outbound['streamSettings'] as Map? ?? const <String, dynamic>{},
    );
    final sockopt = Map<String, dynamic>.from(
      stream['sockopt'] as Map? ?? const <String, dynamic>{},
    );
    if ((sockopt['dialerProxy']?.toString() ?? '').isNotEmpty) return outbound;
    sockopt.putIfAbsent('interface', () => name);
    return <String, dynamic>{
      ...Map<String, dynamic>.from(outbound),
      'streamSettings': {...stream, 'sockopt': sockopt},
    };
  }

  static const int ephemeralPingPort = 28150;

  // IPv6 тоже: regex только под IPv4 делал direct-правило для сервера доменным, и трафик к нему мог закольцеваться
  static bool _isIpLiteral(String value) =>
      InternetAddress.tryParse(value.trim()) != null;

  // держать в паре с KeqdisVpnService.TUN_DNS_ADDRESS. слушать на нём некому, запрос обязан попасть в перехват
  static const String _androidTunDns = '172.19.0.2';

  // настоящее значение ставит нативная часть через setMtu, числа обязаны совпасть
  static const int _defaultTunMtu = 1400;

  // имя обязательно: пустое ядро ищет само через net.Interfaces(), а netlink на Android
  // для приложения закрыт (netlinkrib: permission denied), и падает весь конфиг
  static const String _tunInterfaceName = 'keqtun0';

  static bool _lanAuthEnabled(AppSettings settings) =>
      settings.lanUsername.trim().isNotEmpty && settings.lanPassword.isNotEmpty;

  static List<String>? _splitAlpn(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final list = raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return list.isEmpty ? null : list;
  }

  // ws и httpupgrade поднимаются апгрейдом по HTTP/1.1, выбери сервер h2, апгрейда не будет.
  // одиночный alpn=h2 не трогаем, его могли поставить осознанно
  static List<String> _alpnForNetwork(String network, List<String> alpn) =>
      (network == 'ws' || network == 'httpupgrade') &&
              alpn.length == 2 &&
              alpn[0] == 'h2' &&
              alpn[1] == 'http/1.1'
          ? const ['http/1.1']
          : alpn;

  // allowInsecure не пишем никогда: ядро поле снесло, и один сервер с insecure=1 ронял всю подписку.
  // pcs и vcn читаем: сертификат сверяется с настоящим именем, а в ClientHello уходит маскировочное
  static Map<String, dynamic> _tlsClientSettings({
    required String serverName,
    required String network,
    String fingerprint = '',
    String? alpnQuery,
    String? echConfigList,
    String? pinnedPeerCertSha256,
    String? verifyPeerCertByName,
  }) {
    final tls = <String, dynamic>{
      'serverName': serverName,
    };
    final fp = fingerprint.trim();
    if (fp.isNotEmpty) {
      tls['fingerprint'] = fp;
    } else if (network != 'hysteria') {
      tls['fingerprint'] = defaultTlsFingerprint;
    }
    final alpn = _splitAlpn(alpnQuery);
    if (alpn != null) tls['alpn'] = _alpnForNetwork(network, alpn);
    final ech = echConfigList?.trim() ?? '';
    if (ech.isNotEmpty) tls['echConfigList'] = ech;
    final pin = pinnedPeerCertSha256?.trim() ?? '';
    if (pin.isNotEmpty) tls['pinnedPeerCertSha256'] = pin;
    final verifyName = verifyPeerCertByName?.trim() ?? '';
    if (verifyName.isNotEmpty) tls['verifyPeerCertByName'] = verifyName;
    return tls;
  }

  // + не трогаем: запрос по RFC 3986, а не по правилам формы
  static String _rawQueryParam(Uri uri, String key, String def) {
    for (final pair in uri.query.split('&')) {
      final eq = pair.indexOf('=');
      if (eq < 0) continue;
      if (Uri.decodeComponent(pair.substring(0, eq)) != key) continue;
      final value = Uri.decodeComponent(pair.substring(eq + 1));
      if (value.isNotEmpty) return value;
    }
    return def;
  }

  static String _decodeBase64UrlCompat(String input) {
    var normalized = input.trim().replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    return utf8.decode(base64.decode(normalized));
  }

  // у vmess два формата: base64 от json и AEAD (#716). различаем как mihomo: не base64 значит ссылка
  static Map<String, dynamic>? _parseVmessPayload(String input) {
    final payload = input.substring('vmess://'.length).trim();
    if (payload.isEmpty) {
      throw ArgumentError('VMess payload is empty');
    }
    try {
      final parsed = jsonDecode(_decodeBase64UrlCompat(payload));
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {}
    // @ в base64 не бывает, у AEAD перед адресом UUID
    if (payload.contains('@')) return null;
    throw ArgumentError('Invalid VMess payload format');
  }

  static Map<String, dynamic> _buildXrayConfig(
    String input,
    AppSettings settings, {
    String? resolvedServerIp,
    int? pingSocksPort,
    bool pingHttpInbound = false,
    bool localInboundsNoAuth = false,
    bool nativeTunInbound = false,
    DesktopTunOptions? desktopTun,
    GeoAssetIndex? geoIndex,
    List<RouteServerOutbound> routeServers = const [],
    List<RouteAppRules> appRoutes = const [],
    OwnerGuard ownerGuard = OwnerGuard.off,
  }) {
    final trimmed = input.trim();
    final pc = pingSocksPort == null ? desktopTun : null;
    final tunInbound = nativeTunInbound || pc != null;
    final guard = pingSocksPort == null && nativeTunInbound && pc == null
        ? ownerGuard
        : OwnerGuard.off;

    final chain = ProxyChainConfig.tryParse(trimmed);
    final parsedCustom = chain == null ? CustomXrayConfig.tryParse(trimmed) : null;
    final custom = settings.ignoreProviderRules
        ? parsedCustom?.withoutProviderRules()
        : parsedCustom;
    final Map<String, dynamic> config;
    if (chain != null) {
      config = _buildChainConfig(
        chain,
        settings,
        resolvedServerIp: resolvedServerIp,
        pingSocksPort: pingSocksPort,
        pingHttpInbound: pingHttpInbound,
        localInboundsNoAuth: localInboundsNoAuth,
        nativeTunInbound: tunInbound,
        desktopTun: pc,
        routeServers: routeServers,
        appRoutes: appRoutes,
        ownerGuard: guard,
      );
    } else if (custom != null) {
      config = _buildCustomConfig(
        custom,
        settings,
        resolvedServerIp: resolvedServerIp,
        pingSocksPort: pingSocksPort,
        pingHttpInbound: pingHttpInbound,
        localInboundsNoAuth: localInboundsNoAuth,
        nativeTunInbound: tunInbound,
        desktopTun: pc,
        geoIndex: geoIndex,
        routeServers: routeServers,
        appRoutes: appRoutes,
        ownerGuard: guard,
      );
    } else {
      final link = _buildLinkOutbound(trimmed, settings);
      _applyMux(link.outbound, settings.xrayCore);

      config = _wrapConfig(
        [link.outbound],
        settings,
        resolvedServerIp ?? link.address,
        link.port,
        originalServerAddress: link.address,
        pingSocksPort: pingSocksPort,
        pingHttpInbound: pingHttpInbound,
        localInboundsNoAuth: localInboundsNoAuth,
        nativeTunInbound: tunInbound,
        desktopTun: pc,
        routeServers: routeServers,
        appRoutes: appRoutes,
        ownerGuard: guard,
      );
    }
    if (pc != null) _applyDesktopTunPolicy(config, pc);
    return config;
  }

  static ({Map<String, dynamic> outbound, String address, int port})
      _buildLinkOutbound(String trimmed, AppSettings settings) {
    final bool isVmess = trimmed.toLowerCase().startsWith('vmess://');
    final lowerTrimmed = trimmed.toLowerCase();
    final bool isHysteria = lowerTrimmed.startsWith('hysteria://') ||
        lowerTrimmed.startsWith('hysteria2://') ||
        lowerTrimmed.startsWith('hy2://');

    if (SocksLink.isSocks(trimmed)) {
      final socks = SocksLink.tryParse(trimmed);
      if (socks == null) throw ArgumentError('Invalid SOCKS link');
      final outbound = <String, dynamic>{
        'tag': 'proxy',
        'protocol': 'socks',
        'settings': {
          'address': socks.host,
          'port': socks.port,
          if (socks.username.isNotEmpty) 'user': socks.username,
          if (socks.username.isNotEmpty) 'pass': socks.password,
        },
        'streamSettings': <String, dynamic>{'network': 'tcp'},
      };
      _applyXrayStreamExtras(outbound, settings.xrayCore);
      _applyServerDomainStrategy(outbound, socks.host, settings.xrayCore);
      return (outbound: outbound, address: socks.host, port: socks.port);
    }

    Uri uri;
    Map<String, dynamic>? vmessConfig;

    try {
      if (isVmess) {
        vmessConfig = _parseVmessPayload(trimmed);
        uri = vmessConfig != null ? Uri.parse('vmess://proxy') : Uri.parse(trimmed);
      } else if (isHysteria) {
        // Uri.parse не берёт порт вида host:20000-20050
        uri = Uri.parse(HysteriaLinkParams.splitPorts(trimmed).$1);
      } else {
        uri = Uri.parse(trimmed);
      }
    } catch (e) {
      // без самого конфига: в нём UUID и пароль, а ошибки уходят в логи и Crashlytics
      final scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):').firstMatch(trimmed)?.group(1);
      throw ArgumentError(
        'Invalid URI format in server config'
        '${scheme != null ? ' (scheme: $scheme)' : ''}',
      );
    }

    final scheme = isVmess ? 'vmess' : uri.scheme.toLowerCase();
    final address =
        vmessConfig != null ? (vmessConfig['add']?.toString() ?? '') : uri.host;
    final port = vmessConfig != null
        ? int.tryParse(vmessConfig['port']?.toString() ?? '') ?? 0
        : uri.port;

    String getParam(String key, [String def = '']) {
      if (vmessConfig != null) {
        if (key == 'type' && vmessConfig.containsKey('net')) {
          final value = vmessConfig['net'];
          return value == null ? def : value.toString();
        }
        final value = vmessConfig[key];
        if (value != null) return value.toString();
      }
      // base64 в запросе: queryParameters превращает + в пробел, а панели + не кодируют. fm тоже json с base64
      if (key == 'ech' || key == 'pcs' || key == 'fm') {
        return _rawQueryParam(uri, key, def);
      }
      final val = uri.queryParametersAll[key];
      return (val != null && val.isNotEmpty) ? val.first : def;
    }

    final networkType = getParam('type', isHysteria ? 'hysteria' : 'tcp');

    final Map<String, dynamic> outbound;
    Map<String, dynamic> streamSettings = {'network': networkType};

    if (scheme == 'vless') {
      outbound = _buildVlessOutbound(uri, getParam, address, port, streamSettings);
    } else if (scheme == 'trojan') {
      outbound = _buildTrojanOutbound(uri, getParam, vmessConfig, address, port, streamSettings);
    } else if (scheme == 'ss') {
      outbound = _buildShadowsocksOutbound(uri, getParam, address, port);
    } else if (scheme == 'vmess') {
      outbound = _buildVmessOutbound(uri, vmessConfig, getParam, address, port, streamSettings);
    } else if (isHysteria) {
      outbound = _buildHysteriaOutbound(
          uri, trimmed, getParam, address, port, streamSettings);
    } else {
      throw ArgumentError('Unsupported protocol: $scheme');
    }

    _applyXrayStreamExtras(outbound, settings.xrayCore);
    _applyServerDomainStrategy(outbound, address, settings.xrayCore);

    return (outbound: outbound, address: address, port: port);
  }

  // оба числа больше нуля, иначе ядро молча возвращается к перебору по очереди (dialer.go)
  static Map<String, dynamic>? _happyEyeballs(XrayCoreSettings core) =>
      core.concurrentDial
          ? const <String, dynamic>{'tryDelayMs': 250, 'maxConcurrentTry': 4}
          : null;

  static void _applyHappyEyeballs(
    Map<String, dynamic> outbound,
    XrayCoreSettings core,
  ) {
    final happy = _happyEyeballs(core);
    if (happy == null) return;
    final stream = Map<String, dynamic>.from(
      (outbound['streamSettings'] as Map<String, dynamic>?) ??
          const <String, dynamic>{},
    );
    final sockopt = Map<String, dynamic>.from(
      (stream['sockopt'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
    );
    sockopt['happyEyeballs'] = happy;
    stream['sockopt'] = sockopt;
    outbound['streamSettings'] = stream;
  }

  static void _applyServerDomainStrategy(
    Map<String, dynamic> outbound,
    String address,
    XrayCoreSettings core,
  ) {
    if (address.isEmpty || _isIpLiteral(address)) return;
    final stream = Map<String, dynamic>.from(
      (outbound['streamSettings'] as Map<String, dynamic>?) ??
          const <String, dynamic>{},
    );
    final sockopt = Map<String, dynamic>.from(
      (stream['sockopt'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
    );
    sockopt['domainStrategy'] = switch (core.dnsQueryStrategy) {
      'UseIPv4' => 'UseIPv4',
      'UseIPv6' => 'UseIPv6',
      _ => 'UseIP',
    };
    final happy = _happyEyeballs(core);
    if (happy != null) sockopt['happyEyeballs'] = happy;
    stream['sockopt'] = sockopt;
    outbound['streamSettings'] = stream;
  }

  // выходной узел остаётся proxy: на этот тег смотрят все правила роутинга
  static const String _chainHopTagPrefix = 'chain-';

  static Map<String, dynamic> _buildChainConfig(
    ProxyChainConfig chain,
    AppSettings settings, {
    String? resolvedServerIp,
    int? pingSocksPort,
    bool pingHttpInbound = false,
    bool localInboundsNoAuth = false,
    bool nativeTunInbound = false,
    DesktopTunOptions? desktopTun,
    List<RouteServerOutbound> routeServers = const [],
    List<RouteAppRules> appRoutes = const [],
    OwnerGuard ownerGuard = OwnerGuard.off,
  }) {
    if (chain.hops.isEmpty) {
      throw ArgumentError('Proxy chain has no nodes');
    }

    final built = [
      for (final hop in chain.hops) _buildLinkOutbound(hop.config, settings),
    ];

    final outbounds = <Map<String, dynamic>>[];
    for (var i = 0; i < built.length; i++) {
      final isExit = i == built.length - 1;
      final outbound = built[i].outbound;
      outbound['tag'] = isExit ? 'proxy' : '$_chainHopTagPrefix$i';
      if (i > 0) {
        _applyDialerProxy(outbound, '$_chainHopTagPrefix${i - 1}');
      }
      outbounds.add(outbound);
    }

    // выходной узел первым: в xray первый аутбаунд основной, туда уходит всё без правила
    final exit = outbounds.removeLast();

    // mux только на выходном узле: на звеньях он мультиплексировал бы одно соединение
    _applyMux(exit, settings.xrayCore);

    return _wrapConfig(
      [exit, ...outbounds],
      settings,
      resolvedServerIp ?? built.first.address,
      built.first.port,
      originalServerAddress: built.first.address,
      // обход туннеля нужен адресам всех узлов, иначе обращение к промежуточному закольцуется через цепочку
      extraServerAddresses: [
        for (var i = 1; i < built.length; i++) built[i].address,
      ],
      pingSocksPort: pingSocksPort,
      pingHttpInbound: pingHttpInbound,
      localInboundsNoAuth: localInboundsNoAuth,
      nativeTunInbound: nativeTunInbound,
      desktopTun: desktopTun,
      routeServers: routeServers,
      appRoutes: appRoutes,
      ownerGuard: ownerGuard,
    );
  }

  static void _applyDialerProxy(Map<String, dynamic> outbound, String tag) {
    final stream = Map<String, dynamic>.from(
      (outbound['streamSettings'] as Map<String, dynamic>?) ??
          const <String, dynamic>{},
    );
    final sockopt = Map<String, dynamic>.from(
      (stream['sockopt'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
    );
    sockopt['dialerProxy'] = tag;
    // адрес узла резолвит предыдущее звено, а гонку адресов за dialerProxy ядро игнорирует
    sockopt.remove('domainStrategy');
    sockopt.remove('happyEyeballs');
    stream['sockopt'] = sockopt;

    // перебор портов только у внешнего узла: за dialerProxy он не проверен, базовый порт рабочий
    final finalmask = stream['finalmask'];
    if (finalmask is Map) {
      final quicParams = finalmask['quicParams'];
      if (quicParams is Map) {
        quicParams.remove('udpHop');
        if (quicParams.isEmpty) finalmask.remove('quicParams');
      }
      if (finalmask.isEmpty) stream.remove('finalmask');
    }

    outbound['streamSettings'] = stream;
  }

  static const String _fragmentTag = 'fragment';

  // только внешний аутбаунд, тот, что открывает сокет наружу: в цепочке у остальных свой dialerProxy,
  // вторая подмена порвала бы её. пакеты внутренних звеньев DPI и так не разберёт
  static Map<String, dynamic>? _applyFragment(
    List<Map<String, dynamic>> proxyOutbounds,
    XrayCoreSettings core,
  ) {
    final fragment = core.buildFragmentMap();
    if (fragment == null) return null;

    Map<String, dynamic>? fragmentOutbound;
    for (final outbound in proxyOutbounds) {
      final stream = outbound['streamSettings'] as Map<String, dynamic>?;
      final sockopt = stream?['sockopt'] as Map<String, dynamic>?;
      final dialer = sockopt?['dialerProxy']?.toString() ?? '';
      if (dialer.isNotEmpty) continue;
      if (_isDatagramOutbound(outbound)) continue;

      final newStream = Map<String, dynamic>.from(
        stream ?? const <String, dynamic>{},
      );
      final newSockopt = Map<String, dynamic>.from(
        sockopt ?? const <String, dynamic>{},
      );
      newSockopt['dialerProxy'] = _fragmentTag;
      newSockopt.remove('happyEyeballs');
      // domainStrategy тут остаётся: дозвон локальный, просто уходит на аутбаунд ниже
      newStream['sockopt'] = newSockopt;
      outbound['streamSettings'] = newStream;

      if (fragmentOutbound != null) continue;
      fragmentOutbound = <String, dynamic>{
        'protocol': 'freedom',
        'tag': _fragmentTag,
        'settings': {'fragment': fragment},
        // домен сервера через DNS-блок конфига: системного резолвера Go на Android нет (нет /etc/resolv.conf).
        // место sockopt, из настроек freedom ядро поле переносит сюда же
        'streamSettings': {
          'sockopt': {'domainStrategy': _freedomDomainStrategy(core)},
        },
      };
      // наружу звонит этот аутбаунд, поэтому гонка адресов здесь, иначе с фрагментацией её нет
      _applyHappyEyeballs(fragmentOutbound, core);
    }
    return fragmentOutbound;
  }

  // какие серверы попадают сюда, решает routeServerSupported до генерации
  static List<Map<String, dynamic>> _buildRouteServerOutbounds(
    List<RouteServerOutbound> servers,
    AppSettings settings,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final server in servers) {
      final custom = CustomXrayConfig.tryParse(server.config.trim());
      if (custom != null) {
        final outbounds = custom.routeOutbounds(server.tag);
        if (outbounds == null) {
          throw ArgumentError('Route server ${server.tag}: its dialerProxy '
              'points outside the config');
        }
        out.addAll(outbounds);
        continue;
      }
      final outbound = _buildLinkOutbound(server.config.trim(), settings).outbound;
      outbound['tag'] = server.tag;
      _applyMux(outbound, settings.xrayCore);
      out.add(outbound);
    }
    return out;
  }

  static ({List<String> domains, List<String> geoip, List<String> ips})
      _routeServerMatch(RouteServerOutbound server) =>
          _entriesMatch(server.entries, server.listDomains);

  static ({List<String> domains, List<String> geoip, List<String> ips})
      _entriesMatch(String entries, List<String> listDomains) {
    final split = splitDomainsAndIps(_parseRuleList(entries));
    final geo = splitGeoipTokens(split.ips);
    return (
      domains: [
        ..._normalizeDomains(split.domains),
        for (final d in listDomains) 'domain:$d',
      ],
      geoip: geo.geoipCodes,
      ips: geo.plainIps
          .where((e) => !e.trim().toLowerCase().startsWith('geoip:'))
          .toList(),
    );
  }

  static List<Map<String, dynamic>> _routeServerRules(
    List<RouteServerOutbound> servers,
    Map<String, dynamic> Function(String tag, Map<String, dynamic> fields) rule,
  ) =>
      [
        for (final server in servers)
          ...() {
            final match = _routeServerMatch(server);
            return [
              if (match.domains.isNotEmpty)
                rule('${server.tag}-domains', {
                  'domain': match.domains,
                  'outboundTag': server.tag,
                }),
              if (match.geoip.isNotEmpty)
                rule('${server.tag}-geoip', {
                  'ip': [for (final c in match.geoip) 'geoip:$c'],
                  'outboundTag': server.tag,
                }),
              if (match.ips.isNotEmpty)
                rule('${server.tag}-ips', {
                  'ip': match.ips,
                  'outboundTag': server.tag,
                }),
            ];
          }(),
      ];

  // процесс в правиле xray проверяет последним и только у совпавших по сайту,
  // поэтому владельца спрашивают не у каждого соединения
  static List<Map<String, dynamic>> _appRouteRules(
    List<RouteAppRules> routes,
    String Function(RouteAppRules route) target,
    Map<String, dynamic> Function(String tag, Map<String, dynamic> fields) rule,
  ) =>
      [
        for (final route in routes)
          ...() {
            Map<String, dynamic> fields([Map<String, dynamic> what = const {}]) => {
                  'inboundTag': [_tunInboundTag],
                  ...what,
                  'process': route.apps,
                  'outboundTag': target(route),
                };
            if (route.allTraffic) return [rule(route.tag, fields())];
            final match = _entriesMatch(route.entries, route.listDomains);
            return [
              if (match.domains.isNotEmpty)
                rule('${route.tag}-domains', fields({'domain': match.domains})),
              if (match.geoip.isNotEmpty)
                rule('${route.tag}-geoip', fields({
                  'ip': [for (final c in match.geoip) 'geoip:$c'],
                })),
              if (match.ips.isNotEmpty)
                rule('${route.tag}-ips', fields({'ip': match.ips})),
            ];
          }(),
      ];

  static String Function(RouteAppRules route) _appRouteTarget({
    required String proxyTag,
    required String directTag,
    required String blockTag,
  }) =>
      (route) => switch (route.target) {
            RouteTarget.block => blockTag,
            RouteTarget.direct => directTag,
            RouteTarget.vpn => proxyTag,
            RouteTarget.server =>
              route.serverTag.isEmpty ? proxyTag : route.serverTag,
          };

  // к самим серверам маршрутов мимо туннеля, как к активному, иначе круг
  static List<Map<String, dynamic>> _routeServerDirectRules(
    List<RouteServerOutbound> servers,
    String directTag,
    Map<String, dynamic> Function(String tag, Map<String, dynamic> fields) rule,
  ) =>
      [
        for (var i = 0; i < servers.length; i++)
          if (servers[i].address.trim().isNotEmpty)
            rule(
              'route-server-$i',
              _isIpLiteral(servers[i].address.trim())
                  ? {'ip': [servers[i].address.trim()], 'outboundTag': directTag}
                  : {
                      'domain': ['full:${servers[i].address.trim()}'],
                      'outboundTag': directTag,
                    },
            ),
      ];

  static String _freedomDomainStrategy(XrayCoreSettings core) =>
      switch (core.dnsQueryStrategy) {
        'UseIPv4' => 'UseIPv4',
        'UseIPv6' => 'UseIPv6',
        _ => 'UseIP',
      };

  // список udp ядро оборачивает с конца (slices.Backward), шум последним ближе всего к проводу
  static void _applyUdpNoise(
    List<Map<String, dynamic>> proxyOutbounds,
    XrayCoreSettings core,
  ) {
    final noise = core.buildNoiseItem();
    if (noise == null) return;

    for (final outbound in proxyOutbounds) {
      final stream = outbound['streamSettings'];
      if (stream is! Map<String, dynamic>) continue;
      final dialer = (stream['sockopt'] as Map<String, dynamic>?)?['dialerProxy']
              ?.toString() ??
          '';
      if (dialer.isNotEmpty) continue;
      if (!_isDatagramOutbound(outbound)) continue;

      final finalmask = Map<String, dynamic>.from(
        (stream['finalmask'] as Map<String, dynamic>?) ?? {},
      );
      final udp = [
        ...((finalmask['udp'] as List?) ?? const []),
        noise,
      ];
      finalmask['udp'] = udp;
      stream['finalmask'] = finalmask;
    }
  }

  static bool _isDatagramOutbound(Map<String, dynamic> outbound) {
    if (outbound['protocol'] == 'hysteria') return true;
    final network = (outbound['streamSettings']
                as Map<String, dynamic>?)?['network']
            ?.toString()
            .toLowerCase() ??
        '';
    return const {'hysteria', 'kcp', 'mkcp', 'quic'}.contains(network);
  }

  // и запятая, и перевод строки: UI обещает оба, а сплит по запятой склеивал строки в один токен
  static List<String> _parseRuleList(String s) => s
      .split(RegExp(r'[\r\n,]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty && !isRuleListUrl(e))
      .toList();

  // цена правила без условия на вход: для этого хоста правила пользователя в xray не действуют
  static Map<String, dynamic> _exitIpProbeFields(String outboundTag) => {
        'domain': ['full:$kExitIpProbeHost'],
        'outboundTag': outboundTag,
      };

  static List<String> _normalizeDomains(List<String> domains) =>
      domains.map((d) {
        final c = d.trim().toLowerCase();
        if (c.startsWith('domain:') ||
            c.startsWith('full:') ||
            c.startsWith('regexp:') ||
            c.startsWith('geosite:')) {
          return c;
        }
        if (!c.contains('.')) return 'regexp:.*\\.$c\$';
        if (c.startsWith('.')) return 'domain:${c.substring(1)}';
        return 'domain:$c';
      }).toList();

  static const _pingDirectTag = 'keq-ping-direct';

  static const _customDirectTag = 'keq-direct';

  static const _customBlockTag = 'keq-block';

  static const _customDnsTag = 'keq-dns-out';

  // xray включает UDP по маршрутам каждого адреса, увидев этот выход: tool/patches/xray-android-udp-per-exit.patch
  static const udpPerExitTag = 'keq-udp-per-exit';

  static Map<String, dynamic> _udpPerExitMark() => {'protocol': 'blackhole', 'tag': udpPerExitTag};

  // nonIPQuery ядро объявило к удалению, а удалённые поля роняют конфиг. без правил вышел бы пустой ответ вместо REFUSED
  static Map<String, dynamic> _dnsOutboundSettings() => {
        'rules': [
          {'action': 'hijack', 'qType': '1,28'},
          {'action': 'return', 'rCode': 5},
        ],
      };

  static bool _fakeDnsApplies(
    AppSettings settings, {
    required bool nativeTunInbound,
    required bool isPingMode,
  }) =>
      settings.fakeIp && nativeTunInbound && !isPingMode;

  static List<Map<String, dynamic>> _fakeDnsPool() => [
        {'ipPool': kFakeIpRange, 'poolSize': 65535},
      ];

  // без снифера подменный адрес так и уехал бы на сервер, поэтому тут он включён и при выключенном в настройках
  static Map<String, dynamic> _fakeDnsSniffing(XrayCoreSettings core) {
    final base = core.buildSniffing();
    if (base['enabled'] != true) {
      return {
        'enabled': true,
        'destOverride': ['fakedns'],
        'metadataOnly': true,
      };
    }
    return {
      ...base,
      'destOverride': [...(base['destOverride'] as List), 'fakedns'],
    };
  }

  // fakedns первым в общем переборе: всё, что разложено по domains, по-прежнему получает настоящий адрес.
  // исключениям своя запись с skipFallback, иначе она отвечала бы раньше подмены
  static Map<String, dynamic> _withFakeDns(Map<String, dynamic> dns) {
    final servers = [...((dns['servers'] as List?) ?? const [])];
    bool inFallback(Object? s) => s is String || (s is Map && s['skipFallback'] != true);
    final at = servers.indexWhere(inFallback);
    final general = at < 0 ? null : servers[at];
    return {
      ...dns,
      'servers': [
        ...servers.take(at < 0 ? servers.length : at),
        if (general != null)
          {
            ...(general is Map ? general.cast<String, dynamic>() : {'address': general}),
            'domains': fakeIpFilterAsRules(),
            'skipFallback': true,
          },
        {'address': 'fakedns'},
        if (at >= 0) ...servers.skip(at),
      ],
    };
  }

  static Map<String, dynamic> _buildCustomConfig(
    CustomXrayConfig custom,
    AppSettings settings, {
    String? resolvedServerIp,
    int? pingSocksPort,
    bool pingHttpInbound = false,
    bool localInboundsNoAuth = false,
    bool nativeTunInbound = false,
    DesktopTunOptions? desktopTun,
    GeoAssetIndex? geoIndex,
    List<RouteServerOutbound> routeServers = const [],
    List<RouteAppRules> appRoutes = const [],
    OwnerGuard ownerGuard = OwnerGuard.off,
  }) {
    final inbounds = _buildInbounds(
      settings,
      pingSocksPort: pingSocksPort,
      pingHttpInbound: pingHttpInbound,
      localInboundsNoAuth: localInboundsNoAuth,
      nativeTunInbound: nativeTunInbound,
      desktopTun: desktopTun,
    );

    if (pingSocksPort != null) {
      final serverAddress = resolvedServerIp?.trim().isNotEmpty == true
          ? resolvedServerIp!.trim()
          : custom.address;
      final config = custom.buildPingConfig(
        inbounds: inbounds,
        rules: _customPingRules(
          serverAddress: serverAddress,
          originalAddress: custom.address,
          proxyTag: custom.primaryOutboundTag,
        ),
      );
      config['outbounds'] = [
        ...(config['outbounds'] as List),
        {'protocol': 'freedom', 'tag': _pingDirectTag},
      ];
      return config;
    }

    final lanRules = <Map<String, dynamic>>[];
    var blockTag = _existingOutboundTag(custom, 'blackhole');
    if (settings.lanSharing || ownerGuard != OwnerGuard.off) {
      blockTag ??= _customBlockTag;
    }
    final outsideVpn = _outsideVpnRule(ownerGuard, blockTag ?? _customBlockTag);
    if (settings.lanSharing) {
      lanRules.addAll([
        {
          'type': 'field',
          'ruleTag': 'lan-allow',
          'inboundTag': ['socks-lan', 'http-lan'],
          'source': [
            '10.0.0.0/8',
            '172.16.0.0/12',
            '192.168.0.0/16',
            '169.254.0.0/16',
            '127.0.0.0/8',
          ],
          'outboundTag': custom.primaryOutboundTag,
        },
        {
          'type': 'field',
          'ruleTag': 'lan-deny',
          'inboundTag': ['socks-lan', 'http-lan'],
          'network': 'tcp,udp',
          'outboundTag': blockTag,
        },
      ]);
    }

    // наши списки после авторских правил: готовый конфиг берут ради его раскладки
    final directTag =
        _existingOutboundTag(custom, 'freedom') ?? _customDirectTag;
    final userRules = _customUserRules(
      settings,
      directTag: directTag,
      proxyTag: custom.primaryOutboundTag,
      blockTag: blockTag ?? _customBlockTag,
      routeServers: routeServers,
      appRoutes: nativeTunInbound ? appRoutes : const [],
    );

    // перехват DNS автора висел на его dns-in, который мы заменили, без этого правила DNS падает в final.
    // inboundTag обязателен: иначе dns-аутбаунд поймает запросы самого ядра и ответит сам себе по кругу
    final fallbackDns = settings.xrayCore.buildDnsBlock(
      directDomains: _normalizeDomains(
        splitDomainsAndIps(_parseRuleList(settings.directRules)).domains,
      ),
      bootstrapDomains: [
        if (custom.address.trim().isNotEmpty && !_isIpLiteral(custom.address))
          'full:${custom.address.trim()}',
      ],
      proxiedDoh: settings.finalOutbound == AppSettings.finalOutboundProxy,
    );
    final effectiveDns =
        CustomXrayConfig.mergeDns(custom.authorDns, fallbackDns) ?? fallbackDns;

    // с fakedns перехват всё ломает: домен из фейкового адреса достаёт только снифер с fakedns, а у нас его нет
    final usesFakeDns = custom.json.containsKey('fakedns') ||
        _dnsUsesFakeIp(effectiveDns);

    final dnsOutTag = _existingOutboundTag(custom, 'dns') ?? _customDnsTag;
    final inboundTags = <String>[
      for (final inbound in inbounds)
        if (inbound['tag'] is String) inbound['tag'] as String,
    ];
    final interceptDns = !usesFakeDns && inboundTags.isNotEmpty;
    final dnsRules = <Map<String, dynamic>>[
      if (interceptDns)
        {
          'type': 'field',
          'ruleTag': 'dns-out',
          'inboundTag': inboundTags,
          'port': '53',
          'network': 'tcp,udp',
          'outboundTag': dnsOutTag,
        },
    ];

    // раньше авторских правил: geoip:private -> direct забирал запрос на 172.19.0.2:53, а там никто не слушает
    final tunDnsRules = <Map<String, dynamic>>[
      if (interceptDns)
        {
          'type': 'field',
          'ruleTag': 'dns-out-tun',
          'inboundTag': inboundTags,
          'ip': ['$_androidTunDns/32'],
          'port': '53',
          'network': 'tcp,udp',
          'outboundTag': dnsOutTag,
        },
    ];

    // final в самый конец: авторский catch-all должен побеждать
    final finalTag = switch (settings.finalOutbound) {
      AppSettings.finalOutboundDirect => directTag,
      AppSettings.finalOutboundBlock => blockTag ?? _customBlockTag,
      _ => custom.primaryOutboundTag,
    };

    // запросы ядра к своему резолверу идут через роутинг, и с final=block ядро блокировало бы само себя
    final resolverNeedsRouting = _dnsGoesThroughRouting(effectiveDns);
    final resolverRules = <Map<String, dynamic>>[
      if ((resolverNeedsRouting || !interceptDns) &&
          settings.finalOutbound == AppSettings.finalOutboundBlock)
        {
          'type': 'field',
          'ruleTag': 'dns-resolver',
          'port': '53',
          'network': 'tcp,udp',
          'outboundTag': directTag,
        },
    ];

    // при авторском IPIfNonMatch ловушка любая сеть отменила бы его же правила по адресу для соединений по домену, см. _wrapConfig
    final authorRouting = custom.json['routing'];
    final resolvesForIpRules = authorRouting is Map &&
        authorRouting['domainStrategy'] == 'IPIfNonMatch';
    Map<String, dynamic> customRule(String tag, Map<String, dynamic> fields) =>
        {'type': 'field', 'ruleTag': tag, ...fields};
    final desktopHead = desktopTun == null
        ? const <Map<String, dynamic>>[]
        : _desktopTunHeadRules(
            desktopTun,
            dnsOutTag: interceptDns ? dnsOutTag : null,
            directTag: directTag,
            rule: customRule,
          );
    final appendRules = <Map<String, dynamic>>[
      ...dnsRules,
      ...userRules,
      // как у ссылок. у кого провайдер прислал своё правило на локалку, оно стоит раньше и решает само
      customRule('direct-private', {
        'ip': [...kBasePrivateRanges],
        'outboundTag': directTag,
      }),
      ...resolverRules,
      if (desktopTun != null)
        ..._desktopTunTailRules(
          desktopTun,
          directTag: directTag,
          blockTag: blockTag ?? _customBlockTag,
          rule: customRule,
        ),
      {
        'type': 'field',
        'ruleTag': 'final',
        if (resolvesForIpRules)
          'ip': ['0.0.0.0/0', '::/0']
        else
          'network': 'tcp,udp',
        'outboundTag': finalTag,
      },
    ];

    final usedTags = <String>{
      for (final rule in [...desktopHead, ...appendRules])
        rule['outboundTag'] as String,
      if (settings.lanSharing) blockTag ?? _customBlockTag,
      if (outsideVpn != null) outsideVpn['outboundTag'] as String,
      if (routeServers.any((r) => r.address.trim().isNotEmpty)) directTag,
    };

    final config = custom.buildSessionConfig(
      inbounds: inbounds,
      logLevel: settings.xrayCore.logLevel,
      // дефолт dns-аутбаунда localhost на Android не резолвит ничего
      dns: fallbackDns,
      // LAN-правила раньше авторских: иначе запрос снаружи уехал бы в туннель до запрета, и прокси стал бы открытым
      prependRules: [
        ...desktopHead,
        if (outsideVpn != null) customRule('outside-vpn', outsideVpn),
        ...lanRules,
        ...tunDnsRules,
        {
          'type': 'field',
          'ruleTag': 'exit-ip-probe',
          ..._exitIpProbeFields(custom.primaryOutboundTag),
        },
        ..._routeServerDirectRules(
          routeServers,
          directTag,
          (tag, fields) => {'type': 'field', 'ruleTag': tag, ...fields},
        ),
      ],
      appendRules: appendRules,
      geoIndex: geoIndex,
    );

    if (!usesFakeDns &&
        _fakeDnsApplies(
          settings,
          nativeTunInbound: nativeTunInbound,
          isPingMode: false,
        )) {
      final dns = config['dns'];
      if (dns is Map) {
        config['dns'] = _withFakeDns(dns.cast<String, dynamic>());
        config['fakedns'] = _fakeDnsPool();
      }
    }

    // только аутбаунды, на которые ссылаются правила: несуществующий тег роняет весь конфиг
    final extraOutbounds = <Map<String, dynamic>>[
      ..._buildRouteServerOutbounds(routeServers, settings),
      if (usedTags.contains(_customBlockTag))
        {'protocol': 'blackhole', 'tag': _customBlockTag},
      if (usedTags.contains(_customDirectTag))
        {'protocol': 'freedom', 'tag': _customDirectTag},
      if (usedTags.contains(_customDnsTag))
        {
          'protocol': 'dns',
          'tag': _customDnsTag,
          'settings': _dnsOutboundSettings(),
        },
      if (settings.xrayCore.udpPerAddress) _udpPerExitMark(),
    ];
    if (extraOutbounds.isNotEmpty) {
      config['outbounds'] = [
        ...(config['outbounds'] as List),
        ...extraOutbounds,
      ];
    }
    if (resolvesForIpRules && finalTag != custom.primaryOutboundTag) {
      final outbounds = [...config['outbounds'] as List];
      final index = outbounds.indexWhere((o) => o is Map && o['tag'] == finalTag);
      if (index > 0) outbounds.insert(0, outbounds.removeAt(index));
      config['outbounds'] = outbounds;
    }
    return config;
  }

  static bool _dnsUsesFakeIp(Map<String, dynamic> dns) {
    final servers = dns['servers'];
    if (servers is! List) return false;
    return servers.any((server) {
      final address = switch (server) {
        String s => s,
        Map m => m['address']?.toString() ?? '',
        _ => '',
      };
      return address.trim().toLowerCase() == 'fakedns';
    });
  }

  // localhost, fakedns и +local идут мимо роутинга, всё остальное через него
  static bool _dnsGoesThroughRouting(Map<String, dynamic> dns) {
    final servers = dns['servers'];
    if (servers is! List) return false;
    for (final server in servers) {
      final address = switch (server) {
        String s => s,
        Map m => m['address']?.toString() ?? '',
        _ => '',
      }
          .trim()
          .toLowerCase();
      if (address.isEmpty) continue;
      if (address == 'localhost' || address == 'fakedns') continue;
      final scheme = RegExp(r'^([a-z][a-z0-9.+-]*)://').firstMatch(address);
      if (scheme != null) {
        final name = scheme.group(1)!;
        if (name.endsWith('+local') || name == 'dhcp') continue;
      }
      return true;
    }
    return false;
  }

  // тот же порядок, что в _wrapConfig, иначе правило вело бы себя по-разному в зависимости от типа сервера
  static List<Map<String, dynamic>> _customUserRules(
    AppSettings settings, {
    required String directTag,
    required String proxyTag,
    required String blockTag,
    List<RouteServerOutbound> routeServers = const [],
    List<RouteAppRules> appRoutes = const [],
  }) {
    final rules = <Map<String, dynamic>>[];
    Map<String, dynamic> rule(String tag, Map<String, dynamic> fields) =>
        {'type': 'field', 'ruleTag': tag, ...fields};
    final appTarget = _appRouteTarget(
      proxyTag: proxyTag,
      directTag: directTag,
      blockTag: blockTag,
    );
    final appBlock = [
      for (final r in appRoutes)
        if (r.target == RouteTarget.block) r,
    ];
    final appOther = [
      for (final r in appRoutes)
        if (r.target != RouteTarget.block) r,
    ];

    void addGroup(String source, String outboundTag, String tagPrefix) {
      final split = splitDomainsAndIps(_parseRuleList(source));
      final geo = splitGeoipTokens(split.ips);
      final domains = _normalizeDomains(split.domains);
      final ips = geo.plainIps
          .where((e) => !e.trim().toLowerCase().startsWith('geoip:'))
          .toList();

      if (domains.isNotEmpty) {
        rules.add({
          'type': 'field',
          'ruleTag': '$tagPrefix-domains',
          'domain': domains,
          'outboundTag': outboundTag,
        });
      }
      if (geo.geoipCodes.isNotEmpty) {
        rules.add({
          'type': 'field',
          'ruleTag': '$tagPrefix-geoip',
          'ip': geo.geoipCodes.map((c) => 'geoip:$c').toList(),
          'outboundTag': outboundTag,
        });
      }
      if (ips.isNotEmpty) {
        rules.add({
          'type': 'field',
          'ruleTag': '$tagPrefix-ips',
          'ip': ips,
          'outboundTag': outboundTag,
        });
      }
    }

    addGroup(settings.blockedRules, blockTag, 'user-block');
    rules.addAll(_appRouteRules(appBlock, appTarget, rule));
    if (appOther.isNotEmpty) {
      rules.add(rule('app-private', {
        'ip': [...kBasePrivateRanges],
        'outboundTag': directTag,
      }));
      rules.addAll(_appRouteRules(appOther, appTarget, rule));
    }
    addGroup(settings.directRules, directTag, 'user-direct');
    rules.addAll(_routeServerRules(routeServers, rule));
    addGroup(settings.proxyRules, proxyTag, 'user-proxy');
    return rules;
  }

  static String? _existingOutboundTag(
    CustomXrayConfig custom,
    String protocol,
  ) {
    final outbounds = custom.json['outbounds'];
    if (outbounds is! List) return null;
    for (final item in outbounds) {
      if (item is! Map) continue;
      if (item['protocol']?.toString().toLowerCase() != protocol) continue;
      final tag = item['tag']?.toString().trim() ?? '';
      if (tag.isNotEmpty) return tag;
    }
    return null;
  }

  // иначе авторское правило могло увести пробу напрямую, и пинг мерил бы не сервер
  static List<Map<String, dynamic>> _customPingRules({
    required String serverAddress,
    required String originalAddress,
    required String proxyTag,
  }) {
    final rules = <Map<String, dynamic>>[];
    final isServerIp =
        serverAddress.isNotEmpty && _isIpLiteral(serverAddress);
    if (isServerIp) {
      rules.add({
        'type': 'field',
        'ip': [serverAddress],
        'outboundTag': _pingDirectTag,
      });
    }
    if (originalAddress.isNotEmpty) {
      if (!_isIpLiteral(originalAddress)) {
        rules.add({
          'type': 'field',
          'domain': ['full:$originalAddress'],
          'outboundTag': _pingDirectTag,
        });
      } else if (!isServerIp) {
        rules.add({
          'type': 'field',
          'ip': [originalAddress],
          'outboundTag': _pingDirectTag,
        });
      }
    }
    rules.add({
      'type': 'field',
      'ip': [
        '0.0.0.0/8', '10.0.0.0/8', '127.0.0.0/8', '172.16.0.0/12',
        '192.168.0.0/16', '::1/128', 'fc00::/7', 'fe80::/10',
      ],
      'outboundTag': _pingDirectTag,
    });
    rules.add({
      'type': 'field',
      'outboundTag': proxyTag,
      'network': 'tcp,udp',
    });
    return rules;
  }

  // extra у xray замещает весь блок XHTTP, от внешнего остаются host, path и mode
  static Map<String, dynamic>? _xhttpExtra(String raw, String paddingBytes) {
    Map<String, dynamic>? extra;
    final trimmed = raw.trim();
    if (trimmed.isNotEmpty) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          extra = Map<String, dynamic>.from(decoded);
        }
      } on FormatException {
        // битый extra: сервер без паддинга лучше, чем не добавившийся
      }
    }
    final padding = paddingBytes.trim();
    if (padding.isNotEmpty) {
      extra ??= <String, dynamic>{};
      extra.putIfAbsent('xPaddingBytes', () => padding);
    }
    final download = extra?['downloadSettings'];
    if (download is Map<String, dynamic>) _fillDownloadFingerprint(download);
    return (extra == null || extra.isEmpty) ? null : extra;
  }

  // у downloadSettings своё TLS-соединение, без отпечатка ядро представилось бы Chrome
  static void _fillDownloadFingerprint(Map<String, dynamic> download) {
    final key = switch (download['security']?.toString().toLowerCase()) {
      'tls' => 'tlsSettings',
      'reality' => 'realitySettings',
      _ => null,
    };
    if (key == null) return;
    final settings = download[key] is Map
        ? Map<String, dynamic>.from(download[key] as Map)
        : <String, dynamic>{};
    if ((settings['fingerprint']?.toString().trim() ?? '').isEmpty) {
      settings['fingerprint'] = defaultTlsFingerprint;
    }
    download[key] = settings;
  }

  // ed ядро читает только из пути (WebSocketConfig.Build), ссылки несут его и так, и так
  static String _pathWithEarlyData(String path, String ed) {
    final size = int.tryParse(ed.trim());
    if (size == null || size <= 0) return path;
    if (path.contains('ed=')) return path;
    return path.contains('?') ? '$path&ed=$size' : '$path?ed=$size';
  }

  // mux понимает общий обработчик сервера, поэтому vless, vmess и trojan. ss уедет к серверу,
  // который mux.cool не знает, а XHTTP мультиплексирует сам через xmux
  static void _applyMux(Map<String, dynamic> outbound, XrayCoreSettings core) {
    final mux = core.buildMuxMap();
    if (mux == null) return;
    const muxable = {'vless', 'vmess', 'trojan'};
    if (!muxable.contains(outbound['protocol']?.toString())) return;
    final stream = outbound['streamSettings'];
    final network =
        stream is Map<String, dynamic> ? stream['network']?.toString() : null;
    if (network == 'xhttp' || network == 'splithttp') return;

    // vision пускает в пачку только UDP, TCP внутри рвёт всё mux-соединение (common/mux/server.go)
    outbound['mux'] = _hasVisionFlow(outbound)
        ? {...mux, 'concurrency': -1}
        : mux;
  }

  static bool _hasVisionFlow(Map<String, dynamic> outbound) {
    final settings = outbound['settings'];
    if (settings is! Map) return false;
    return (settings['flow']?.toString().trim() ?? '')
        .startsWith('xtls-rprx-vision');
  }

  static void _applyXrayStreamExtras(
    Map<String, dynamic> outbound,
    XrayCoreSettings core,
  ) {
    final stream = outbound['streamSettings'];
    if (stream is! Map<String, dynamic>) return;
    final network = stream['network']?.toString() ?? '';
    if (network != 'xhttp' && network != 'splithttp') return;

    final xmux = core.buildXmuxMap();
    if (xmux == null) return;

    final xhttp = Map<String, dynamic>.from(
      (stream['xhttpSettings'] as Map<String, dynamic>?) ?? {},
    );
    final extra = Map<String, dynamic>.from(
      (xhttp['extra'] as Map<String, dynamic>?) ?? {},
    );
    extra['xmux'] = xmux;
    xhttp['extra'] = extra;
    stream['xhttpSettings'] = xhttp;
  }

  static Map<String, dynamic> _buildVlessOutbound(
      Uri uri, String Function(String, [String]) getParam, String address, int port, Map<String, dynamic> streamSettings) {
    final uuid = uri.userInfo;
    if (uuid.isEmpty) {
      throw ArgumentError('VLESS requires UUID in userInfo');
    }

    final flow = getParam('flow');
    final encryption = getParam('encryption', 'none').trim().isEmpty
        ? 'none'
        : getParam('encryption', 'none').trim();

    return {
      'tag': 'proxy',
      'protocol': 'vless',
      'settings': {
        'address': address,
        'port': port,
        'id': uuid,
        'encryption': encryption,
        if (flow.isNotEmpty) 'flow': flow,
        'level': 0,
      },
      'streamSettings': _buildStreamSettings(getParam, address, streamSettings),
    };
  }

  static Map<String, dynamic> _buildVmessOutbound(
      Uri uri, Map<String, dynamic>? vmessConfig, String Function(String, [String]) getParam,
      String address, int port, Map<String, dynamic> streamSettings) {
    final uuid = (vmessConfig?['id'] ?? uri.userInfo).toString();
    if (uuid.isEmpty) {
      throw ArgumentError('VMess requires id in payload');
    }

    // у AEAD-ссылки шифр в encryption, так его читает и mihomo
    final vmessSecurity = vmessConfig?['security']?.toString() ??
        vmessConfig?['scy']?.toString() ??
        (vmessConfig == null ? getParam('encryption', 'auto') : 'auto');
    final flow = vmessConfig?['flow']?.toString() ?? getParam('flow');

    return {
      'tag': 'proxy',
      'protocol': 'vmess',
      'settings': {
        'address': address,
        'port': port,
        'id': uuid,
        'security': vmessSecurity,
        'level': 0,
        if (flow.isNotEmpty) 'flow': flow,
      },
      'streamSettings': _buildStreamSettings(
        vmessConfig != null ? _vmessStreamParams(vmessConfig) : getParam,
        address,
        streamSettings,
      ),
    };
  }

  // type в json это заголовок маскировки, транспорт в net, security бывает шифром.
  // имя gRPC-сервиса и seed mKCP v2rayN кладёт в path
  static String Function(String, [String]) _vmessStreamParams(
      Map<String, dynamic>? cfg) {
    String raw(String key) {
      final value = cfg?[key];
      if (value == null) return '';
      // extra приезжает вложенным объектом, а дальше его ждёт jsonDecode
      return (value is Map || value is List)
          ? jsonEncode(value)
          : value.toString();
    }

    return (String key, [String def = '']) {
      final value = switch (key) {
        'type' => raw('net'),
        'headerType' => raw('type'),
        'security' => raw('tls').toLowerCase() == 'tls' ? 'tls' : '',
        'serviceName' => raw('path'),
        'seed' => const {'kcp', 'mkcp'}.contains(raw('net').toLowerCase())
            ? raw('path')
            : raw('seed'),
        _ => raw(key),
      };
      return value.isEmpty ? def : value;
    };
  }

  // пароль в ссылке закодирован (p%40ss), без декода в ядро уехал бы как есть
  static String _decodedUserInfo(Uri uri) {
    try {
      return Uri.decodeComponent(uri.userInfo);
    } catch (_) {
      return uri.userInfo;
    }
  }

  static Map<String, dynamic> _buildTrojanOutbound(
      Uri uri, String Function(String, [String]) getParam, Map<String, dynamic>? vmessConfig,
      String address, int port, Map<String, dynamic> streamSettings) {
    final password = vmessConfig != null
        ? (vmessConfig['id']?.toString() ?? '')
        : _decodedUserInfo(uri);
    if (password.isEmpty) {
      throw ArgumentError('Trojan requires password in userInfo');
    }

    final email = getParam('email');

    // trojan без TLS не бывает, а security=none ссылки пишут копипастой. слушаем только reality
    String stream(String key, [String def = '']) {
      if (key != 'security') return getParam(key, def);
      return getParam('security').trim().toLowerCase() == 'reality'
          ? 'reality'
          : 'tls';
    }

    _buildStreamSettings(
      stream,
      address,
      streamSettings,
      defaultSecurity: 'tls',
      sniFallback: address,
    );

    return {
      'tag': 'proxy',
      'protocol': 'trojan',
      'settings': {
        'address': address,
        'port': port,
        'password': password,
        if (email.isNotEmpty) 'email': email,
        'level': 0,
      },
      'streamSettings': streamSettings,
    };
  }

  static Map<String, dynamic> _buildShadowsocksOutbound(
      Uri uri, String Function(String, [String]) getParam, String address, int port) {
    // sip002: ss://base64(method:password@host:port) или ss://method:password@host:port
    // также бывает ss://base64(method:password)@host:port
    final withoutScheme = uri.toString().replaceFirst('ss://', '').trim();
    final hashIdx = withoutScheme.indexOf('#');
    final beforeHash = hashIdx >= 0 ? withoutScheme.substring(0, hashIdx) : withoutScheme;
    final atIdx = beforeHash.lastIndexOf('@');

    String method;
    String password;

    if (atIdx < 0) {
      throw ArgumentError('Shadowsocks requires userInfo with method:password');
    }

    final userInfo = beforeHash.substring(0, atIdx);

    if (userInfo.contains(':')) {
      final splitIdx = userInfo.indexOf(':');
      method = userInfo.substring(0, splitIdx);
      password = userInfo.substring(splitIdx + 1);
    } else {
      final decoded = _decodeBase64UrlCompat(userInfo);
      final splitIdx = decoded.indexOf(':');
      if (splitIdx <= 0 || splitIdx >= decoded.length - 1) {
        throw ArgumentError('Invalid Shadowsocks userInfo format');
      }
      method = decoded.substring(0, splitIdx);
      password = decoded.substring(splitIdx + 1);
    }

    final email = getParam('email');

    // uot и UoTVersion у shadowsocks в xray 26 нет, ядро их выбрасывало. UDP внутри TCP умеет только mihomo
    return {
      'tag': 'proxy',
      'protocol': 'shadowsocks',
      'settings': {
        'address': address,
        'port': port,
        'method': method,
        'password': password,
        if (email.isNotEmpty) 'email': email,
        'level': 0,
      },
      'streamSettings': {'network': 'tcp'},
    };
  }

  static Map<String, dynamic> _buildHysteriaOutbound(
      Uri uri,
      String rawLink,
      String Function(String, [String]) getParam,
      String address,
      int port,
      Map<String, dynamic> streamSettings,
  ) {
    var auth = getParam('auth', getParam('password', '')).trim();
    if (auth.isEmpty && uri.userInfo.isNotEmpty) {
      auth = _decodedUserInfo(uri).trim();
    }
    if (auth.isEmpty) {
      throw ArgumentError('Hysteria requires auth/password in URI (query or userInfo)');
    }

    final udpIdleTimeout = int.tryParse(getParam('udpIdleTimeout', '60')) ?? 60;

    Map<String, dynamic>? buildMasquerade() {
      final type = getParam('masqueradeType', getParam('masqType', ''));
      final dir = getParam('masqueradeDir', getParam('masqDir', ''));
      final url = getParam('masqueradeUrl', getParam('masqUrl', ''));
      final content = getParam('masqueradeContent', getParam('masqContent', ''));
      final statusCode = int.tryParse(getParam('masqueradeStatusCode', getParam('masqStatusCode', '')));

      if (type.isEmpty && dir.isEmpty && url.isEmpty && content.isEmpty && statusCode == null) {
        return null;
      }

      final map = <String, dynamic>{
        if (type.isNotEmpty) 'type': type,
        if (dir.isNotEmpty) 'dir': dir,
        if (url.isNotEmpty) 'url': url,
        if (content.isNotEmpty) 'content': content,
        'statusCode': ?statusCode,
      };
      return map;
    }

    // из исходной ссылки: список портов из адреса при разборе уже вынули
    final hyParams = HysteriaLinkParams.fromConfig(rawLink);
    final sni = getParam('sni', hyParams.sni.isNotEmpty ? hyParams.sni : address);
    // схема hysteria:// одна на обе версии, первая собиралась бы как вторая
    final version = int.tryParse(getParam('version', '2')) ?? 2;
    if (version != 2 || HysteriaLinkParams.isV1(uri.toString())) {
      throw ArgumentError(
        'Hysteria v1 is not supported. Use a hysteria2:// or hy2:// link.',
      );
    }

    final alpnRaw = getParam('alpn', hyParams.alpn);
    final alpnForTls = alpnRaw.isNotEmpty ? alpnRaw : 'h3';

    // в xray 26 нет отдельного quic, у hysteria свой network
    streamSettings['network'] = 'hysteria';
    streamSettings['security'] = 'tls';
    streamSettings['tlsSettings'] = _tlsClientSettings(
      serverName: sni,
      network: 'hysteria',
      fingerprint: getParam('fp', ''),
      alpnQuery: alpnForTls,
      echConfigList: getParam('ech'),
      pinnedPeerCertSha256: getParam('pinSHA256', hyParams.pinSha256),
    );

    streamSettings['hysteriaSettings'] = <String, dynamic>{
      'version': version,
      'auth': auth,
      'udpIdleTimeout': udpIdleTimeout,
      'masquerade': ?buildMasquerade(),
    };

    // полоса и перебор портов в xray 26 живут в finalmask.quicParams, из hysteriaSettings ядро их выбрасывает
    final quicParams = <String, dynamic>{};
    final up = HysteriaLinkParams.formatBandwidth(
      getParam('up', hyParams.up),
    );
    final down = HysteriaLinkParams.formatBandwidth(
      getParam('down', hyParams.down),
    );
    if (up != null) quicParams['brutalUp'] = up;
    if (down != null) quicParams['brutalDown'] = down;
    final mport = getParam('mport', hyParams.mport);
    if (mport.isNotEmpty) {
      quicParams['udpHop'] = <String, dynamic>{
        'ports': mport,
        'interval': ?_hopInterval(
          getParam('hop-interval', hyParams.hopInterval),
        ),
      };
    }

    final finalmask = hyParams.buildFinalmask() ?? <String, dynamic>{};
    if (quicParams.isNotEmpty) finalmask['quicParams'] = quicParams;
    if (finalmask.isNotEmpty) streamSettings['finalmask'] = finalmask;

    return {
      'tag': 'proxy',
      'protocol': 'hysteria',
      'settings': {
        'address': address,
        'port': port,
        'version': version,
      },
      'streamSettings': streamSettings,
    };
  }

  // меньше 5 с xray не принимает и роняет конфиг, mihomo поднимает до 5, делаем так же
  static String? _hopInterval(String raw) {
    final match = RegExp(r'^\s*(\d+)\s*(?:-\s*(\d+)\s*)?$').firstMatch(raw);
    if (match == null) return null;
    int? atLeast5(String? value) {
      final seconds = int.tryParse(value ?? '');
      if (seconds == null) return null;
      return seconds < 5 ? 5 : seconds;
    }

    final from = atLeast5(match.group(1));
    if (from == null) return null;
    final to = atLeast5(match.group(2)) ?? from;
    return to > from ? '$from-$to' : '$from';
  }

  // у trojan TLS подразумевается, а имя от адреса, а не от host, как и в mihomo-генераторе
  static Map<String, dynamic> _buildStreamSettings(
    String Function(String, [String]) getParam,
    String address,
    Map<String, dynamic> existing, {
    String defaultSecurity = 'none',
    String? sniFallback,
  }) {
    final type = getParam('type', 'tcp');
    final security = getParam('security', defaultSecurity);
    final sni = getParam('sni', sniFallback ?? getParam('host', address));

    final stream = existing;
    stream['network'] = type;
    stream['security'] = security;

    if (security == 'tls') {
      stream['tlsSettings'] = _tlsClientSettings(
        serverName: sni,
        network: type,
        fingerprint: getParam('fp', ''),
        alpnQuery: getParam('alpn'),
        echConfigList: getParam('ech'),
        pinnedPeerCertSha256: getParam('pcs'),
        verifyPeerCertByName: getParam('vcn'),
      );
    } else if (security == 'reality') {
      final rfp = getParam('fp', '').trim();
      stream['realitySettings'] = {
        'show': false,
        'fingerprint': rfp.isNotEmpty ? rfp : defaultTlsFingerprint,
        'serverName': sni,
        'publicKey': getParam('pbk'),
        'shortId': getParam('sid'),
        'spiderX': getParam('spx'),
        if (getParam('pqv').trim().isNotEmpty)
          'mldsa65Verify': getParam('pqv').trim(),
      };
    }

    // порядок масок xray перевернул между 26.3 и 26.7, две маски сервера на 26.3 прочтутся наоборот
    final finalmask = _finalmaskFromLink(getParam('fm'));
    if (finalmask != null) stream['finalmask'] = finalmask;

    switch (type) {
      case 'ws':
        // host полем: заголовок Host ядро объявило к удалению и само переносит его сюда
        stream['wsSettings'] = {
          'path': _pathWithEarlyData(getParam('path', '/'), getParam('ed')),
          'host': getParam('host', sni),
        };
      case 'grpc':
        // без authority ядро подставит адрес узла, и сервер за общим фронтом ответит 404
        final authority = getParam('authority');
        stream['grpcSettings'] = {
          'serviceName': getParam('serviceName'),
          'multiMode': getParam('mode') == 'multi',
          if (authority.isNotEmpty) 'authority': authority,
        };
      case 'xhttp': case 'splithttp':
        final host = getParam('host');
        stream['xhttpSettings'] = {
          'path': getParam('path', '/'),
          'host': host.isNotEmpty ? host : sni,
          if (getParam('mode').isNotEmpty) 'mode': getParam('mode'),
          'extra': ?_xhttpExtra(
            getParam('extra'),
            getParam('x_padding_bytes', getParam('xPaddingBytes')),
          ),
        };
      case 'httpupgrade':
        stream['httpupgradeSettings'] = {
          'path': _pathWithEarlyData(getParam('path', '/'), getParam('ed')),
          'host': getParam('host', sni),
        };
      case 'kcp' || 'mkcp':
        final kcp = <String, dynamic>{
          'mtu': ?_intInRange(getParam('mtu'), 21, 65535),
          'tti': ?_intInRange(getParam('tti'), 10, 1000),
        };
        if (kcp.isNotEmpty) stream['kcpSettings'] = kcp;
        if (finalmask == null) {
          final masks = _legacyKcpMasks(
            getParam('headerType'),
            getParam('seed'),
          );
          if (masks != null) stream['finalmask'] = {'udp': masks};
        }
      case 'tcp' || 'raw':
        if (getParam('headerType') == 'http') {
          // пустой список путей ядро поймёт как запрос без пути, а по умолчанию у него /
          final path = getParam('path');
          final method = getParam('method');
          stream['tcpSettings'] = {
            'header': {
              'type': 'http',
              'request': {
                if (method.isNotEmpty) 'method': method,
                if (path.isNotEmpty) 'path': [path],
                'headers': {'Host': [getParam('host', address)]},
              },
            },
          };
        }
    }
    return stream;
  }

  static Map<String, dynamic>? _finalmaskFromLink(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> && decoded.isNotEmpty
          ? decoded
          : null;
    } on FormatException {
      return null;
    }
  }

  // xray 26 снял headerType и seed из kcpSettings, прежний провод это маска mkcp-legacy.
  // заголовок последним, ближе к сети; сочетание проверено трафиком против xray 25.12.8
  static List<Map<String, dynamic>>? _legacyKcpMasks(
    String header,
    String seed,
  ) {
    var h = header.trim().toLowerCase();
    final s = seed.trim();
    if (h.isEmpty && s.isEmpty) return null;
    // у старых ядер этот заголовок звался wechat-video
    if (h == 'wechat-video') h = 'wechat';
    final withHeader = h.isNotEmpty && h != 'none';
    if (withHeader && !_mkcpHeaders.contains(h)) {
      throw ArgumentError('mKCP header "$header" is not known to the core');
    }
    return [
      {
        'type': 'mkcp-legacy',
        if (s.isNotEmpty) 'settings': {'value': s},
      },
      if (withHeader)
        {
          'type': 'mkcp-legacy',
          'settings': {'header': h},
        },
    ];
  }

  // с другими именами ядро роняет конфиг
  static const _mkcpHeaders = {
    'dns',
    'dtls',
    'srtp',
    'utp',
    'wechat',
    'wireguard',
  };

  // вне границ mtu и tti xray роняет весь конфиг
  static int? _intInRange(String raw, int min, int max) {
    final value = int.tryParse(raw.trim());
    return value != null && value >= min && value <= max ? value : null;
  }

  static Map<String, dynamic> _wrapConfig(
      List<Map<String, dynamic>> proxyOutbounds, AppSettings settings, String serverAddress, int serverPort,
      {String? originalServerAddress, List<String> extraServerAddresses = const [], int? pingSocksPort, bool pingHttpInbound = false, bool localInboundsNoAuth = false, bool nativeTunInbound = false, DesktopTunOptions? desktopTun, List<RouteServerOutbound> routeServers = const [], List<RouteAppRules> appRoutes = const [], OwnerGuard ownerGuard = OwnerGuard.off}) {

    originalServerAddress ??= serverAddress;
    final isPingMode = pingSocksPort != null;
    // пинг меряет один сервер, маршрутам там места нет
    final routes = isPingMode ? const <RouteServerOutbound>[] : routeServers;
    final apps = isPingMode || !nativeTunInbound
        ? const <RouteAppRules>[]
        : appRoutes;
    final appBlock = [
      for (final r in apps)
        if (r.target == RouteTarget.block) r,
    ];
    final appOther = [
      for (final r in apps)
        if (r.target != RouteTarget.block) r,
    ];
    final appTarget = _appRouteTarget(
      proxyTag: 'proxy',
      directTag: 'direct',
      blockTag: 'block',
    );
    final routeOutbounds = _buildRouteServerOutbounds(routes, settings);

    final directSplit  = splitDomainsAndIps(_parseRuleList(settings.directRules));
    final proxySplit   = splitDomainsAndIps(_parseRuleList(settings.proxyRules));
    final blockedSplit = splitDomainsAndIps(_parseRuleList(settings.blockedRules));

    final directGeo    = splitGeoipTokens(directSplit.ips);
    final proxyGeo     = splitGeoipTokens(proxySplit.ips);
    final blockedGeo   = splitGeoipTokens(blockedSplit.ips);

    final directDomains  = _normalizeDomains(directSplit.domains);
    final blockedDomains = _normalizeDomains(blockedSplit.domains);
    final proxyDomains   = _normalizeDomains(proxySplit.domains);
    final directIps      = directGeo.plainIps
        .where((e) => !e.trim().toLowerCase().startsWith('geoip:'))
        .toList();
    final proxyIps       = proxyGeo.plainIps
        .where((e) => !e.trim().toLowerCase().startsWith('geoip:'))
        .toList();
    final blockedIps     = blockedGeo.plainIps
        .where((e) => !e.trim().toLowerCase().startsWith('geoip:'))
        .toList();
    final directGeoip    = directGeo.geoipCodes;
    final proxyGeoip     = proxyGeo.geoipCodes;
    final blockedGeoip   = blockedGeo.geoipCodes;

    // приватные диапазоны не считаем пользовательскими IP-правилами, иначе стратегию поднимало бы всегда
    final extraDirectIps = directIps
        .where((ip) => !kBasePrivateRanges.contains(ip.trim()))
        .toList();

    final core = settings.xrayCore;

    // с AsIs xray не резолвит домен из CONNECT, и пользовательское IP-правило (корп. 10.x в Direct) молчит.
    // IPIfNonMatch только при своих IP-правилах: проксируемые домены без них не резолвим, так приватнее
    final hasUserIpRules = extraDirectIps.isNotEmpty ||
        proxyIps.isNotEmpty ||
        blockedIps.isNotEmpty ||
        routes.any((r) => _routeServerMatch(r).ips.isNotEmpty) ||
        apps.any((r) => _entriesMatch(r.entries, const []).ips.isNotEmpty);
    final effectiveDomainStrategy =
        (!isPingMode && hasUserIpRules && core.routingDomainStrategy == 'AsIs')
            ? 'IPIfNonMatch'
            : core.routingDomainStrategy;
    final bootstrapDomains = <String>[
      for (final addr in [
        originalServerAddress,
        ...extraServerAddresses,
        for (final r in routes) r.address,
      ])
        if (addr.trim().isNotEmpty && !_isIpLiteral(addr)) 'full:${addr.trim()}',
    ];

    final globalProxy = settings.finalOutbound == AppSettings.finalOutboundProxy;

    final dns = isPingMode
        ? {
            // тот же DoH, что в боевом конфиге: UDP-53 к 8.8.8.8 у части провайдеров подменяют, и пинг краснел бы на живом
            'servers': [
              'https+local://1.1.1.1/dns-query',
              'https+local://8.8.8.8/dns-query',
              'localhost',
            ],
            'queryStrategy': 'UseIPv4',
          }
        : core.buildDnsBlock(
            directDomains: directDomains,
            bootstrapDomains: bootstrapDomains,
            proxiedDoh: globalProxy,
          );

    // ruleTag печатается в логе на Info, по нему экран Соединения показывает правило
    final rules = <Map<String, dynamic>>[];
    Map<String, dynamic> rule(
      String tag,
      Map<String, dynamic> fields,
    ) => {
          'type': 'field',
          ...fields,
          if (!isPingMode) 'ruleTag': tag,
        };

    if (desktopTun != null) {
      rules.addAll(_desktopTunHeadRules(
        desktopTun,
        dnsOutTag: 'dns-out',
        directTag: 'direct',
        rule: rule,
      ));
    }

    final outsideVpn = _outsideVpnRule(ownerGuard, 'block');
    if (outsideVpn != null) rules.add(rule('outside-vpn', outsideVpn));

    rules.add(rule('block-special', {
      'ip': ['169.254.0.0/16', '224.0.0.0/4', '255.255.255.255/32'],
      'outboundTag': 'block',
    }));

    void addChainHopDirectRules() {
      for (var i = 0; i < extraServerAddresses.length; i++) {
        final addr = extraServerAddresses[i].trim();
        if (addr.isEmpty) continue;
        rules.add(rule(
          'chain-hop-$i',
          _isIpLiteral(addr)
              ? {'ip': [addr], 'outboundTag': 'direct'}
              : {'domain': ['full:$addr'], 'outboundTag': 'direct'},
        ));
      }
    }

    if (isPingMode) {
      final isServerIp = _isIpLiteral(serverAddress);
      if (isServerIp) {
        rules.add({'type': 'field', 'ip': [serverAddress], 'outboundTag': 'direct'});
      }
      if (!_isIpLiteral(originalServerAddress)) {
        rules.add({'type': 'field', 'domain': ['full:$originalServerAddress'], 'outboundTag': 'direct'});
      } else if (!isServerIp) {
        rules.add({'type': 'field', 'ip': [originalServerAddress], 'outboundTag': 'direct'});
      }
      addChainHopDirectRules();
      rules.add({
        'type': 'field',
        'ip': [
          '0.0.0.0/8', '10.0.0.0/8', '127.0.0.0/8', '172.16.0.0/12',
          '192.168.0.0/16', '::1/128', 'fc00::/7', 'fe80::/10',
        ],
        'outboundTag': 'direct',
      });
    } else {
    if (!isPingMode && settings.lanSharing) {
      rules.add(rule('lan-allow', {
        'inboundTag': ['socks-lan', 'http-lan'],
        'source': [
          '10.0.0.0/8',
          '172.16.0.0/12',
          '192.168.0.0/16',
          '169.254.0.0/16',
          '127.0.0.0/8',
        ],
        'outboundTag': 'proxy',
      }));
      rules.add(rule('lan-deny', {
        'inboundTag': ['socks-lan', 'http-lan'],
        'network': 'tcp,udp',
        'outboundTag': 'block',
      }));
    }
    // DNS устройства отвечает ядро: иначе каждый запрос шёл отдельным TCP до сервера, и пачка с Android
    // выбивала лимит новых соединений. после lan-правил, иначе вышел бы открытый резолвер наружу
    rules.add(rule('dns-out', {
      'port': '53',
      'network': 'tcp,udp',
      'outboundTag': 'dns-out',
    }));
    rules.add(rule('exit-ip-probe', _exitIpProbeFields('proxy')));
    if (blockedDomains.isNotEmpty) {
      rules.add(rule('block-domains',
          {'domain': blockedDomains, 'outboundTag': 'block'}));
    }
    if (blockedGeoip.isNotEmpty) {
      // отдельного поля geoip у xray нет: голый ключ выбрасывается, и ядро падает на this rule has no effective fields
      rules.add(rule('block-geoip', {
        'ip': blockedGeoip.map((c) => 'geoip:$c').toList(),
        'outboundTag': 'block',
      }));
    }
    if (blockedIps.isNotEmpty) {
      rules.add(rule('block-ips', {'ip': blockedIps, 'outboundTag': 'block'}));
    }
    rules.addAll(_appRouteRules(appBlock, appTarget, rule));
    final isServerIp = _isIpLiteral(serverAddress);
    if (isServerIp) {
      rules.add(rule('server-ip',
          {'ip': [serverAddress], 'outboundTag': 'direct'}));
    }
    if (!_isIpLiteral(originalServerAddress)) {
      rules.add(rule('server-domain', {
        'domain': ['full:$originalServerAddress'],
        'outboundTag': 'direct',
      }));
    } else if (!isServerIp) {
      rules.add(rule('server-address',
          {'ip': [originalServerAddress], 'outboundTag': 'direct'}));
    }
    addChainHopDirectRules();
    rules.addAll(_routeServerDirectRules(routes, 'direct', rule));
    // весь трафик на сервер не должен увозить туда роутер и принтер
    if (appOther.isNotEmpty) {
      rules.add(rule('app-private', {
        'ip': [...kBasePrivateRanges],
        'outboundTag': 'direct',
      }));
      rules.addAll(_appRouteRules(appOther, appTarget, rule));
    }
    if (directDomains.isNotEmpty) {
      rules.add(rule('direct-domains',
          {'domain': directDomains, 'outboundTag': 'direct'}));
    }
    if (directGeoip.isNotEmpty) {
      rules.add(rule('direct-geoip', {
        'ip': directGeoip.map((c) => 'geoip:$c').toList(),
        'outboundTag': 'direct',
      }));
    }
    rules.add(rule('direct-private', {
      'ip': [
        ...extraDirectIps,
        ...kBasePrivateRanges,
      ],
      'outboundTag': 'direct',
    }));
    // между обходом и через VPN, как в разделе всех приложений (routesIn)
    rules.addAll(_routeServerRules(routes, rule));
    // vision отвергает UDP/443 только после полного TCP+TLS до сервера, и каждый QUIC-ретрай стоил рукопожатия.
    // только при глобал-прокси, вариант -udp443 не трогаем
    if (settings.finalOutbound == AppSettings.finalOutboundProxy &&
        _visionRejectsQuic(proxyOutbounds)) {
      rules.add(rule('block-quic', {
        'network': 'udp',
        'port': '443',
        'outboundTag': 'block',
      }));
    }
    if (proxyDomains.isNotEmpty) {
      rules.add(rule('proxy-domains',
          {'domain': proxyDomains, 'outboundTag': 'proxy'}));
    }
    if (proxyGeoip.isNotEmpty) {
      rules.add(rule('proxy-geoip', {
        'ip': proxyGeoip.map((c) => 'geoip:$c').toList(),
        'outboundTag': 'proxy',
      }));
    }
    if (proxyIps.isNotEmpty) {
      rules.add(rule('proxy-ips', {'ip': proxyIps, 'outboundTag': 'proxy'}));
    }
    }

    final finalTag = isPingMode
        ? 'proxy'
        : switch (settings.finalOutbound) {
            AppSettings.finalOutboundDirect => 'direct',
            AppSettings.finalOutboundBlock => 'block',
            _ => 'proxy',
          };
    // второй проход с резолвом для правил по адресу xray делает, только если в первом не совпало ничего (pickRouteInternal),
    // и ловушка любая сеть его отменяла. домен, который не отрезолвился, уходит в первый выход
    final resolvesForIpRules =
        !isPingMode && effectiveDomainStrategy == 'IPIfNonMatch';
    if (desktopTun != null) {
      rules.addAll(_desktopTunTailRules(
        desktopTun,
        directTag: 'direct',
        blockTag: 'block',
        rule: rule,
      ));
    }
    rules.add(rule(
      'final',
      resolvesForIpRules
          ? {'ip': ['0.0.0.0/0', '::/0'], 'outboundTag': finalTag}
          : {'outboundTag': finalTag, 'network': 'tcp,udp'},
    ));

    // и в пробе: она обязана дозваниваться так же, как потом боевое соединение
    final fragmentOutbound =
        _applyFragment([...proxyOutbounds, ...routeOutbounds], core);

    _applyUdpNoise([...proxyOutbounds, ...routeOutbounds], core);

    final inbounds = _buildInbounds(
      settings,
      pingSocksPort: pingSocksPort,
      pingHttpInbound: pingHttpInbound,
      localInboundsNoAuth: localInboundsNoAuth,
      nativeTunInbound: nativeTunInbound,
      desktopTun: desktopTun,
    );
    final fakeDns = _fakeDnsApplies(
      settings,
      nativeTunInbound: nativeTunInbound,
      isPingMode: isPingMode,
    );

    final outbounds = <Map<String, dynamic>>[
        ...proxyOutbounds,
        ...routeOutbounds,
        {
          'protocol': 'freedom',
          'tag': 'direct',
          if (core.concurrentDial)
            'streamSettings': {
              'sockopt': {'happyEyeballs': _happyEyeballs(core)},
            },
        },
        {'protocol': 'blackhole', 'tag': 'block'},
        // не раньше прокси-аутбаунда: первый у xray основной
        ?fragmentOutbound,
        if (!isPingMode)
          {
            'protocol': 'dns',
            'tag': 'dns-out',
            'settings': _dnsOutboundSettings(),
          },
        if (!isPingMode && core.udpPerAddress) _udpPerExitMark(),
    ];
    if (resolvesForIpRules && finalTag != 'proxy') {
      final index = outbounds.indexWhere((o) => o['tag'] == finalTag);
      outbounds.insert(0, outbounds.removeAt(index));
    }

    return {
      'log': {'loglevel': isPingMode ? 'none' : core.logLevel},
      'dns': fakeDns ? _withFakeDns(dns) : dns,
      if (fakeDns) 'fakedns': _fakeDnsPool(),
      'inbounds': inbounds,
      'outbounds': outbounds,
      'routing': {
        'domainStrategy': isPingMode ? 'AsIs' : effectiveDomainStrategy,
        'rules': rules,
      },
    };
  }

  static bool _visionRejectsQuic(List<Map<String, dynamic>> proxyOutbounds) {
    if (proxyOutbounds.isEmpty) return false;
    final first = proxyOutbounds.first;
    if (first['protocol'] != 'vless') return false;
    final settings = first['settings'];
    if (settings is! Map) return false;
    final flow = settings['flow']?.toString().trim() ?? '';
    return flow.startsWith('xtls-rprx-vision') && !flow.endsWith('-udp443');
  }

  // маршрут xray на Linux кладёт в main с метрикой 1, и default с метрикой 0 его перебивал бы: половинки /1 точнее
  static Map<String, dynamic> _desktopTunSettings(DesktopTunOptions tun) {
    final v6 = tun.captureIpv6;
    return {
      'name': kTunInterfaceName,
      'mtu': tun.mtu,
      'gateway': [kTunInterfacePrefix, if (v6) kTunInterfaceIpv6Prefix],
      if (tun.windows) 'dns': [kTunDnsAddress],
      if (tun.autoRoute)
        'autoSystemRoutingTable': tun.windows
            ? ['0.0.0.0/0', if (v6) '::/0']
            : [
                '0.0.0.0/1',
                '128.0.0.0/1',
                if (v6) ...['::/1', '8000::/1'],
                ...tun.systemResolvers,
              ],
      'autoOutboundsInterface': 'auto',
      // как strict_route у sing-box на Windows: DNS и семейство без маршрута в TUN мимо него не выходят
      if (tun.windows && tun.strictRoute && tun.autoRoute)
        'autoSystemWfpBlockLeak': ['dns', 'misconfigtun'],
    };
  }

  // впереди всего, как решал sing-box до xray: сначала DNS любой программы в перехват, потом кому туннель вообще не положен
  static List<Map<String, dynamic>> _desktopTunHeadRules(
    DesktopTunOptions tun, {
    required String? dnsOutTag,
    required String directTag,
    required Map<String, dynamic> Function(String tag, Map<String, dynamic> fields) rule,
  }) {
    Map<String, dynamic> fromTun(String tag, Map<String, dynamic> fields) =>
        rule(tag, {
          'inboundTag': [_tunInboundTag],
          ...fields,
        });
    final app = tun.appProcessName.trim();
    final selected = [
      for (final name in tun.managedProcessNames)
        if (name.trim().isNotEmpty) name.trim(),
    ];
    return [
      if (dnsOutTag != null)
        fromTun('tun-dns', {
          'port': '53',
          'network': 'tcp,udp',
          'outboundTag': dnsOutTag,
        }),
      // временное ядро замера отдельным процессом: туннель забирал его соединение, и пинг мерил локальный конец
      fromTun('tun-own', {
        'process': [if (app.isNotEmpty) app, 'xray', 'mihomo'],
        'outboundTag': directTag,
      }),
      if (tun.routingMode == AppRoutingMode.allProxy)
        fromTun('tun-other-vpn', {
          'process': [
            'tailscaled',
            'wireguard',
            'openvpn',
            if (tun.windows) 'openvpn-gui',
          ],
          'outboundTag': directTag,
        }),
      // !имя это патч tool/patches/xray-desktop-process.patch: невыбранные мимо туннеля целиком, как на Android
      if (selected.isNotEmpty)
        ?switch (tun.routingMode) {
          AppRoutingMode.onlySelected => fromTun('tun-unselected', {
              'process': [for (final name in selected) '!$name'],
              'outboundTag': directTag,
            }),
          AppRoutingMode.allExceptSelected => fromTun('tun-excluded', {
              'process': selected,
              'outboundTag': directTag,
            }),
          AppRoutingMode.allProxy => null,
        },
    ];
  }

  static List<Map<String, dynamic>> _desktopTunTailRules(
    DesktopTunOptions tun, {
    required String directTag,
    required String blockTag,
    required Map<String, dynamic> Function(String tag, Map<String, dynamic> fields) rule,
  }) {
    final unnamedSelection = tun.routingMode == AppRoutingMode.onlySelected &&
        tun.managedProcessNames.every((name) => name.trim().isEmpty);
    return [
      // закрываем, а не проксируем: закрытый выход Happy Eyeballs откатывает на IPv4 за миллисекунды
      if (tun.captureIpv6)
        rule('tun-ipv6', {
          'inboundTag': [_tunInboundTag],
          'ip': ['::/0'],
          'outboundTag': blockTag,
        }),
      // только выбранные без единого имени: всё без правила напрямую, как у mihomo
      if (unnamedSelection)
        rule('tun-unselected', {
          'inboundTag': [_tunInboundTag],
          'network': 'tcp,udp',
          'outboundTag': directTag,
        }),
    ];
  }

  // UDP из TUN идёт уровнем 1, tool/patches/xray-desktop-tun-udp-level.patch. уровень с одним connIdle
  // обнулил бы остальные таймауты (ToCorePolicy), поэтому все четыре, прочие как в SessionDefault
  static void _applyDesktopTunPolicy(
    Map<String, dynamic> config,
    DesktopTunOptions tun,
  ) {
    if (tun.udpTimeoutSec == TunSettings.defaultUdpTimeoutSec) return;
    final policy = {...?(config['policy'] as Map?)?.cast<String, dynamic>()};
    final levels = {...?(policy['levels'] as Map?)?.cast<String, dynamic>()};
    levels['1'] = {
      'handshake': 60,
      'connIdle': tun.udpTimeoutSec,
      'uplinkOnly': 1,
      'downlinkOnly': 1,
    };
    policy['levels'] = levels;
    config['policy'] = policy;
  }

  static const _tunInboundTag = 'tun-in';

  // первым правилом: и DNS-перехват, и exit-ip-probe ответили бы приложению вне VPN через сервер
  static Map<String, dynamic>? _outsideVpnRule(
    OwnerGuard guard,
    String blockTag,
  ) {
    if (guard == OwnerGuard.off) return null;
    return {
      'inboundTag': [_tunInboundTag],
      'process': [kOutsideVpnOwner],
      'outboundTag': blockTag,
    };
  }

  static const appInboundTags = [
    'socks-in',
    'http-in',
    'socks-lan',
    'http-lan',
    'tun-in',
  ];

  // у готового конфига авторские инбаунды заменяются этими: их порты и креды ждёт нативная часть
  static List<Map<String, dynamic>> _buildInbounds(
    AppSettings settings, {
    int? pingSocksPort,
    bool pingHttpInbound = false,
    bool localInboundsNoAuth = false,
    bool nativeTunInbound = false,
    DesktopTunOptions? desktopTun,
  }) {
    final core = settings.xrayCore;
    final isPingMode = pingSocksPort != null;
    final socksPort = pingSocksPort ?? settings.localPort;
    final useNoAuthInbound = isPingMode || localInboundsNoAuth;
    return <Map<String, dynamic>>[
      // дескриптор ядро берёт из XRAY_TUN_FD, mtu обязан совпасть с интерфейсом. port ядро не спрашивает,
      // но без ключа падает на Listen on AnyIP but no Port(s) set. без снифера доменные правила не работают
      if (nativeTunInbound && !isPingMode)
        {
          'tag': 'tun-in',
          'port': 0,
          'protocol': 'tun',
          'settings': desktopTun == null
              ? {'name': _tunInterfaceName, 'mtu': _defaultTunMtu}
              : _desktopTunSettings(desktopTun),
          'sniffing': _fakeDnsApplies(
            settings,
            nativeTunInbound: nativeTunInbound,
            isPingMode: isPingMode,
          )
              ? _fakeDnsSniffing(core)
              : core.buildSniffing(),
        },
      if (isPingMode && pingHttpInbound)
        // на десктопе HTTP: проба на dart:io, а HttpClient умеет только PROXY. на Android Java-проба ходит по SOCKS
        {
          'tag': 'http-in',
          'port': socksPort,
          'listen': '127.0.0.1',
          'protocol': 'http',
          'settings': {'allowTransparent': false},
        }
      else if (isPingMode)
        {
          'tag': 'socks-in',
          'port': socksPort,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'settings': {'auth': 'noauth', 'udp': true},
        }
      else ...[
      {
        'tag': 'socks-in',
        'port': socksPort,
        'listen': '127.0.0.1',
        'protocol': 'socks',
        'settings': useNoAuthInbound
            ? {'auth': 'noauth', 'udp': true}
            : {
                'auth': 'password',
                'udp': true,
                'accounts': [
                  {
                    'user': Socks5Credentials().username,
                    'pass': Socks5Credentials().password,
                  }
                ],
              },
        'sniffing': core.buildSniffing(),
      },
      {
        'tag': 'http-in',
        'port': settings.httpPort,
        'listen': '127.0.0.1',
        'protocol': 'http',
        'settings': useNoAuthInbound
            ? {'allowTransparent': false}
            : {
                'allowTransparent': false,
                'accounts': [
                  {
                    'user': Socks5Credentials().username,
                    'pass': Socks5Credentials().password,
                  }
                ],
              },
      },
      if (settings.lanSharing) ...[
        {
          'tag': 'socks-lan',
          'port': settings.lanSocksPort,
          'listen': '0.0.0.0',
          'protocol': 'socks',
          'settings': _lanAuthEnabled(settings)
              ? {
                  'auth': 'password',
                  'udp': true,
                  'accounts': [
                    {
                      'user': settings.lanUsername.trim(),
                      'pass': settings.lanPassword,
                    }
                  ],
                }
              : {
                  'auth': 'noauth',
                  'udp': true,
                },
          'sniffing': core.buildSniffing(),
        },
        {
          'tag': 'http-lan',
          'port': settings.lanHttpPort,
          'listen': '0.0.0.0',
          'protocol': 'http',
          'settings': _lanAuthEnabled(settings)
              ? {
                  'allowTransparent': false,
                  'accounts': [
                    {
                      'user': settings.lanUsername.trim(),
                      'pass': settings.lanPassword,
                    }
                  ],
                }
              : {'allowTransparent': false},
        },
      ],
      ],
    ];
  }
}
