import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';
import '../models/traffic_route.dart';
import '../models/xray_core_settings.dart';
import '../tunnel/app_routing_mode.dart';
import 'app_routes.dart';
import 'awg_profile.dart';
import 'custom_clash_config.dart';
import 'exit_ip_probe.dart';
import 'fake_ip.dart';
import 'geo_asset_index.dart';
import 'hysteria_uri.dart';
import 'mieru_uri.dart';
import 'owner_guard.dart';
import 'process_name_utils.dart';
import 'proxy_chain.dart';
import 'route_servers.dart';
import 'routing_entry.dart';
import 'rule_lists.dart';
import 'socks5_credentials.dart';
import 'socks_uri.dart';
import 'ssr_uri.dart';
import 'tls_fingerprint.dart';

class MihomoTunOptions {
  const MihomoTunOptions({
    this.device,
    required this.stack,
    this.mtu = 0,
    this.autoRoute = true,
    this.strictRoute = false,
    this.fromFileDescriptor = false,
  });

  // file-descriptor и mtu в готовый конфиг дописывает нативный сервис, это его числа
  final bool fromFileDescriptor;

  // без имени mihomo берёт Meta, а wintun считает GUID адаптера от имени, и соседний клиент забирает наш адаптер
  final String? device;

  final String stack;

  final int mtu;

  // на Android маршруты ставит VpnService, ядро без root получит отказ
  final bool autoRoute;

  final bool strictRoute;

  bool get autoDetectInterface => autoRoute;
}

// udp: true у прокси всегда: без флага mihomo молча отбрасывает и UDP ASSOCIATE, и UDP-сессии.
// JSON вместо YAML: YAML 1.2 его надмножество, файл всё равно .yaml
class MihomoConfigGen {
  static const proxyName = 'proxy';


  static const lanSocksListener = 'keq-lan-socks';
  static const lanHttpListener = 'keq-lan-http';
  static const lanRuleSet = 'keq-lan';

  static String generate(
    String input,
    AppSettings settings, {
    required int socksPort,
    int? httpPort,
    String? resolvedServerIp,
    bool localInboundsNoAuth = false,
    int? apiPort,
    String apiSecret = '',
    MihomoTunOptions? tun,
    AppRoutingMode routingMode = AppRoutingMode.allProxy,
    List<String> managedProcessNames = const [],
    String appProcessName = '',
    bool? windows,
    RuleListDomains ruleLists = RuleListDomains.none,
    List<RouteServerOutbound> routeServers = const [],
    List<RouteAppRules> appRoutes = const [],
    OwnerGuard ownerGuard = OwnerGuard.off,
    GeoAssetIndex? geoIndex,
  }) =>
      const JsonEncoder.withIndent('  ').convert(
        build(
          input,
          settings,
          socksPort: socksPort,
          httpPort: httpPort,
          resolvedServerIp: resolvedServerIp,
          localInboundsNoAuth: localInboundsNoAuth,
          apiPort: apiPort,
          apiSecret: apiSecret,
          tun: tun,
          routingMode: routingMode,
          managedProcessNames: managedProcessNames,
          appProcessName: appProcessName,
          windows: windows,
          ruleLists: ruleLists,
          routeServers: routeServers,
          appRoutes: appRoutes,
          ownerGuard: ownerGuard,
          geoIndex: geoIndex,
        ),
      );

  // httpPort нужен и на Android: Dart HttpClient не умеет SOCKS, а прямой запрос уходит мимо туннеля
  static Map<String, dynamic> build(
    String input,
    AppSettings settings, {
    required int socksPort,
    int? httpPort,
    String? resolvedServerIp,
    bool localInboundsNoAuth = false,
    int? apiPort,
    String apiSecret = '',
    MihomoTunOptions? tun,
    AppRoutingMode routingMode = AppRoutingMode.allProxy,
    List<String> managedProcessNames = const [],
    String appProcessName = '',
    bool? windows,
    RuleListDomains ruleLists = RuleListDomains.none,
    List<RouteServerOutbound> routeServers = const [],
    List<RouteAppRules> appRoutes = const [],
    OwnerGuard ownerGuard = OwnerGuard.off,
    GeoAssetIndex? geoIndex,
  }) {
    // сплит по процессам только на десктопном TUN: на Android его исполняет VpnService
    final processRules = tun != null && !tun.fromFileDescriptor;
    // на Android владельца ядро спрашивает у приложения (mihomo-android-uid-owner.patch)
    final appRules = tun != null ? appRoutes : const <RouteAppRules>[];
    final guard =
        tun != null && tun.fromFileDescriptor ? ownerGuard : OwnerGuard.off;
    final findProcess =
        processRules || appRules.isNotEmpty || guard != OwnerGuard.off;

    // без правил по процессам режим только выбранные держит финал DIRECT, и в DIRECT уходило всё.
    // там, где процесс не найти, верный режим один: весь трафик
    final effectiveRoutingMode = processRules
        ? routingMode
        : AppRoutingMode.allProxy;

    // fake-ip держится на перехвате DNS из tun-блока, без своего туннеля подменный адрес некому вернуть
    final fakeIp = settings.fakeIp && tun != null;

    final authored = CustomClashConfig.tryParse(input);
    final parsedClash =
        geoIndex == null ? authored : authored?.withKnownGeo(geoIndex).config;
    final clash = settings.ignoreProviderRules
        ? parsedClash?.withoutProviderRules()
        : parsedClash;
    if (clash != null) {
      return _buildCustom(
        clash,
        settings,
        socksPort: socksPort,
        httpPort: httpPort,
        resolvedServerIp: resolvedServerIp,
        localInboundsNoAuth: localInboundsNoAuth,
        apiPort: apiPort,
        apiSecret: apiSecret,
        tun: tun,
        routingMode: effectiveRoutingMode,
        managedProcessNames: managedProcessNames,
        appProcessName: appProcessName,
        processRules: processRules,
        fakeIp: fakeIp,
        windows: windows,
        ruleLists: ruleLists,
        routeServers: routeServers,
        appRoutes: appRules,
        ownerGuard: guard,
      );
    }

    final proxies = buildProxies(input.trim());
    final addresses = _serverAddresses(proxies);

    return <String, dynamic>{
      ..._inbound(
        settings,
        socksPort: socksPort,
        httpPort: httpPort,
        localInboundsNoAuth: localInboundsNoAuth,
        apiPort: apiPort,
        apiSecret: apiSecret,
      ),
      'mode': 'rule',
      'log-level': _logLevel(settings.xrayCore.logLevel),
      // автообновление geo полезло бы в сеть до того, как поднялся туннель
      'geodata-mode': true,
      'geo-auto-update': false,
      if (settings.xrayCore.concurrentDial) 'tcp-concurrent': true,
      // поиск процесса стоит на каждой сессии, включаем только где без него не работают наши правила
      'find-process-mode': findProcess ? 'strict' : 'off',
      if (settings.xrayCore.udpPerAddress) udpPerExitKey: true,
      if (guard != OwnerGuard.off) ownerGuardKey: guard.name,
      'sniffer': buildSniffer(settings.xrayCore),
      if (buildHosts(settings.xrayCore).isNotEmpty)
        'hosts': buildHosts(settings.xrayCore),
      'dns': buildDns(settings, fakeIp: fakeIp),
      if (tun != null) 'tun': buildTun(tun),
      if (settings.lanSharing) 'listeners': buildLanListeners(settings),
      if (settings.lanSharing || appRules.isNotEmpty)
        'sub-rules': {
          if (settings.lanSharing) lanRuleSet: buildLanRules(),
          ...buildAppRouteSubRules(
            settings,
            appRules,
            proxyTarget: proxyName,
            routeServers: routeServers,
          ),
        },
      'proxies': [...proxies, ...buildRouteServerProxies(routeServers)],
      if (buildRouteServerGroups(routeServers).isNotEmpty)
        'proxy-groups': buildRouteServerGroups(routeServers),
      if (!ruleLists.isEmpty ||
          routeServers.isNotEmpty ||
          appRules.isNotEmpty)
        'rule-providers': {
          ...buildRuleListProviders(ruleLists),
          ...buildRouteServerProviders(routeServers),
          ...buildAppRouteProviders(appRules),
        },
      'rules': buildRules(
        settings,
        serverAddress: addresses.firstOrNull ?? '',
        chainAddresses: addresses.skip(1).toList(),
        resolvedServerIp: resolvedServerIp,
        routingMode: effectiveRoutingMode,
        managedProcessNames: processRules ? managedProcessNames : const [],
        appProcessName: processRules ? appProcessName : '',
        tunOwned: tun != null,
        windows: windows,
        ruleLists: ruleLists,
        routeServers: routeServers,
        appRoutes: appRules,
        ownerGuard: guard,
      ),
    };
  }

  // адрес интерфейса не задать: mihomo считает его из dns.fake-ip-range, даже без fake-ip.
  // поэтому готовность туннеля по имени, а не по адресу

  static Map<String, dynamic> buildTun(MihomoTunOptions tun) =>
      <String, dynamic>{
        'enable': true,
        if (tun.device != null && tun.device!.isNotEmpty) 'device': tun.device,
        'stack': tun.stack,
        if (tun.mtu > 0) 'mtu': tun.mtu,
        'auto-route': tun.autoRoute,
        'auto-detect-interface': tun.autoDetectInterface,
        if (tun.strictRoute) 'strict-route': true,
        'dns-hijack': const ['any:53'],
      };

  static Map<String, dynamic> _buildCustom(
    CustomClashConfig clash,
    AppSettings settings, {
    required int socksPort,
    int? httpPort,
    String? resolvedServerIp,
    bool localInboundsNoAuth = false,
    int? apiPort,
    String apiSecret = '',
    MihomoTunOptions? tun,
    AppRoutingMode routingMode = AppRoutingMode.allProxy,
    List<String> managedProcessNames = const [],
    String appProcessName = '',
    bool processRules = false,
    bool fakeIp = false,
    bool? windows,
    RuleListDomains ruleLists = RuleListDomains.none,
    List<RouteServerOutbound> routeServers = const [],
    List<RouteAppRules> appRoutes = const [],
    OwnerGuard ownerGuard = OwnerGuard.off,
  }) {
    final authorProviders = clash.map['rule-providers'];
    final authorSubRules = clash.map['sub-rules'];
    return clash.buildSessionConfig(
      inbound: _inbound(
        settings,
        socksPort: socksPort,
        httpPort: httpPort,
        localInboundsNoAuth: localInboundsNoAuth,
        apiPort: apiPort,
        apiSecret: apiSecret,
      ),
      sniffer: buildSniffer(settings.xrayCore),
      logLevel: _logLevel(settings.xrayCore.logLevel),
      // наш DNS только если у автора своего нет
      dns: buildDns(settings, fakeIp: fakeIp),
      // правила по процессам раньше авторских: это решение человека о своей машине
      prependRules: [
        ?outsideVpnRule(ownerGuard),
        exitIpProbeRule(clash.primaryTarget),
        if (processRules)
          ...buildProcessRules(
            routingMode: routingMode,
            managedProcessNames: managedProcessNames,
            appProcessName: appProcessName,
            windows: windows,
          ),
        ...buildServerDirectRules(
          serverAddress: clash.address,
          resolvedServerIp: resolvedServerIp,
        ),
        ...routeServerDirectRules(routeServers),
        if (tun != null) 'IP-CIDR,$tunInterfaceRange,DIRECT,no-resolve',
      ],
      appendRules: [
        ...buildUserRules(
          settings,
          proxyTarget: clash.primaryTarget,
          ruleLists: ruleLists,
          routeServers: routeServers,
          appRoutes: appRoutes,
        ),
        // MATCH провайдера выброшен вместе с его правилами, остальное решает человек
        if (settings.ignoreProviderRules)
          'MATCH,${_customFinalTarget(settings, clash, routingMode, managedProcessNames)}',
      ],
      extraProxies: buildRouteServerProxies(routeServers),
      extraGroups: buildRouteServerGroups(routeServers),
      extra: {
        if (!ruleLists.isEmpty ||
            routeServers.isNotEmpty ||
            appRoutes.isNotEmpty)
          'rule-providers': {
            if (authorProviders is Map) ...authorProviders,
            ...buildRuleListProviders(ruleLists),
            ...buildRouteServerProviders(routeServers),
            ...buildAppRouteProviders(appRoutes),
          },
        if (!clash.map.containsKey('hosts') &&
            buildHosts(settings.xrayCore).isNotEmpty)
          'hosts': buildHosts(settings.xrayCore),
        if (processRules || appRoutes.isNotEmpty || ownerGuard != OwnerGuard.off)
          'find-process-mode': 'strict',
        if (settings.xrayCore.udpPerAddress) udpPerExitKey: true,
        if (ownerGuard != OwnerGuard.off) ownerGuardKey: ownerGuard.name,
        if (tun != null) 'tun': buildTun(tun),
        if (settings.lanSharing) 'listeners': buildLanListeners(settings),
        // наборы автора остаются: его правила на них ссылаются
        if (settings.lanSharing || appRoutes.isNotEmpty)
          'sub-rules': {
            if (authorSubRules is Map) ...authorSubRules,
            if (settings.lanSharing)
              lanRuleSet: buildLanRules(target: clash.primaryTarget),
            ...buildAppRouteSubRules(
              settings,
              appRoutes,
              proxyTarget: clash.primaryTarget,
              routeServers: routeServers,
            ),
          },
      },
    );
  }

  static Map<String, dynamic> _inbound(
    AppSettings settings, {
    required int socksPort,
    int? httpPort,
    required bool localInboundsNoAuth,
    int? apiPort,
    String apiSecret = '',
  }) {
    final creds = Socks5Credentials();
    return <String, dynamic>{
      'socks-port': socksPort,
      // port у mihomo это HTTP-прокси: через него ходит апдейтер и на него смотрит системный прокси
      'port': ?httpPort,
      'bind-address': '127.0.0.1',
      'allow-lan': false,
      // глобальный ipv6: false режет AAAA независимо от dns.ipv6, берём из той же стратегии
      'ipv6': settings.xrayCore.dnsQueryStrategy != 'UseIPv4',
      // глобальная авторизация на socks-port, LAN-листенеры из-под неё выведены своим users
      if (!localInboundsNoAuth)
        'authentication': ['${creds.username}:${creds.password}'],
      // secret обязателен: петля на Android общая, без него любое приложение управляло бы туннелем
      if (apiPort != null) ...{
        'external-controller': '127.0.0.1:$apiPort',
        'secret': apiSecret,
      },
    };
  }

  // маска *. переводится в +.: у mihomo звёздочка значит ровно один уровень

  static Map<String, dynamic> buildNameserverPolicy(XrayCoreSettings core) {
    final parsed = XrayCoreSettings.parseDnsPolicy(core.dnsPolicy).entries;
    final out = <String, dynamic>{};
    for (final entry in parsed.entries) {
      final servers = <String>[];
      for (final address in entry.value) {
        final converted = _dnsAddress(address);
        if (converted != null && !servers.contains(converted)) {
          servers.add(converted);
        }
      }
      if (servers.isEmpty) continue;
      final key = entry.key.startsWith('*.')
          ? '+.${entry.key.substring(2)}'
          : entry.key;
      out[key] = servers;
    }
    return out;
  }

  static Map<String, dynamic> buildHosts(XrayCoreSettings core) {
    final parsed = XrayCoreSettings.parseDnsHosts(core.dnsHosts).entries;
    return {
      for (final entry in parsed.entries)
        (entry.key.startsWith('*.')
                ? '+.${entry.key.substring(2)}'
                : entry.key):
            entry.value.length == 1 ? entry.value.single : entry.value,
    };
  }

  // parse-pure-ip обязателен: без него ядро нюхает только соединения с именем хоста, а у нас его нет.
  // порты только строками, число роняет конфиг (cannot unmarshal !!int into string)
  static Map<String, dynamic> buildSniffer(XrayCoreSettings core) => {
        'enable': core.sniffingEnabled,
        'parse-pure-ip': true,
        'override-destination': !core.sniffingRouteOnly,
        'sniff': {
          'HTTP': {
            'ports': ['80', '8080-8880'],
          },
          'TLS': {
            'ports': ['443', '8443'],
          },
          'QUIC': {
            'ports': ['443', '8443'],
          },
        },
      };

  // пустой users значит без пароля, а отсутствующий ключ подставит глобальный authentication с нашими кредами

  static List<Map<String, dynamic>> buildLanListeners(AppSettings settings) {
    final users = lanUsers(settings);
    return [
      {
        'name': lanSocksListener,
        'type': 'socks',
        'listen': '0.0.0.0',
        'port': '${settings.lanSocksPort}',
        'udp': true,
        'rule': lanRuleSet,
        'users': users,
      },
      {
        'name': lanHttpListener,
        'type': 'http',
        'listen': '0.0.0.0',
        'port': '${settings.lanHttpPort}',
        'rule': lanRuleSet,
        'users': users,
      },
    ];
  }

  static List<Map<String, String>> lanUsers(AppSettings settings) {
    final user = settings.lanUsername.trim();
    final pass = settings.lanPassword;
    if (user.isEmpty || pass.isEmpty) return const [];
    return [
      {'username': user, 'password': pass},
    ];
  }

  static const _lanSourceRanges = [
    '10.0.0.0/8',
    '172.16.0.0/12',
    '192.168.0.0/16',
    '169.254.0.0/16',
    '127.0.0.0/8',
  ];

  // в конце MATCH,REJECT: без него несовпавшее уходит в DIRECT, и раздача становится открытым прокси
  static List<String> buildLanRules({String target = proxyName}) => [
        for (final range in _lanSourceRanges) 'SRC-IP-CIDR,$range,$target',
        'MATCH,REJECT',
      ];

  // не боевой конфиг: geo-базы ядро разбирает полсекунды, и они уехали бы в измеренную задержку

  static String generatePingConfig(
    String input,
    AppSettings settings, {
    required int socksPort,
    bool httpInbound = false,
    String? outboundInterface,
  }) {
    final proxies = buildProxies(input.trim());
    return jsonEncode(<String, dynamic>{
      if (httpInbound) 'port': socksPort else 'socks-port': socksPort,
      'bind-address': '127.0.0.1',
      'allow-lan': false,
      // как xray в пробе: только IPv4, иначе разница цифр окажется разницей семейства адресов
      'ipv6': false,
      'mode': 'rule',
      'log-level': 'silent',
      'find-process-mode': 'off',
      'geo-auto-update': false,
      'interface-name': ?outboundInterface,
      'dns': _pingDns(),
      'proxies': proxies,
      'rules': ['MATCH,$proxyName'],
    });
  }

  // фиксированный, как у xray: UDP-53 у части провайдеров подменяют. #DIRECT значит мимо правил
  static Map<String, dynamic> _pingDns() => <String, dynamic>{
        'enable': true,
        'ipv6': false,
        'enhanced-mode': 'normal',
        'default-nameserver': const ['https://1.1.1.1/dns-query'],
        'nameserver': const [
          'https://1.1.1.1/dns-query#DIRECT',
          'https://8.8.8.8/dns-query#DIRECT',
          'system',
        ],
      };

  // без enable mihomo резолвит средствами Go, а на Android нет /etc/resolv.conf, и домен сервера не резолвится

  static Map<String, dynamic> buildDns(
    AppSettings settings, {
    bool fakeIp = false,
  }) {
    final core = settings.xrayCore;
    final servers = dnsServers(core);
    final policy = buildNameserverPolicy(core);
    final globalProxy =
        settings.finalOutbound == AppSettings.finalOutboundProxy;
    // через туннель CDN отдаёт узлы рядом с сервером, прямым соединениям нужен ближний к дому,
    // этот список ядро читает без respect-rules
    final viaTunnel = globalProxy &&
        servers.any((s) =>
            !s.endsWith('#DIRECT') && s != 'system' && !s.startsWith('dhcp://'));

    return <String, dynamic>{
      'enable': true,
      'ipv6': core.dnsQueryStrategy != 'UseIPv4',
      'enhanced-mode': fakeIp ? 'fake-ip' : 'normal',
      if (fakeIp) ...{
        // из него же ядро берёт адрес своего tun-интерфейса, а его мы пускаем мимо туннеля
        'fake-ip-range': fakeIpRange,
        'fake-ip-filter': fakeIpFilter,
      },
      if (policy.isNotEmpty) 'nameserver-policy': policy,
      'default-nameserver': bootstrapNameservers(core),
      // адрес прокси-сервера всегда мимо туннеля, иначе круг
      'proxy-server-nameserver': servers,
      'nameserver': servers,
      if (viaTunnel) ...{
        'direct-nameserver': [...servers, ...directPlainFallback(servers)],
        // иначе домен со своим резолвером напрямую не открылся бы
        if (policy.isNotEmpty) 'direct-nameserver-follow-policy': true,
      },
      // respect-rules гоняет DNS ядра по правилам, то есть в туннель
      if (globalProxy) 'respect-rules': true,
    };
  }

  // h2c и fakedns mihomo не знает, неизвестная схема роняет конфиг. +local становится #DIRECT:
  // с respect-rules сервер с пустым фрагментом получает RULES и уезжает в туннель
  static List<String> dnsServers(XrayCoreSettings core) {
    const fallback = ['https://1.1.1.1/dns-query', 'https://8.8.8.8/dns-query'];
    if (!core.dnsUseCustom) return fallback;

    final out = <String>[];
    for (final raw in _parseList(core.dnsServers)) {
      final converted = _dnsAddress(raw);
      if (converted != null && !out.contains(converted)) out.add(converted);
    }
    return out.isEmpty ? fallback : out;
  }

  // по нему ядро ходит напрямую, и провайдер видит содержимое: берём свои серверы с IP вместе со схемой,
  // голый 9.9.9.9 отдал бы запрос открытым
  static List<String> bootstrapNameservers(XrayCoreSettings core) {
    final out = [
      for (final server in dnsServers(core))
        if (_hasIpAddress(server)) server,
    ];
    return out.isEmpty ? _bootstrapFallback : out;
  }

  static const _bootstrapFallback = ['1.1.1.1', '8.8.8.8'];

  // DoH к публичным резолверам провайдер может резать, и прямое соединение висело на резолве (issue #9).
  // список опрашивается параллельно, живой DoH запасной не тормозит. system не годится: на Android это 114.114.114.114
  static List<String> directPlainFallback(List<String> servers) {
    final hasPlain = servers.any((s) =>
        s == 'system' ||
        !s.contains('://') ||
        s.startsWith('udp://') ||
        s.startsWith('tcp://') ||
        s.startsWith('dhcp://'));
    if (hasPlain) return const [];
    final out = <String>[];
    for (final server in servers) {
      final host = _hostOf(server);
      final ip = InternetAddress.tryParse(host);
      if (ip == null) continue;
      final plain = ip.type == InternetAddressType.IPv6 ? '[$host]' : host;
      if (!out.contains(plain)) out.add(plain);
    }
    return out;
  }

  static bool _hasIpAddress(String server) =>
      InternetAddress.tryParse(_hostOf(server)) != null;

  static String _hostOf(String server) {
    var host = server;
    final hash = host.indexOf('#');
    if (hash >= 0) host = host.substring(0, hash);
    final scheme = host.indexOf('://');
    if (scheme >= 0) host = host.substring(scheme + 3);
    final slash = host.indexOf('/');
    if (slash >= 0) host = host.substring(0, slash);
    if (host.startsWith('[')) {
      final close = host.indexOf(']');
      if (close < 0) return '';
      host = host.substring(1, close);
    } else if (':'.allMatches(host).length == 1) {
      // одно двоеточие это порт, у голого IPv6 их больше
      host = host.substring(0, host.indexOf(':'));
    }
    return host;
  }

  static const _dnsSchemes = {'https', 'tls', 'quic', 'tcp', 'udp', 'dhcp'};

  static String? _dnsAddress(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    if (v.toLowerCase() == 'localhost') return 'system';

    final scheme = RegExp(r'^([a-zA-Z0-9]+)(\+local)?://').firstMatch(v);
    if (scheme == null) {
      return v;
    }
    final name = scheme.group(1)!.toLowerCase();
    if (!_dnsSchemes.contains(name)) return null;
    final local = scheme.group(2) != null;
    return '$name://${v.substring(scheme.end)}${local ? '#DIRECT' : ''}';
  }

  static String _logLevel(String xrayLevel) =>
      xrayLevel == 'none' ? 'silent' : xrayLevel;

  // звено цепочки по префиксу узнают соединения и счётчик трафика: mihomo пишет его соединение отдельно
  // как Inner (component/proxydialer), и трафик выхода посчитался бы дважды
  static const chainHopPrefix = 'keq-chain-';

  static bool isChainHop(String proxy) => proxy.startsWith(chainHopPrefix);

  // выход остаётся под именем, на которое смотрят правила. dialer-proxy умеет любой исходящий (adapter/outbound/base.go)
  static List<Map<String, dynamic>> buildProxies(
    String input, {
    String name = proxyName,
  }) {
    final chain = ProxyChainConfig.tryParse(input);
    if (chain == null) return [{...buildProxy(input), 'name': name}];
    if (chain.hops.isEmpty) throw ArgumentError('Proxy chain has no nodes');
    String hop(int i) =>
        name == proxyName ? '$chainHopPrefix$i' : '$chainHopPrefix$name-$i';
    final last = chain.hops.length - 1;
    return [
      for (var i = 0; i <= last; i++)
        {
          ...buildProxy(chain.hops[i].config.trim()),
          'name': i == last ? name : hop(i),
          if (i > 0) 'dialer-proxy': hop(i - 1),
        },
    ];
  }

  // мимо туннеля все узлы, как у xray: обращение к промежуточному закольцевалось бы через цепочку
  static List<String> _serverAddresses(List<Map<String, dynamic>> proxies) => [
        for (final proxy in proxies)
          if (CustomClashConfig.serverOf(proxy).address.isNotEmpty)
            CustomClashConfig.serverOf(proxy).address,
      ];

  static Map<String, dynamic> buildProxy(String link) {
    if (AwgProfile.isAwgConfig(link)) return _amneziaWg(link);
    final lower = link.toLowerCase();
    if (lower.startsWith('vmess://')) return _vmess(link);
    if (lower.startsWith('vless://')) return _vless(link);
    if (lower.startsWith('trojan://')) return _trojan(link);
    if (lower.startsWith('ss://')) return _shadowsocks(link);
    if (lower.startsWith('hysteria2://') || lower.startsWith('hy2://')) {
      return _hysteria2(link);
    }
    if (lower.startsWith('tuic://')) return _tuic(link);
    if (lower.startsWith('anytls://')) return _anytls(link);
    if (lower.startsWith('ssr://')) return _ssr(link);
    if (lower.startsWith('mierus://')) return _mieru(link);
    if (SocksLink.isSocks(link)) return _socks(link);
    if (lower.startsWith('hysteria://')) {
      if (HysteriaLinkParams.isV1(link)) {
        throw ArgumentError(
          'mihomo: Hysteria v1 is not supported. Use a hysteria2:// link',
        );
      }
      return _hysteria2(link);
    }
    final scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):').firstMatch(link)?.group(1);
    throw ArgumentError(
      'mihomo: unsupported protocol${scheme != null ? ' ($scheme)' : ''}',
    );
  }

  static Uri _parse(String link) {
    try {
      return Uri.parse(link);
    } catch (_) {
      // без самой ссылки: в ней UUID и пароль, а текст ошибки уходит в логи
      throw ArgumentError('mihomo: invalid URI in server config');
    }
  }

  static String _param(Uri uri, String key, [String def = '']) {
    final all = uri.queryParametersAll[key];
    return (all != null && all.isNotEmpty) ? all.first : def;
  }

  // + не трогаем: панели его не кодируют, а queryParameters делает из него пробел
  static String _rawParam(Uri uri, String key) {
    for (final pair in uri.query.split('&')) {
      final eq = pair.indexOf('=');
      if (eq < 0) continue;
      if (Uri.decodeComponent(pair.substring(0, eq)) != key) continue;
      return Uri.decodeComponent(pair.substring(eq + 1));
    }
    return '';
  }

  // ech у xray это либо сам ECHConfigList, либо адрес DNS для него. у mihomo первому отвечает config,
  // второму пустой config с запросом HTTPS-записи, адрес DNS подставить некуда
  static Map<String, dynamic>? _echOpts(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (!value.contains('://')) return {'enable': true, 'config': value};
    final name = value.split('+').first.trim();
    return {
      'enable': true,
      if (name.isNotEmpty && !name.contains('://')) 'query-server-name': name,
    };
  }

  // REALITY в xray с 26.9.9 молча отказывает приветствию без X25519MLKEM768 (REALITY authentication failed),
  // а mihomo без флага ключ вырезает. ключ несут только профили chrome, firefox у mihomo застрял на 120
  static Map<String, dynamic> _realityOpts({
    required String publicKey,
    required String shortId,
  }) {
    return {
      'public-key': publicKey,
      'short-id': shortId,
      'support-x25519mlkem768': true,
    };
  }

  static List<String>? _alpn(String raw) {
    final list = raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return list.isEmpty ? null : list;
  }

  // незнакомый транспорт это ошибка, а не тихий откат на tcp: xhttp уже превращался в голый tcp.
  // skip-cert-verify не пишем никогда, как и allowInsecure у xray
  static void _applyTransport(
    Map<String, dynamic> out,
    Uri uri, {
    required String protocol,
    required String network,
    required String host,
  }) {
    _refuseForeignTransport(protocol, network);
    switch (network) {
      case '' || 'tcp' || 'raw':
        // маскировка HTTP у mihomo отдельный network, а не флаг: без неё сервер ждёт заголовки и молчит
        if (_param(uri, 'headerType').toLowerCase() == 'http') {
          // у TrojanOption нет http-opts, такая ссылка только для xray
          if (protocol == 'trojan') {
            throw ArgumentError('mihomo: trojan over http header is xray-only');
          }
          final method = _param(uri, 'method');
          final path = _param(uri, 'path', '/');
          out['network'] = 'http';
          out['http-opts'] = {
            if (method.isNotEmpty) 'method': method,
            'path': [path],
            'headers': {if (host.isNotEmpty) 'Host': [_param(uri, 'host', host)]},
          };
        } else {
          out['network'] = 'tcp';
        }
      case 'ws':
        final early = _earlyData(uri, _param(uri, 'path', '/'));
        final wsHost = _param(uri, 'host', host);
        out['network'] = 'ws';
        out['ws-opts'] = {
          'path': early.path,
          if (wsHost.isNotEmpty) 'headers': {'Host': wsHost},
          if (early.size != null) 'max-early-data': early.size,
          // без имени заголовка ядро ранние данные не отправит, а ссылки его обычно не называют
          if (early.size != null || early.header != null)
            'early-data-header-name': early.header ?? 'Sec-WebSocket-Protocol',
        };
      case 'grpc':
        out['network'] = 'grpc';
        out['grpc-opts'] = {
          'grpc-service-name': _param(uri, 'serviceName'),
        };
      case 'http' || 'h2':
        // host, а не sni: у h2 это имя в заголовке, сервер за общим фронтом различает по нему узлы
        final h2Host = _param(uri, 'host', host);
        out['network'] = 'h2';
        out['h2-opts'] = {
          'path': _param(uri, 'path', '/'),
          if (h2Host.isNotEmpty) 'host': [h2Host],
        };
      case 'httpupgrade':
        final upgrade = _earlyData(uri, _param(uri, 'path', '/'));
        out['network'] = 'ws';
        out['ws-opts'] = {
          'path': upgrade.path,
          'v2ray-http-upgrade': true,
          if (upgrade.size != null) 'v2ray-http-upgrade-fast-open': true,
          if (host.isNotEmpty) 'headers': {'Host': _param(uri, 'host', host)},
        };
      case 'xhttp' || 'splithttp':
        out['network'] = 'xhttp';
        out['xhttp-opts'] = _xhttpOpts(uri);
      default:
        throw ArgumentError('mihomo: unsupported transport ($network)');
    }
  }

  // незнакомый network ядро не проверяет и говорит с сервером голым TCP поверх TLS, отказ громче
  static void _refuseForeignTransport(String protocol, String network) {
    final foreign = switch ((protocol, network)) {
      // xhttp-opts есть только у VlessOption
      ('vmess' || 'trojan', 'xhttp' || 'splithttp') => true,
      // у TrojanOption нет ни h2-opts, ни http-opts
      ('trojan', 'http' || 'h2') => true,
      _ => false,
    };
    if (foreign) {
      throw ArgumentError('mihomo: $protocol over $network is xray-only');
    }
  }

  // NewVless включает xudp сам, если packet-addr не задан, пустая карта ничего не выключает.
  // NewVmess сам не включает, а xray шлёт UDP vmess через XUDP по умолчанию (cone в proxy/vmess/outbound)
  static Map<String, dynamic> _packetEncoding(String raw, {bool vmess = false}) =>
      switch (raw.trim().toLowerCase()) {
        '' => vmess ? const {'xudp': true} : const {},
        'none' => const {},
        'packet' => const {'packet-addr': true},
        _ => const {'xudp': true},
      };

  // ed из пути вынимаем: ядро читает только поле, а путь с хвостом сервер не ждёт
  static ({String path, int? size, String? header}) _earlyData(
    Uri uri,
    String rawPath,
  ) {
    var path = rawPath;
    var size = int.tryParse(_param(uri, 'ed'));
    var header = _param(uri, 'eh');

    final query = rawPath.indexOf('?');
    if (query >= 0) {
      final parsed = Uri.tryParse(rawPath);
      if (parsed != null) {
        final params = Map<String, String>.from(parsed.queryParameters);
        size ??= int.tryParse(params.remove('ed') ?? '');
        final inPath = params.remove('eh') ?? '';
        if (header.isEmpty) header = inPath;
        path = params.isEmpty
            ? rawPath.substring(0, query)
            : Uri(path: parsed.path, queryParameters: params).toString();
      }
    }
    return (
      path: path,
      size: size,
      header: header.isEmpty ? null : header,
    );
  }

  static Map<String, dynamic> _xhttpOpts(Uri uri) {
    final extra = _extraObject(uri);

    String pick(String queryKey, String extraKey) {
      final fromQuery = _param(uri, queryKey).trim();
      if (fromQuery.isNotEmpty) return fromQuery;
      return extra[extraKey]?.toString().trim() ?? '';
    }

    final host = pick('host', 'host');
    final path = pick('path', 'path');
    final mode = pick('mode', 'mode');
    final padding = pick('x_padding_bytes', 'xPaddingBytes');

    final opts = <String, dynamic>{
      'path': path.isEmpty ? '/' : path,
      if (host.isNotEmpty) 'host': host,
      if (mode.isNotEmpty) 'mode': mode,
      if (padding.isNotEmpty) 'x-padding-bytes': padding,
    };

    for (final field in _xhttpExtraFields.entries) {
      if (opts.containsKey(field.value)) continue;
      final value = extra[field.key]?.toString().trim() ?? '';
      if (value.isNotEmpty) opts[field.value] = value;
    }
    for (final flag in _xhttpExtraFlags.entries) {
      if (extra[flag.key] == true) opts[flag.value] = true;
    }
    _applyXPaddingObfsDefaults(opts);

    final headers = _headers(extra['headers']);
    if (headers != null) opts['headers'] = headers;

    final reuse = _xmux(extra);
    if (reuse != null) opts['reuse-settings'] = reuse;
    final download = _downloadSettings(extra['downloadSettings']);
    if (download != null) opts['download-settings'] = download;
    return opts;
  }

  // этими полями описан сам вид запроса, без них mihomo слал свои и сервер отвечал 400.
  // у части полей два написания, берётся первое непустое, порядок значим
  static const Map<String, String> _xhttpExtraFields = {
    'xPaddingKey': 'x-padding-key',
    'xPaddingHeader': 'x-padding-header',
    'xPaddingPlacement': 'x-padding-placement',
    'xPaddingMethod': 'x-padding-method',
    'uplinkHTTPMethod': 'uplink-http-method',
    'uplinkDataPlacement': 'uplink-data-placement',
    'uplinkDataKey': 'uplink-data-key',
    'uplinkChunkSize': 'uplink-chunk-size',
    'sessionPlacement': 'session-placement',
    'sessionIDPlacement': 'session-placement',
    'sessionKey': 'session-key',
    'sessionIDKey': 'session-key',
    'sessionIDTable': 'session-table',
    'sessionIDLength': 'session-length',
    'seqPlacement': 'seq-placement',
    'seqKey': 'seq-key',
    'scMaxEachPostBytes': 'sc-max-each-post-bytes',
    'scMinPostsIntervalMs': 'sc-min-posts-interval-ms',
  };

  static const Map<String, String> _xhttpExtraFlags = {
    'xPaddingObfsMode': 'x-padding-obfs-mode',
    'noGRPCHeader': 'no-grpc-header',
  };

  // в режиме obfs xray кладёт набивку в X-Padding, и сервер без неё отвечает 400, а mihomo при пустом
  // x-padding-placement её не добавляет. дописываем дефолты xray
  static void _applyXPaddingObfsDefaults(Map<String, dynamic> opts) {
    if (opts['x-padding-obfs-mode'] != true) return;
    opts.putIfAbsent('x-padding-placement', () => 'queryInHeader');
    opts.putIfAbsent('x-padding-header', () => 'X-Padding');
    opts.putIfAbsent('x-padding-key', () => 'x_padding');
  }

  static Map<String, dynamic> _extraObject(Uri uri) {
    final raw = _param(uri, 'extra').trim();
    if (raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }

  // поля строками, кроме hKeepAlivePeriod: принимают диапазоны 16-32
  static Map<String, dynamic>? _xmux(Map<String, dynamic> extra) {
    final nested = extra['xmux'];
    final xmux = <String, dynamic>{
      ...extra,
      if (nested is Map) ...Map<String, dynamic>.from(nested),
    };
    String value(String key) => xmux[key]?.toString().trim() ?? '';

    final keepAlive = int.tryParse(value('hKeepAlivePeriod'));
    final out = <String, dynamic>{
      for (final field in const {
        'maxConcurrency': 'max-concurrency',
        'maxConnections': 'max-connections',
        'cMaxReuseTimes': 'c-max-reuse-times',
        'hMaxRequestTimes': 'h-max-request-times',
        'hMaxReusableSecs': 'h-max-reusable-secs',
      }.entries)
        if (value(field.key).isNotEmpty) field.value: value(field.key),
      'h-keep-alive-period': ?keepAlive,
    };
    return out.isEmpty ? null : out;
  }

  static Map<String, String>? _headers(Object? raw) {
    if (raw is! Map || raw.isEmpty) return null;
    return {for (final e in raw.entries) e.key.toString(): e.value.toString()};
  }

  // у xray это полное описание подключения, а mihomo незаданное берёт у основного, и скачивание
  // уехало бы с его SNI, REALITY и пином. поэтому пишем явно, даже пустым
  static Map<String, dynamic>? _downloadSettings(Object? raw) {
    if (raw is! Map) return null;
    Map<String, dynamic> obj(Object? v) =>
        v is Map ? Map<String, dynamic>.from(v) : const {};
    String str(Map<String, dynamic> m, String key) =>
        m[key]?.toString().trim() ?? '';
    String single(String csv) {
      final values = _csv(csv);
      return values.length == 1 ? values.single : '';
    }

    final ds = obj(raw);
    final address = str(ds, 'address');
    final security = str(ds, 'security').toLowerCase();
    final reality = security == 'reality';
    final isTls = reality || security == 'tls';
    final tls = obj(ds[reality ? 'realitySettings' : 'tlsSettings']);
    final xhttp = obj(ds['xhttpSettings']);
    // свой extra у скачивания замещает его настройки, кроме host и path
    final nested = obj(xhttp['extra']);
    final shape = nested.isNotEmpty ? nested : xhttp;
    final path = str(xhttp, 'path');
    // ключ REALITY у xray бывает и в password, тогда главнее он
    final password = str(tls, 'password');
    final publicKey = password.isNotEmpty ? password : str(tls, 'publicKey');

    final out = <String, dynamic>{
      if (address.isNotEmpty) 'server': address,
      'port': ?int.tryParse(str(ds, 'port')),
      'tls': isTls,
      'host': str(xhttp, 'host'),
      'path': path.isEmpty ? '/' : path,
      // пустой ключ единственный способ сказать mihomo без REALITY
      'reality-opts': reality
          ? _realityOpts(
              publicKey: publicKey,
              shortId: str(tls, 'shortId'),
            )
          : {'public-key': ''},
      // пин и имя проверки свои: сертификат тут другой
      'fingerprint': reality ? '' : single(str(tls, 'pinnedPeerCertSha256')),
      'name-cert-verify':
          reality ? '' : single(str(tls, 'verifyPeerCertByName')),
    };
    if (isTls) {
      final serverName = str(tls, 'serverName');
      final sni = serverName.isNotEmpty ? serverName : address;
      if (sni.isNotEmpty) out['servername'] = sni;
      final fp = str(tls, 'fingerprint');
      out['client-fingerprint'] = fp.isNotEmpty ? fp : defaultTlsFingerprint;
      final alpnRaw = tls['alpn'];
      final alpn = _alpn(
        alpnRaw is List ? alpnRaw.join(',') : alpnRaw?.toString() ?? '',
      );
      if (alpn != null) out['alpn'] = alpn;
    }
    final headers = _headers(shape['headers']);
    if (headers != null) out['headers'] = headers;
    final reuse = _xmux(shape);
    if (reuse != null) out['reuse-settings'] = reuse;
    return out;
  }

  // name-cert-verify аналог verifyPeerCertByName: без него сертификат сверяется с маскировочным sni.
  // переносим только одно значение, чужой отпечаток наугад закрыл бы соединение
  static void _applyCertPinning(Map<String, dynamic> out, Uri uri) {
    final names = _csv(_param(uri, 'vcn'));
    if (names.length == 1) out['name-cert-verify'] = names.first;
    final pins = _csv(_rawParam(uri, 'pcs'));
    if (pins.length == 1) out['fingerprint'] = pins.first;
  }

  static List<String> _csv(String raw) =>
      raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  static Map<String, dynamic> _vless(String link) {
    final uri = _parse(link);
    final flow = _param(uri, 'flow');
    // без encryption ядро идёт открытым VLESS, а сервер ждёт mlkem и молча рвёт соединение
    final encryption = _param(uri, 'encryption').trim();
    return _vShareLink(uri, 'vless', {
      if (flow.isNotEmpty) 'flow': flow,
      if (encryption.isNotEmpty && encryption != 'none')
        'encryption': encryption,
    });
  }

  static Map<String, dynamic> _vShareLink(
    Uri uri,
    String type,
    Map<String, dynamic> protocolFields,
  ) {
    final uuid = uri.userInfo;
    if (uuid.isEmpty) {
      throw ArgumentError('${type.toUpperCase()} requires UUID in userInfo');
    }

    final security = _param(uri, 'security', 'none');
    final sni = _param(uri, 'sni', _param(uri, 'host', uri.host));
    final fp = _param(uri, 'fp');

    final out = <String, dynamic>{
      'name': proxyName,
      'type': type,
      'server': uri.host,
      'port': uri.port,
      'uuid': uuid,
      'udp': true,
      ..._packetEncoding(_param(uri, 'packetEncoding'), vmess: type == 'vmess'),
      ...protocolFields,
    };

    if (security == 'tls' || security == 'reality') {
      out['tls'] = true;
      if (sni.isNotEmpty) out['servername'] = sni;
      // пустой client-fingerprint mihomo понимает как без uTLS, а не chrome, как xray
      out['client-fingerprint'] = fp.isNotEmpty ? fp : defaultTlsFingerprint;
      final alpn = _alpn(_param(uri, 'alpn'));
      if (alpn != null) out['alpn'] = alpn;
      final ech = _echOpts(_rawParam(uri, 'ech'));
      if (ech != null) out['ech-opts'] = ech;
    }
    // у REALITY сертификат подставной, пинить нечего
    if (security == 'tls') _applyCertPinning(out, uri);
    if (security == 'reality') {
      out['reality-opts'] = _realityOpts(
        publicKey: _param(uri, 'pbk'),
        shortId: _param(uri, 'sid'),
      );
    }

    _applyTransport(out, uri,
        protocol: type, network: _param(uri, 'type', 'tcp'), host: sni);
    return out;
  }

  // два формата vmess, различаем как converter.go: не base64 значит ссылка
  static Map<String, dynamic> _vmess(String link) {
    final payload = link.substring('vmess://'.length).trim();
    if (payload.isEmpty) throw ArgumentError('VMess payload is empty');
    Map<String, dynamic>? cfg;
    try {
      var normalized = payload.replaceAll('-', '+').replaceAll('_', '/');
      while (normalized.length % 4 != 0) {
        normalized += '=';
      }
      final decoded = jsonDecode(utf8.decode(base64.decode(normalized)));
      if (decoded is Map) cfg = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    if (cfg == null) {
      // @ в base64 не бывает, у AEAD перед адресом UUID
      if (!payload.contains('@')) {
        throw ArgumentError('Invalid VMess payload format');
      }
      final uri = _parse(link);
      final cipher = _param(uri, 'encryption', 'auto');
      return _vShareLink(uri, 'vmess', {
        'alterId': 0,
        'cipher': cipher.isEmpty ? 'auto' : cipher,
      });
    }

    final json = cfg;
    String s(String key, [String def = '']) => json[key]?.toString() ?? def;

    final host = s('add');
    final sni = s('sni', s('host'));
    final out = <String, dynamic>{
      'name': proxyName,
      'type': 'vmess',
      'server': host,
      'port': int.tryParse(s('port')) ?? 0,
      'uuid': s('id'),
      'alterId': int.tryParse(s('aid', '0')) ?? 0,
      'cipher': s('scy', s('security', 'auto')),
      'udp': true,
      ..._packetEncoding('', vmess: true),
    };
    if (s('tls') == 'tls') {
      out['tls'] = true;
      if (sni.isNotEmpty) out['servername'] = sni;
      final fp = s('fp');
      out['client-fingerprint'] = fp.isNotEmpty ? fp : defaultTlsFingerprint;
      final alpn = _alpn(s('alpn'));
      if (alpn != null) out['alpn'] = alpn;
      final ech = _echOpts(s('ech'));
      if (ech != null) out['ech-opts'] = ech;
    }

    final net = s('net', 'tcp');
    final synthetic = Uri(
      scheme: 'vmess',
      host: host.isEmpty ? 'x' : host,
      queryParameters: {
        'type': net,
        // type в json vmess это заголовок маскировки, не транспорт
        'headerType': s('type'),
        'path': s('path', '/'),
        'host': s('host'),
        'serviceName': s('path'),
        'mode': s('mode'),
        'extra': s('extra'),
      },
    );
    _applyTransport(out, synthetic, protocol: 'vmess', network: net, host: sni);
    return out;
  }

  // пароль в ссылке закодирован (p%40ss), без декода в ядро уезжал бы как есть
  static String _decodedUserInfo(Uri uri) => _unescaped(uri.userInfo);

  static String _unescaped(String raw) {
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      return raw;
    }
  }

  static Map<String, dynamic> _socks(String link) {
    final socks = SocksLink.tryParse(link);
    if (socks == null) throw ArgumentError('Invalid SOCKS link');
    return {
      'name': proxyName,
      'type': 'socks5',
      'server': socks.host,
      'port': socks.port,
      if (socks.username.isNotEmpty) 'username': socks.username,
      if (socks.username.isNotEmpty) 'password': socks.password,
      'udp': true,
    };
  }

  static Map<String, dynamic> _trojan(String link) {
    final uri = _parse(link);
    final password = _decodedUserInfo(uri);
    if (password.isEmpty) throw ArgumentError('Trojan requires password');

    final sni = _param(uri, 'sni', uri.host);
    final fp = _param(uri, 'fp');
    final out = <String, dynamic>{
      'name': proxyName,
      'type': 'trojan',
      'server': uri.host,
      'port': uri.port,
      'password': password,
      'udp': true,
      if (sni.isNotEmpty) 'sni': sni,
      'client-fingerprint': fp.isNotEmpty ? fp : defaultTlsFingerprint,
      'ech-opts': ?_echOpts(_rawParam(uri, 'ech')),
    };
    final network = _param(uri, 'type', 'tcp');
    final alpn = _alpn(_param(uri, 'alpn'));
    if (alpn != null) out['alpn'] = _alpnForTrojan(network, alpn);
    // без reality-opts trojan шёл обычным TLS и получал сертификат маскировочного сайта
    if (_param(uri, 'security').trim().toLowerCase() == 'reality') {
      out['reality-opts'] = _realityOpts(
        publicKey: _param(uri, 'pbk'),
        shortId: _param(uri, 'sid'),
      );
    } else {
      _applyCertPinning(out, uri);
    }

    _applyTransport(out, uri, protocol: 'trojan', network: network, host: sni);
    return out;
  }

  // alpn на ws-пути в mihomo читает только trojan, у vless и vmess http/1.1 подставляется само.
  // одиночный h2 не трогаем
  static List<String> _alpnForTrojan(String network, List<String> alpn) =>
      network == 'ws' &&
              alpn.length == 2 &&
              alpn[0] == 'h2' &&
              alpn[1] == 'http/1.1'
          ? const ['http/1.1']
          : alpn;

  static Map<String, dynamic> _shadowsocks(String link) {
    // sip002 и старая форма: ss://base64(method:pass)@host:port и
    // ss://base64(method:pass@host:port).
    final withoutScheme = link.substring('ss://'.length).trim();
    final hashIdx = withoutScheme.indexOf('#');
    final beforeHash =
        hashIdx >= 0 ? withoutScheme.substring(0, hashIdx) : withoutScheme;
    final queryIdx = beforeHash.indexOf('?');
    final core = queryIdx >= 0 ? beforeHash.substring(0, queryIdx) : beforeHash;

    final atIdx = core.lastIndexOf('@');
    if (atIdx < 0) throw ArgumentError('Shadowsocks requires method:password');

    final userInfo = core.substring(0, atIdx);
    // перед ? по SIP002 стоит /, с плагином он обязателен
    final hostPort = core.substring(atIdx + 1).split('/').first;

    String method;
    String password;
    // без base64 метод и пароль по SIP002 обязаны быть в percent-кодировке, у ключей 2022 там + / =
    if (userInfo.contains(':')) {
      final i = userInfo.indexOf(':');
      method = _unescaped(userInfo.substring(0, i));
      password = _unescaped(userInfo.substring(i + 1));
    } else {
      var n = userInfo.replaceAll('-', '+').replaceAll('_', '/');
      while (n.length % 4 != 0) {
        n += '=';
      }
      final decoded = utf8.decode(base64.decode(n));
      final i = decoded.indexOf(':');
      if (i <= 0) throw ArgumentError('Invalid Shadowsocks userInfo');
      method = decoded.substring(0, i);
      password = decoded.substring(i + 1);
    }

    final colon = hostPort.lastIndexOf(':');
    if (colon < 0) throw ArgumentError('Shadowsocks requires host:port');

    final query = queryIdx >= 0 ? beforeHash.substring(queryIdx + 1) : '';
    final params = query.isEmpty
        ? const <String, String>{}
        : Uri.splitQueryString(query);
    final plugin = _ssPlugin(params['plugin'] ?? '');

    return <String, dynamic>{
      'name': proxyName,
      'type': 'ss',
      'server': hostPort.substring(0, colon),
      'port': int.tryParse(hostPort.substring(colon + 1)) ?? 0,
      'cipher': method,
      'password': password,
      'udp': true,
      if (_ssUdpOverTcp(params)) ...{
        'udp-over-tcp': true,
        'udp-over-tcp-version': ?int.tryParse(
          params['udp-over-tcp-version'] ?? params['UoTVersion'] ?? '',
        ),
      },
      ...?plugin,
    };
  }

  static bool _ssUdpOverTcp(Map<String, String> params) =>
      params['udp-over-tcp']?.toLowerCase() == 'true' ||
      params['udp-over-tcp'] == '1' ||
      params['uot'] == '1' ||
      params['uot']?.toLowerCase() == 'true';

  // разбор как в converter.go ядра: ; заменяются на &. формат в ссылке есть только у obfs и v2ray-plugin
  static Map<String, dynamic>? _ssPlugin(String raw) {
    final value = raw.trim();
    if (!value.contains(';')) return null;
    final Map<String, String> opts;
    try {
      opts = Uri.splitQueryString('pluginName=${value.replaceAll(';', '&')}');
    } catch (_) {
      return null;
    }
    final name = opts['pluginName'] ?? '';
    String pick(String key, [String alias = '']) {
      final direct = opts[key]?.trim() ?? '';
      if (direct.isNotEmpty || alias.isEmpty) return direct;
      return opts[alias]?.trim() ?? '';
    }

    if (name.contains('obfs') && !name.contains('v2ray-plugin')) {
      return {
        'plugin': 'obfs',
        'plugin-opts': {
          'mode': pick('obfs'),
          'host': pick('obfs-host'),
        },
      };
    }
    if (name.contains('v2ray-plugin')) {
      return {
        'plugin': 'v2ray-plugin',
        'plugin-opts': {
          'mode': pick('mode', 'obfs'),
          'host': pick('host', 'obfs-host'),
          'path': pick('path'),
          'tls': value.contains('tls'),
        },
      };
    }
    return null;
  }

  static Map<String, dynamic> _hysteria2(String link) {
    // Uri.parse не берёт порт вида host:20000-20050
    final params = HysteriaLinkParams.fromConfig(link);
    final uri = _parse(HysteriaLinkParams.splitPorts(link).$1);
    var password = _decodedUserInfo(uri);
    if (password.isEmpty) password = _param(uri, 'password', _param(uri, 'auth'));
    if (password.isEmpty) throw ArgumentError('Hysteria2 requires password');

    final sni = _param(uri, 'sni', uri.host);
    final obfs = _param(uri, 'obfs');
    final out = <String, dynamic>{
      'name': proxyName,
      'type': 'hysteria2',
      'server': uri.host,
      'port': HysteriaLinkParams.port(link),
      'password': password,
      if (sni.isNotEmpty) 'sni': sni,
      if (obfs.isNotEmpty) 'obfs': obfs,
      if (obfs.isNotEmpty)
        'obfs-password': _param(uri, 'obfs-password', _param(uri, 'obfsParam')),
    };
    final up = _param(uri, 'up');
    final down = _param(uri, 'down');
    if (up.isNotEmpty) out['up'] = up;
    if (down.isNotEmpty) out['down'] = down;
    final alpn = _alpn(_param(uri, 'alpn'));
    if (alpn != null) out['alpn'] = alpn;
    if (params.mport.isNotEmpty) {
      out['ports'] = params.mport;
      if (params.hopInterval.isNotEmpty) {
        out['hop-interval'] = params.hopInterval;
      }
    }
    // fingerprint тут отпечаток сертификата, а не uTLS
    if (params.pinSha256.isNotEmpty) out['fingerprint'] = params.pinSha256;
    return out;
  }

  // версии различаются формой userInfo, как в converter.go: uuid:password пятая, один токен четвёртая

  static Map<String, dynamic> _tuic(String link) {
    final uri = _parse(link);
    final userInfo = uri.userInfo;
    if (userInfo.isEmpty) throw ArgumentError('TUIC requires credentials');

    final split = userInfo.indexOf(':');
    final out = <String, dynamic>{
      'name': proxyName,
      'type': 'tuic',
      'server': uri.host,
      'port': uri.port,
      'udp': true,
      if (split > 0) ...{
        'uuid': Uri.decodeComponent(userInfo.substring(0, split)),
        'password': Uri.decodeComponent(userInfo.substring(split + 1)),
      } else
        'token': Uri.decodeComponent(userInfo),
    };

    final sni = _param(uri, 'sni');
    if (sni.isNotEmpty) out['sni'] = sni;
    final alpn = _alpn(_param(uri, 'alpn'));
    if (alpn != null) out['alpn'] = alpn;
    final congestion = _param(uri, 'congestion_control');
    if (congestion.isNotEmpty) out['congestion-controller'] = congestion;
    final relay = _param(uri, 'udp_relay_mode');
    if (relay.isNotEmpty) out['udp-relay-mode'] = relay;
    if (_param(uri, 'disable_sni') == '1') out['disable-sni'] = true;
    return out;
  }

  // двоеточия нет, значит паролем работает весь userInfo
  static Map<String, dynamic> _anytls(String link) {
    final uri = _parse(link);
    final userInfo = uri.userInfo;
    if (userInfo.isEmpty) throw ArgumentError('AnyTLS requires password');
    final split = userInfo.indexOf(':');
    final password = Uri.decodeComponent(
      split > 0 ? userInfo.substring(split + 1) : userInfo,
    );

    final sni = _param(uri, 'sni');
    final fp = _param(uri, 'fp');
    final out = <String, dynamic>{
      'name': proxyName,
      'type': 'anytls',
      'server': uri.host,
      'port': uri.port,
      'password': password,
      'udp': true,
      if (sni.isNotEmpty) 'sni': sni,
      // пустой fingerprint mihomo читает как без uTLS
      'client-fingerprint': fp.isNotEmpty ? fp : defaultTlsFingerprint,
    };
    final alpn = _alpn(_param(uri, 'alpn'));
    if (alpn != null) out['alpn'] = alpn;
    // hpkp это пин сертификата, у ядра поле fingerprint
    final pin = _rawParam(uri, 'hpkp');
    if (pin.isNotEmpty) out['fingerprint'] = pin;
    final ech = _echOpts(_rawParam(uri, 'ech'));
    if (ech != null) out['ech-opts'] = ech;
    return out;
  }

  // ветку amneziawg-go выбирает version: 3 это v3, на которой AWG ездил и раньше, остальное старая v1
  static Map<String, dynamic> _amneziaWg(String conf) {
    final profile = AwgProfile.parse(conf);
    final iface = profile.iface;

    String? v4;
    String? v6;
    for (final address in iface.addresses) {
      if (address.split('/').first.contains(':')) {
        v6 ??= address;
      } else {
        v4 ??= address;
      }
    }
    if (v4 == null && v6 == null) {
      throw ArgumentError('AmneziaWG config: Interface.Address is required');
    }

    final peers = [for (final peer in profile.peers) _awgPeer(peer)];

    // у ядра keepalive один и целым числом, а AWG 3.1 пишет диапазон: берём нижнюю границу, реже слать нельзя
    final keepalive = profile.peers
        .map((peer) => peer.persistentKeepalive)
        .whereType<String>()
        .map((value) => int.parse(value.split('-').first))
        .firstOrNull;

    // только адреса: домены поиска из wg-quick ядро приняло бы за резолвер
    final dns = iface.dns
        .where((server) => InternetAddress.tryParse(server) != null)
        .toList();

    final awg = _awgOption(iface.awgParams);
    return <String, dynamic>{
      'name': proxyName,
      'type': 'wireguard',
      'server': peers.first['server'],
      'port': peers.first['port'],
      'ip': ?v4,
      'ipv6': ?v6,
      'private-key': _awgKey(iface.privateKey, 'Interface.PrivateKey'),
      // списком даже для одного пира: в плоской форме ядро ставит allowed-ips в 0.0.0.0/0 само
      'peers': peers,
      'mtu': iface.mtu ?? _awgDefaultMtu,
      'udp': true,
      if (keepalive != null && keepalive > 0) 'persistent-keepalive': keepalive,
      // резолвер профиля обычно внутри туннеля (10.8.0.1), снаружи он не отвечает
      if (dns.isNotEmpty) ...{'dns': dns, 'remote-dns-resolve': true},
      'amnezia-wg-option': ?awg,
      // mihomo 1.19.32 перевёл умолчание на свой новый стек mips, AWG у нас ездил на gVisor
      'ip-stack': {'mode': 'gvisor'},
    };
  }

  // у ядра своё умолчание 1408, а на Android AWG ездил с 1280
  static const _awgDefaultMtu = 1280;

  static Map<String, dynamic> _awgPeer(AwgPeer peer) {
    final (host, port) = AwgProfile.splitEndpoint(peer.endpoint);
    final psk = peer.presharedKey;
    return <String, dynamic>{
      'server': host,
      'port': port,
      'public-key': _awgKey(peer.publicKey, 'Peer.PublicKey'),
      if (psk != null && psk.isNotEmpty)
        'pre-shared-key': _awgKey(psk, 'Peer.PresharedKey'),
      // пира без AllowedIPs ядро не принимает
      'allowed-ips': peer.allowedIps.isEmpty
          ? const ['0.0.0.0/0', '::/0']
          : peer.allowedIps,
    };
  }

  // ядро декодирует строгим StdEncoding и ключу без = отказывает, а прежний разбор такой ключ брал
  static String _awgKey(String raw, String field) {
    try {
      return base64.normalize(raw.trim());
    } on FormatException {
      throw ArgumentError('AmneziaWG config: $field is not a base64 key');
    }
  }

  static const _awgOptionNames = <String, String>{
    'jc': 'jc',
    'jmin': 'jmin',
    'jmax': 'jmax',
    's1': 's1',
    's2': 's2',
    's3': 's3',
    's4': 's4',
    'h1': 'h1',
    'h2': 'h2',
    'h3': 'h3',
    'h4': 'h4',
    'i1': 'i1',
    'i2': 'i2',
    'i3': 'i3',
    'i4': 'i4',
    'i5': 'i5',
    'headerprotectionkey': 'header-protection-key',
    'contentpaddingaddition': 'content-padding-addition',
    'rekeyaftertime': 'rekey-after-time',
    'rekeytimeout': 'rekey-timeout',
    'rejectaftertime': 'reject-after-time',
    'keepalivetimeout': 'keepalive-timeout',
    'maxhandshakeattempts': 'max-handshake-attempts',
    'randomtrailers': 'random-trailers',
    'disablecookies': 'disable-cookies',
  };

  static Map<String, dynamic>? _awgOption(Map<String, String> params) {
    if (params.isEmpty) return null;
    final out = <String, dynamic>{'version': 3};
    for (final MapEntry(:key, :value) in params.entries) {
      final name = _awgOptionNames[key];
      // ключ без имени потерялся бы молча, и сервер получил бы пакеты не той формы
      if (name == null) {
        throw ArgumentError(
          'mihomo: AmneziaWG parameter "$key" is not supported',
        );
      }
      final v = value.trim();
      out[name] = switch (key) {
        'jc' || 'jmin' || 'jmax' || 's1' || 's2' || 's3' || 's4' =>
          int.tryParse(v) ??
              (throw ArgumentError('AmneziaWG config: $key must be a number')),
        'randomtrailers' || 'disablecookies' =>
          const {'true', 't', '1', 'yes', 'on'}.contains(v.toLowerCase()),
        'headerprotectionkey' => _awgKey(v, 'HeaderProtectionKey'),
        _ => v,
      };
    }
    return out;
  }

  static Map<String, dynamic> _ssr(String link) {
    final parsed = SsrLink.tryParse(link);
    if (parsed == null) throw ArgumentError('mihomo: invalid SSR link');
    return <String, dynamic>{
      'name': proxyName,
      'type': 'ssr',
      'server': parsed.host,
      'port': parsed.port,
      'cipher': parsed.method,
      'password': parsed.password,
      // obfs и protocol у ядра обязательны, пустыми декодер их не примет
      'obfs': parsed.obfs,
      'protocol': parsed.protocol,
      'udp': true,
      if (parsed.obfsParam.isNotEmpty) 'obfs-param': parsed.obfsParam,
      if (parsed.protocolParam.isNotEmpty)
        'protocol-param': parsed.protocolParam,
    };
  }

  static Map<String, dynamic> _mieru(String link) {
    final parsed = MieruLink.tryParse(link);
    if (parsed == null) {
      throw ArgumentError('mihomo: invalid Mieru link (port/protocol pair)');
    }
    return <String, dynamic>{
      'name': proxyName,
      'type': 'mieru',
      'server': parsed.host,
      if (parsed.port != null) 'port': parsed.port,
      if (parsed.portRange.isNotEmpty) 'port-range': parsed.portRange,
      // transport, username и password у ядра обязательны
      'transport': parsed.transport,
      'username': parsed.username,
      'password': parsed.password,
      'udp': true,
      if (parsed.multiplexing.isNotEmpty) 'multiplexing': parsed.multiplexing,
      if (parsed.handshakeMode.isNotEmpty)
        'handshake-mode': parsed.handshakeMode,
      if (parsed.trafficPattern.isNotEmpty)
        'traffic-pattern': parsed.trafficPattern,
    };
  }

  static List<String> _parseList(String s) => s
      .split(RegExp(r'[\r\n,]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  static List<String> _parseRuleList(String s) =>
      _parseList(s).where((e) => !isRuleListUrl(e)).toList();

  // раньше правил пользователя и автора готового конфига. трафик туннеля к этому хосту идёт по общим правилам:
  // адрес сервера за CDN бывает ровно им
  static String exitIpProbeRule(String proxyTarget) =>
      'AND,((NOT,((IN-TYPE,TUN))),(DOMAIN,$kExitIpProbeHost)),$proxyTarget';

  // какие серверы попадают сюда, решает routeServerSupported до генерации
  static List<Map<String, dynamic>> buildRouteServerProxies(
    List<RouteServerOutbound> servers,
  ) =>
      [
        for (final server in servers)
          ...switch (_routeClashNodes(server)) {
            final nodes? => nodes.proxies,
            null => buildProxies(server.config.trim(), name: server.tag),
          },
      ];

  static List<Map<String, dynamic>> buildRouteServerGroups(
    List<RouteServerOutbound> servers,
  ) =>
      [
        for (final server in servers)
          ...?_routeClashNodes(server)?.groups,
      ];

  static ({List<Map<String, dynamic>> proxies, List<Map<String, dynamic>> groups})?
      _routeClashNodes(RouteServerOutbound server) {
    if (!CustomClashConfig.looksLikeClash(server.config)) return null;
    final clash = CustomClashConfig.tryParse(server.config.trim());
    if (clash == null) return null;
    final nodes = clash.routeNodes(server.tag);
    if (nodes == null) {
      throw ArgumentError('Route server ${server.tag}: its groups are filled '
          'by the core or point outside the config');
    }
    // узел, до которого доходят только через dialer-proxy, зовём звеном цепочки: иначе его Inner-соединение посчиталось бы второй раз
    final used = <String>{
      server.tag,
      for (final group in nodes.groups)
        for (final member in group['proxies'] as List) member.toString(),
    };
    final hops = <String>{
      for (final proxy in nodes.proxies)
        if (proxy['dialer-proxy'] case final Object dialer
            when !used.contains(dialer.toString()))
          dialer.toString(),
    };
    if (hops.isEmpty) return nodes;
    String hop(Object? name) => hops.contains(name.toString())
        ? '$chainHopPrefix$name'
        : name.toString();
    return (
      proxies: [
        for (final proxy in nodes.proxies)
          {
            ...proxy,
            'name': hop(proxy['name']),
            if (proxy['dialer-proxy'] != null)
              'dialer-proxy': hop(proxy['dialer-proxy']),
          },
      ],
      groups: [
        for (final group in nodes.groups)
          {...group, 'name': hop(group['name'])},
      ],
    );
  }

  // address у цепочки это её входной узел, у готового конфига первый из его узлов
  static List<String> routeServerDirectRules(
    List<RouteServerOutbound> servers,
  ) =>
      [
        for (final server in servers) ...[
          ...buildServerDirectRules(serverAddress: server.address),
          if (ProxyChainConfig.looksLikeChain(server.config))
            for (final address in _serverAddresses(
              buildProxies(server.config.trim(), name: server.tag),
            ).skip(1))
              ...buildServerDirectRules(serverAddress: address),
          if (_routeClashNodes(server) case final nodes?)
            for (final address in {..._serverAddresses(nodes.proxies)}
              ..remove(server.address))
              ...buildServerDirectRules(serverAddress: address),
        ],
      ];

  static String _routeServerListSet(RouteServerOutbound server) =>
      'keq-list-${server.tag}';

  // у каждого сервера свой набор, по той же причине, что у полей (buildRuleListProviders)
  static Map<String, dynamic> buildRouteServerProviders(
    List<RouteServerOutbound> servers,
  ) =>
      {
        for (final server in servers)
          if (server.listDomains.isNotEmpty)
            _routeServerListSet(server): {
              'type': 'inline',
              'behavior': 'domain',
              'payload': [for (final d in server.listDomains) '+.$d'],
            },
      };

  static const blockListSet = 'keq-list-block';
  static const directListSet = 'keq-list-direct';
  static const proxyListSet = 'keq-list-proxy';

  // набором, а не правилом на домен: на 100 тысячах это 4,5 мс на соединение против 1,4 (замер 09.10.2026).
  // встроенным, а не файлом: у Linux-туннеля под root дом свой на каждую сессию
  static Map<String, dynamic> buildRuleListProviders(RuleListDomains lists) {
    Map<String, dynamic> set(List<String> domains) => {
          'type': 'inline',
          'behavior': 'domain',
          'payload': [for (final d in domains) '+.$d'],
        };
    return {
      if (lists.blocked.isNotEmpty) blockListSet: set(lists.blocked),
      if (lists.direct.isNotEmpty) directListSet: set(lists.direct),
      if (lists.proxy.isNotEmpty) proxyListSet: set(lists.proxy),
    };
  }

  static const _privateRanges = [
    '0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8',
    '169.254.0.0/16', '172.16.0.0/12', '192.168.0.0/16',
    '192.0.0.0/24', '198.51.100.0/24', '203.0.113.0/24',
  ];

  // порядок как в xray-генераторе: блок, сам сервер, обход, приватные сети, прокси, финал
  static List<String> buildRules(
    AppSettings settings, {
    required String serverAddress,
    List<String> chainAddresses = const [],
    String? resolvedServerIp,
    String proxyTarget = proxyName,
    AppRoutingMode routingMode = AppRoutingMode.allProxy,
    List<String> managedProcessNames = const [],
    String appProcessName = '',
    bool tunOwned = false,
    bool? windows,
    RuleListDomains ruleLists = RuleListDomains.none,
    List<RouteServerOutbound> routeServers = const [],
    List<RouteAppRules> appRoutes = const [],
    OwnerGuard ownerGuard = OwnerGuard.off,
  }) {
    final rules = <String>[
      ?outsideVpnRule(ownerGuard),
      exitIpProbeRule(proxyTarget),
      ...buildProcessRules(
        routingMode: routingMode,
        managedProcessNames: managedProcessNames,
        appProcessName: appProcessName,
        windows: windows,
      ),
      ...buildUserRules(
        settings,
        proxyTarget: proxyTarget,
        blockedOnly: true,
        ruleLists: ruleLists,
        routeServers: routeServers,
        appRoutes: appRoutes,
      ),
      ...buildServerDirectRules(
        serverAddress: serverAddress,
        resolvedServerIp: resolvedServerIp,
      ),
      for (final address in chainAddresses)
        ...buildServerDirectRules(serverAddress: address),
      ...routeServerDirectRules(routeServers),
      // адрес своего tun-интерфейса мимо туннеля, иначе обращение к нему уйдёт само в себя
      if (tunOwned) 'IP-CIDR,$tunInterfaceRange,DIRECT,no-resolve',
      ...buildUserRules(
        settings,
        proxyTarget: proxyTarget,
        blockedOnly: false,
        skipBlocked: true,
        ruleLists: ruleLists,
        routeServers: routeServers,
        appRoutes: appRoutes,
      ),
    ];

    // сплит решает, чьи соединения идут в туннель, а финал что делать с остальным.
    // исключение: только выбранные без единого имени, там прежний DIRECT
    final unnamedSelection = routingMode == AppRoutingMode.onlySelected &&
        managedProcessNames.every((name) => name.trim().isEmpty);
    final finalTarget = unnamedSelection
        ? 'DIRECT'
        : _finalTarget(settings.finalOutbound, proxyTarget);

    return [...rules, 'MATCH,$finalTarget'];
  }

  // читает только наш mihomo, tool/patches/mihomo-udp-per-exit.patch; чужой ключ ядро пропускает
  static const udpPerExitKey = 'keqdroid-udp-per-exit';

  // читает только наш mihomo, tool/patches/mihomo-uid-owner-guard.patch: без ключа ядро не отличает приложение вне VPN,
  // со значением all проверяет и DNS, который перехватывает раньше правил
  static const ownerGuardKey = 'keqdroid-owner-guard';

  // первым правилом, раньше авторских
  static String? outsideVpnRule(OwnerGuard guard) => switch (guard) {
        OwnerGuard.off => null,
        OwnerGuard.all =>
          'AND,((IN-TYPE,TUN),(PROCESS-NAME,$kOutsideVpnOwner)),REJECT',
      };

  static const tunInterfaceRange = '198.18.0.0/30';

  static const fakeIpRange = '198.18.0.1/16';

  static const fakeIpFilter = kFakeIpFilter;

  // свой процесс и чужие VPN раньше сплита, иначе режим кроме выбранных утащил бы в туннель наши пинг-сокеты.
  // имя сравнивается без регистра (EqualFold), вариантов регистра как у sing-box не нужно
  static List<String> buildProcessRules({
    required AppRoutingMode routingMode,
    required List<String> managedProcessNames,
    required String appProcessName,
    bool? windows,
  }) {
    final app = appProcessName.trim();
    if (app.isEmpty && managedProcessNames.isEmpty) return const [];

    // ОС параметром: фикстура, снятая на Windows, иначе падала бы на linux-раннере
    final exe = (windows ?? Platform.isWindows) ? '.exe' : '';

    final rules = <String>[
      // наши сокеты мимо туннеля, иначе пинг мерил бы локальный конец. только пришедшие из TUN: на HTTP-вход
      // приложение шлёт то, что обязано ехать в туннель (подписки, апдейтер, флаг выхода)
      if (app.isNotEmpty)
        'AND,((IN-TYPE,TUN),(PROCESS-NAME-REGEX,^${processRegexLiteral(app)}\$)),DIRECT',
      // временное ядро замера отдельным процессом: туннель забирал его соединение, и пинговались два сервера из двадцати
      'PROCESS-NAME,keqrnel$exe,DIRECT',
      'PROCESS-NAME,mihomo$exe,DIRECT',
      'PROCESS-NAME,xray$exe,DIRECT',
      'PROCESS-NAME,sing-box$exe,DIRECT',
      // чужие VPN-клиенты мимо нашего туннеля, иначе туннель в туннеле. только в режиме весь трафик
      if (routingMode == AppRoutingMode.allProxy) ...[
        'PROCESS-NAME,tailscaled$exe,DIRECT',
        'PROCESS-NAME,wireguard$exe,DIRECT',
        'PROCESS-NAME,openvpn$exe,DIRECT',
      ],
    ];

    // одной регуляркой: ядро режет правило по запятым и считает скобки, exe с запятой в имени ронял весь конфиг.
    // только из TUN: на HTTP-вход приложение шлёт подписки и апдейтер, а невыбранное мимо уводило их напрямую
    String fromTun(String rule) => 'AND,((IN-TYPE,TUN),($rule)),DIRECT';
    final names = <String>[];
    final paths = <String>[];
    for (final process in managedProcessNames) {
      final entry = process.trim();
      if (entry.isEmpty) continue;
      (isProcessPathEntry(entry) ? paths : names).add(entry);
    }
    if (names.isEmpty && paths.isEmpty) return rules;
    final nameAlts = names.map(processRegexLiteral).join('|');
    final pathAlts = paths.map(processPathPattern).join('|');
    switch (routingMode) {
      case AppRoutingMode.onlySelected:
        final any = _processAlternatives([...names, ...paths]);
        rules.add(fromTun('${any.type},^(?!(?:${any.alts})\$)'));
      case AppRoutingMode.allExceptSelected:
        if (names.isNotEmpty) {
          rules.add(fromTun('PROCESS-NAME-REGEX,^(?:$nameAlts)\$'));
        }
        if (paths.isNotEmpty) {
          rules.add(fromTun('PROCESS-PATH-REGEX,^(?:$pathAlts)\$'));
        }
      case AppRoutingMode.allProxy:
        break;
    }
    return rules;
  }

  // одним выражением: любая из записей из двух правил собралась бы только логическим ИЛИ
  static ({String type, String alts}) _processAlternatives(
    List<String> entries,
  ) {
    final names = <String>[];
    final paths = <String>[];
    for (final entry in entries) {
      (isProcessPathEntry(entry) ? paths : names).add(entry);
    }
    final nameAlts = names.map(processRegexLiteral).join('|');
    if (paths.isEmpty) return (type: 'PROCESS-NAME-REGEX', alts: nameAlts);
    return (
      type: 'PROCESS-PATH-REGEX',
      alts: [
        paths.map(processPathPattern).join('|'),
        if (names.isNotEmpty) '.*[\\x5c/](?:$nameAlts)',
      ].join('|'),
    );
  }

  // тип входа проверяется первым, у остальных процесс не ищется вовсе
  static String _appRouteCondition(RouteAppRules route) {
    final any = _processAlternatives(route.apps);
    return 'AND,((IN-TYPE,TUN),(${any.type},^(?:${any.alts})\$))';
  }

  static String _appRouteTarget(RouteAppRules route, String proxyTarget) =>
      switch (route.target) {
        RouteTarget.block => 'REJECT',
        RouteTarget.direct => 'DIRECT',
        RouteTarget.vpn => proxyTarget,
        RouteTarget.server =>
          route.serverTag.isEmpty ? proxyTarget : route.serverTag,
      };

  static String _appRouteListSet(RouteAppRules route) =>
      'keq-list-${route.tag}';

  static String _appRouteIpSet(RouteAppRules route) => '${route.tag}-ip';

  // одним набором за одним условием: условие с процессом на каждый домен проверялось бы заново
  static List<String> _appRouteBody(
    RouteAppRules route,
    String target,
    String ipSuffix,
  ) =>
      [
        for (final d in splitDomainsAndIps(_parseRuleList(route.entries)).domains)
          '${_domainRule(d)},$target',
        if (route.listDomains.isNotEmpty)
          'RULE-SET,${_appRouteListSet(route)},$target',
        ..._ipRules(route.entries, target, ipSuffix),
      ];

  // ничего в наборе не совпало, и проверка идёт дальше по общему списку (matchSubRules):
  // сайты маршрута не отнимают у приложения остальных правил
  static List<String> _appRouteRules(
    List<RouteAppRules> routes,
    String proxyTarget,
    String suffix,
  ) =>
      [
        for (final route in routes)
          if (route.allTraffic)
            '${_appRouteCondition(route)},${_appRouteTarget(route, proxyTarget)}'
          else if (_appRouteBody(
            route,
            _appRouteTarget(route, proxyTarget),
            suffix,
          ).isNotEmpty)
            'SUB-RULE,(${_appRouteCondition(route)}),${route.tag}',
      ];

  // все маршруты сразу: от них зависит стратегия резолва, она обязана совпасть с buildUserRules
  static Map<String, List<String>> buildAppRouteSubRules(
    AppSettings settings,
    List<RouteAppRules> routes, {
    required String proxyTarget,
    List<RouteServerOutbound> routeServers = const [],
  }) {
    final strategy = _ipRuleStrategy(settings, routeServers, routes);
    final suffix = _ipSuffix(strategy);
    final sets = <String, List<String>>{};
    for (final route in routes) {
      if (route.allTraffic) continue;
      final target = _appRouteTarget(route, proxyTarget);
      final body = _appRouteBody(route, target, suffix);
      if (body.isNotEmpty) sets[route.tag] = body;
      final tail = _ipRules(route.entries, target, '');
      if (strategy == 'IPIfNonMatch' && tail.isNotEmpty) {
        sets[_appRouteIpSet(route)] = tail;
      }
    }
    return sets;
  }

  static Map<String, dynamic> buildAppRouteProviders(
    List<RouteAppRules> routes,
  ) =>
      {
        for (final route in routes)
          if (!route.allTraffic && route.listDomains.isNotEmpty)
            _appRouteListSet(route): {
              'type': 'inline',
              'behavior': 'domain',
              'payload': [for (final d in route.listDomains) '+.$d'],
            },
      };

  // no-resolve всегда: резолв ради правила против круга это тот же круг на шаг раньше
  static List<String> buildServerDirectRules({
    required String serverAddress,
    String? resolvedServerIp,
  }) {
    final rules = <String>[];
    if (serverAddress.isNotEmpty && !looksLikeIpOrCidr(serverAddress)) {
      rules.add('DOMAIN,$serverAddress,DIRECT');
    }
    for (final ip in [serverAddress, resolvedServerIp ?? '']) {
      if (ip.isNotEmpty && looksLikeIpOrCidr(ip)) {
        rules.add('IP-CIDR,${_cidr(ip)},DIRECT,no-resolve');
      }
    }
    return rules;
  }

  // IP-правила дважды: на месте с no-resolve и в конце с резолвом, mihomo идёт одним проходом,
  // а xray сначала сверяет все домены. раньше GEOIP резолвил всегда, и TikTok уходил напрямую через кэш Akamai
  static List<String> buildUserRules(
    AppSettings settings, {
    String proxyTarget = proxyName,
    bool blockedOnly = false,
    bool skipBlocked = false,
    RuleListDomains ruleLists = RuleListDomains.none,
    List<RouteServerOutbound> routeServers = const [],
    List<RouteAppRules> appRoutes = const [],
  }) {
    final rules = <String>[];
    final strategy = _ipRuleStrategy(settings, routeServers, appRoutes);
    final inPlace = _ipSuffix(strategy);
    final appBlock = [
      for (final r in appRoutes)
        if (r.target == RouteTarget.block) r,
    ];
    final appOther = [
      for (final r in appRoutes)
        if (r.target != RouteTarget.block) r,
    ];
    List<String> appRules(List<RouteAppRules> routes) =>
        _appRouteRules(routes, proxyTarget, inPlace);

    void addGroup(String raw, String target, String listSet, List<String> listed) {
      for (final d in splitDomainsAndIps(_parseRuleList(raw)).domains) {
        rules.add('${_domainRule(d)},$target');
      }
      if (listed.isNotEmpty) rules.add('RULE-SET,$listSet,$target');
      rules.addAll(_ipRules(raw, target, inPlace));
    }

    // блокировка действует во всех приложениях, и в тех, у кого свой маршрут
    if (!skipBlocked) {
      addGroup(settings.blockedRules, 'REJECT', blockListSet, ruleLists.blocked);
      rules.addAll(appRules(appBlock));
    }
    if (blockedOnly) return rules;

    // приватные сети резолва не получают. при маршрутах приложений они раньше них: весь трафик на сервер не должен увозить роутер с принтером
    final privateRanges = [
      for (final range in _privateRanges) 'IP-CIDR,$range,DIRECT,no-resolve',
    ];
    if (appOther.isNotEmpty) {
      rules
        ..addAll(privateRanges)
        ..addAll(appRules(appOther));
    }
    addGroup(settings.directRules, 'DIRECT', directListSet, ruleLists.direct);
    if (appOther.isEmpty) rules.addAll(privateRanges);
    // между обходом и через VPN, как в разделе всех приложений (routesIn)
    for (final server in routeServers) {
      addGroup(
        server.entries,
        server.tag,
        _routeServerListSet(server),
        server.listDomains,
      );
    }
    addGroup(settings.proxyRules, proxyTarget, proxyListSet, ruleLists.proxy);

    if (strategy == 'IPIfNonMatch') {
      rules.addAll(_ipRules(settings.blockedRules, 'REJECT', ''));
      // хвост с резолвом у маршрутов приложений своими наборами, за тем же условием
      for (final route in [...appBlock, ...appOther]) {
        if (route.allTraffic) continue;
        final target = _appRouteTarget(route, proxyTarget);
        if (_ipRules(route.entries, target, '').isEmpty) continue;
        rules.add(
          'SUB-RULE,(${_appRouteCondition(route)}),${_appRouteIpSet(route)}',
        );
      }
      rules.addAll(_ipRules(settings.directRules, 'DIRECT', ''));
      for (final server in routeServers) {
        rules.addAll(_ipRules(server.entries, server.tag, ''));
      }
      rules.addAll(_ipRules(settings.proxyRules, proxyTarget, ''));
    }
    return rules;
  }

  static String _ipRuleStrategy(
    AppSettings settings, [
    List<RouteServerOutbound> routeServers = const [],
    List<RouteAppRules> appRoutes = const [],
  ]) {
    final chosen = settings.xrayCore.routingDomainStrategy;
    if (chosen != 'AsIs') return chosen;
    List<String> ips(String raw) =>
        splitGeoipTokens(splitDomainsAndIps(_parseRuleList(raw)).ips).plainIps;
    // приватные сети в обходе своими не считаем: их туда клал прежний пресет
    final hasUserIps = ips(settings.blockedRules).isNotEmpty ||
        ips(settings.proxyRules).isNotEmpty ||
        routeServers.any((s) => ips(s.entries).isNotEmpty) ||
        appRoutes.any((r) => ips(r.entries).isNotEmpty) ||
        ips(settings.directRules)
            .any((ip) => !kBasePrivateRanges.contains(ip.trim()));
    return hasUserIps ? 'IPIfNonMatch' : 'AsIs';
  }

  static String _ipSuffix(String strategy) =>
      strategy == 'IPOnDemand' ? '' : ',no-resolve';

  static List<String> _ipRules(String raw, String target, String suffix) {
    final geo = splitGeoipTokens(splitDomainsAndIps(_parseRuleList(raw)).ips);
    return [
      for (final code in geo.geoipCodes) 'GEOIP,$code,$target$suffix',
      for (final ip in geo.plainIps) 'IP-CIDR,${_cidr(ip)},$target$suffix',
    ];
  }

  static String _finalTarget(String finalOutbound, String proxyTarget) =>
      switch (finalOutbound) {
        AppSettings.finalOutboundDirect => 'DIRECT',
        AppSettings.finalOutboundBlock => 'REJECT',
        _ => proxyTarget,
      };

  // то же исключение, что у ссылок в buildUserRules: только выбранные без единого имени
  static String _customFinalTarget(
    AppSettings settings,
    CustomClashConfig clash,
    AppRoutingMode routingMode,
    List<String> managedProcessNames,
  ) =>
      routingMode == AppRoutingMode.onlySelected &&
              managedProcessNames.every((name) => name.trim().isEmpty)
          ? 'DIRECT'
          : _finalTarget(settings.finalOutbound, clash.primaryTarget);

  // голое слово это зона: DOMAIN-KEYWORD ловил буквы где угодно, su уводил напрямую AI Studio
  static String _domainRule(String raw) {
    final v = raw.trim();
    final lower = v.toLowerCase();
    if (lower.startsWith('geosite:')) {
      return 'GEOSITE,${v.substring('geosite:'.length)}';
    }
    if (lower.startsWith('full:')) return 'DOMAIN,${v.substring('full:'.length)}';
    if (lower.startsWith('domain:')) {
      return 'DOMAIN-SUFFIX,${v.substring('domain:'.length)}';
    }
    if (lower.startsWith('regexp:')) {
      return 'DOMAIN-REGEX,${v.substring('regexp:'.length)}';
    }
    if (v.startsWith('.')) return 'DOMAIN-SUFFIX,${v.substring(1)}';
    return 'DOMAIN-SUFFIX,$v';
  }

  // IP-CIDR mihomo принимает только с префиксом
  static String _cidr(String raw) {
    final v = raw.trim();
    if (v.contains('/')) return v;
    return v.contains(':') ? '$v/128' : '$v/32';
  }
}
