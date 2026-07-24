import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';
import '../models/tun_settings.dart';
import '../tunnel/app_routing_mode.dart';
import 'process_name_utils.dart';
import 'routing_entry.dart';

/// sing-box tun-конфиг: весь трафик tun → socks5 (auth) → локальный xray.
/// xray поднимает upstream (vless, vmess, hysteria, …), sing-box только
/// перехватывает пакеты и не парсит subscription-протоколы.
class SingBoxTunConfigGen {
  static String generate({
    required int localSocksPort,
    required String socksUsername,
    required String socksPassword,
    required String serverIpToExclude,
    required AppSettings settings,
    List<String> managedProcessNames = const [],
    AppRoutingMode routingMode = AppRoutingMode.allProxy,
    /// AmneziaWG: wireproxy SOCKS5 без auth — не шлём username/password в outbound.
    bool localSocksNoAuth = false,
    /// this app's own exe (e.g. keqdroid.exe). routed direct so our tcp/url ping
    /// sockets measure latency from the local pc, not through the active server.
    String appProcessName = '',
  }) {
    // Разделители — и запятая, и перевод строки: UI обещает «по одному в
    // строке или через запятую», сплит только по ',' склеивал построчные
    // записи в один несрабатывающий токен.
    List<String> parseList(String s) => s
        .split(RegExp(r'[\r\n,]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    Map<String, dynamic> buildProxyDnsServer() {
      // Кастомный DNS уважаем только когда он включён в настройках xray-ядра.
      final customDns = !settings.xrayCore.dnsUseCustom
          ? const <String>[]
          : settings.xrayCore.dnsServers
              .split(RegExp(r'[\n,]+'))
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();

      // Дефолт — DNS-over-HTTPS через туннель. Многие VPS-хостеры/серверы режут
      // исходящий порт 53 (анти-abuse), из-за чего и UDP-, и TCP-DNS через
      // прокси умирали с "read response: EOF" — браузер получал "server not
      // found" при живом туннеле. DoH на 443 неотличим от обычного HTTPS.
      Map<String, dynamic> defaultDoh() => {
            'tag': 'proxy-dns',
            'type': 'https',
            'server': '1.1.1.1',
            'detour': 'proxy',
          };

      if (customDns.isEmpty) return defaultDoh();

      // Поле DNS хранит адреса в xray-синтаксисе (https+local://, tls://,
      // quic://, tcp://, голый ip[:port]). sing-box же ждёт типизированный
      // объект сервера, а НЕ сырую xray-строку: если скормить её как есть,
      // keqrnel падал на разборе конфига (exit code 2 — «ошибка подключения»).
      // Переводим первый адрес; непереводимое (localhost/fakedns/…) → дефолт.
      return _singBoxDnsServerFromXray(customDns.first) ?? defaultDoh();
    }

    ({
      List<String> domain,
      List<String> domainSuffix,
      List<String> domainRegex,
    }) classifyDomains(List<String> domains) {
      final exact = <String>[];
      final suffix = <String>[];
      final regex = <String>[];

      for (final raw in domains) {
        final cleaned = raw.trim().toLowerCase();
        if (cleaned.isEmpty) continue;

        if (cleaned.startsWith('full:')) {
          final v = cleaned.substring('full:'.length).trim();
          if (v.isNotEmpty) exact.add(v);
          continue;
        }
        if (cleaned.startsWith('regexp:')) {
          final v = cleaned.substring('regexp:'.length).trim();
          if (v.isNotEmpty) regex.add(v);
          continue;
        }
        if (cleaned.startsWith('domain:')) {
          final v = cleaned.substring('domain:'.length).trim();
          if (v.isNotEmpty) suffix.add(v.startsWith('.') ? v.substring(1) : v);
          continue;
        }
        if (cleaned.startsWith('geosite:')) {
          final v = cleaned.substring('geosite:'.length).trim();
          if (v.isNotEmpty) suffix.add(v);
          continue;
        }
        if (cleaned.startsWith('.')) {
          final v = cleaned.substring(1).trim();
          if (v.isNotEmpty) suffix.add(v);
          continue;
        }
        if (!cleaned.contains('.')) {
          suffix.add(cleaned);
          continue;
        }
        suffix.add(cleaned);
      }

      return (domain: exact, domainSuffix: suffix, domainRegex: regex);
    }

    void addDomainRule({
      required List<Map<String, dynamic>> targetRules,
      required List<String> sourceDomains,
      required String outbound,
    }) {
      final parts = classifyDomains(sourceDomains);
      if (parts.domain.isEmpty &&
          parts.domainSuffix.isEmpty &&
          parts.domainRegex.isEmpty) {
        return;
      }
      targetRules.add({
        if (parts.domain.isNotEmpty) 'domain': parts.domain,
        if (parts.domainSuffix.isNotEmpty) 'domain_suffix': parts.domainSuffix,
        if (parts.domainRegex.isNotEmpty) 'domain_regex': parts.domainRegex,
        'outbound': outbound,
      });
    }

    // each list is mixed (domains + ip/cidr + geoip:); split per kind.
    final directSplit = splitDomainsAndIps(parseList(settings.directRules));
    final proxySplit = splitDomainsAndIps(parseList(settings.proxyRules));
    final blockedSplit = splitDomainsAndIps(parseList(settings.blockedRules));

    final directDomains = directSplit.domains;
    final blockedDomains = blockedSplit.domains;
    final proxyDomains = proxySplit.domains;

    bool isIPv4OrCidr(String value) {
      final v = value.trim();
      final ipV4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
      final cidrV4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}/\d{1,2}$');
      return ipV4.hasMatch(v) || cidrV4.hasMatch(v);
    }

    bool isIPv6OrCidr(String value) {
      final v = value.trim();
      final ipV6 = RegExp(r'^[0-9a-fA-F:]+$');
      final cidrV6 = RegExp(r'^[0-9a-fA-F:]+/\d{1,3}$');
      return ipV6.hasMatch(v) || cidrV6.hasMatch(v);
    }

    // sing-box has no built-in geoip db here, so keep only literal ip/cidr
    // (plus geoip:private which it understands) and drop other geoip: codes.
    List<String> ipsForSingBox(List<String> ips) => ips
        .where(
          (entry) =>
              isIPv4OrCidr(entry) ||
              isIPv6OrCidr(entry) ||
              entry.trim().toLowerCase() == 'geoip:private',
        )
        .map((e) => e.trim())
        .toList();

    final directIpsForSingBox = ipsForSingBox(directSplit.ips);
    final proxyIpsForSingBox = ipsForSingBox(proxySplit.ips);
    final blockedIpsForSingBox = ipsForSingBox(blockedSplit.ips);

    const tunInboundTag = 'tun-in';

    final rules = <Map<String, dynamic>>[
      {
        'inbound': [tunInboundTag],
        'action': 'sniff',
      },
      {'protocol': 'dns', 'action': 'hijack-dns'},
      // icmp can't go over socks; route it locally
      {'protocol': 'icmp', 'outbound': 'direct'},
      {'ip_cidr': ['172.19.0.0/30'], 'outbound': 'direct'},
    ];

    // bypass tun for the cores and this app itself so they go direct:
    //  - xray.exe / ephemeral ping xray: only dials the server, avoids double-tunnel
    //  - sing-box.exe: don't route its own direct egress back into itself
    //  - <app>.exe: our dart tcp-ping sockets, so latency reflects the local pc
    // placed before split-tunnel rules so it wins regardless of routing mode.
    // Windows process names carry `.exe`; on Linux they are the bare binary
    // basename (sing-box's find_process matches the comm name). Keep Windows
    // output byte-identical by only appending the suffix there.
    final exe = Platform.isWindows ? '.exe' : '';
    final bypassProcessNames = <String>{
      'xray$exe',
      'sing-box$exe',
      // wireproxy (AmneziaWG): его WG-UDP к серверу должен идти мимо туннеля
      'wireproxy$exe',
      if (appProcessName.trim().isNotEmpty) appProcessName.trim().toLowerCase(),
    }.toList();
    rules.add({
      'process_name': bypassProcessNames,
      'outbound': 'direct',
    });

    if (routingMode == AppRoutingMode.allProxy) {
      rules.add({
        'process_name': [
          'tailscaled$exe',
          'wireguard$exe',
          'openvpn$exe',
          if (Platform.isWindows) 'openvpn-gui.exe',
        ],
        'outbound': 'direct',
      });
    }

    if (managedProcessNames.isNotEmpty) {
      switch (routingMode) {
        case AppRoutingMode.onlySelected:
          for (final process in managedProcessNames) {
            final variants = processNameMatchVariants(process);
            if (variants.isEmpty) continue;
            rules.add({
              'process_name': variants,
              'outbound': 'proxy',
            });
          }
        case AppRoutingMode.allExceptSelected:
          for (final process in managedProcessNames) {
            final variants = processNameMatchVariants(process);
            if (variants.isEmpty) continue;
            rules.add({
              'process_name': variants,
              'outbound': 'direct',
            });
          }
        case AppRoutingMode.allProxy:
          break;
      }
    }

    if (blockedDomains.isNotEmpty) {
      addDomainRule(
        targetRules: rules,
        sourceDomains: blockedDomains,
        outbound: 'block',
      );
    }
    if (blockedIpsForSingBox.isNotEmpty) {
      rules.add({'ip_cidr': blockedIpsForSingBox, 'outbound': 'block'});
    }

    if (serverIpToExclude.isNotEmpty) {
      final cidrs = serverIpToExclude.contains('/')
          ? [serverIpToExclude]
          : ['$serverIpToExclude/32'];
      rules.add({'ip_cidr': cidrs, 'outbound': 'direct'});
    }

    if (directDomains.isNotEmpty) {
      addDomainRule(
        targetRules: rules,
        sourceDomains: directDomains,
        outbound: 'direct',
      );
    }

    if (directIpsForSingBox.isNotEmpty) {
      rules.add({'ip_cidr': directIpsForSingBox, 'outbound': 'direct'});
    }

    rules.add({
      'ip_cidr': [
        '10.0.0.0/8',
        '172.16.0.0/12',
        '192.168.0.0/16',
        '127.0.0.0/8',
      ],
      'outbound': 'direct',
    });

    if (proxyDomains.isNotEmpty) {
      addDomainRule(
        targetRules: rules,
        sourceDomains: proxyDomains,
        outbound: 'proxy',
      );
    }
    if (proxyIpsForSingBox.isNotEmpty) {
      rules.add({'ip_cidr': proxyIpsForSingBox, 'outbound': 'proxy'});
    }

    var routeFinal =
        routingMode == AppRoutingMode.onlySelected ? 'direct' : 'proxy';

    if (settings.killSwitch && routingMode == AppRoutingMode.allProxy) {
      rules.add({
        'ip_cidr': ['0.0.0.0/1', '128.0.0.0/1'],
        'outbound': 'proxy',
      });
      routeFinal = 'block';
    }

    final proxyOutbound = <String, dynamic>{
      'type': 'socks',
      'tag': 'proxy',
      'server': '127.0.0.1',
      'server_port': localSocksPort,
      'version': '5',
      if (!localSocksNoAuth) ...{
        'username': socksUsername,
        'password': socksPassword,
      },
    };

    // Direct-домены резолвим системным резолвером (local-dns): он знает
    // корпоративные/LAN-зоны сплит-DNS, которых у публичного DoH нет — иначе
    // домен из Direct-списка получает NXDOMAIN, хотя маршрут для него direct.
    // hijack-dns при этом перехватывает ВСЕ запросы (анти-leak, см. dns.final),
    // поэтому выбор резолвера возможен только здесь, через dns.rules.
    final directDnsParts = classifyDomains(directDomains);
    final dnsRules = <Map<String, dynamic>>[
      if (directDnsParts.domain.isNotEmpty ||
          directDnsParts.domainSuffix.isNotEmpty ||
          directDnsParts.domainRegex.isNotEmpty)
        {
          if (directDnsParts.domain.isNotEmpty)
            'domain': directDnsParts.domain,
          if (directDnsParts.domainSuffix.isNotEmpty)
            'domain_suffix': directDnsParts.domainSuffix,
          if (directDnsParts.domainRegex.isNotEmpty)
            'domain_regex': directDnsParts.domainRegex,
          'server': 'local-dns',
        },
    ];

    final tun = settings.tun;
    final tunInbound = <String, dynamic>{
      'type': 'tun',
      'tag': tunInboundTag,
      'mtu': tun.mtu,
      'address': ['172.19.0.1/30'],
      // без auto_route трафик в TUN не попадает; off — только для ручных маршрутов
      'auto_route': tun.autoRoute,
      // auto: on везде, кроме Windows — там strict_route breaks routing when
      // another vpn (e.g. tailscale) is active.
      'strict_route': tun.strictRouteEnabled(windows: Platform.isWindows),
      'stack': tun.stack,
      // full-cone NAT считает только gvisor-netstack (в mixed он держит UDP)
      if (tun.endpointIndependentNat && tun.stack != TunSettings.stackSystem)
        'endpoint_independent_nat': true,
      if (tun.udpTimeoutSec != TunSettings.defaultUdpTimeoutSec)
        'udp_timeout': '${tun.udpTimeoutSec}s',
    };
    if (!Platform.isWindows) {
      tunInbound['interface_name'] = 'tun-keqdis';
    }

    final map = <String, dynamic>{
      'log': {
        'level': 'info',
        'timestamp': true,
      },
      'dns': {
        'servers': [
          {'tag': 'local-dns', 'type': 'local'},
          buildProxyDnsServer(),
        ],
        if (dnsRules.isNotEmpty) 'rules': dnsRules,
        'strategy': 'ipv4_only',
        // Клиентский DNS идёт через туннель (proxy-dns), а не через системный
        // резолвер: иначе на машинах с Tailscale его перехватывает MagicDNS
        // (100.100.100.100) и резолв ломается, плюс это утечка DNS мимо VPN.
        // Исключение — direct-домены, их dns.rules выше шлют в local-dns.
        'final': 'proxy-dns',
      },
      'inbounds': [tunInbound],
      'outbounds': [
        proxyOutbound,
        {'type': 'direct', 'tag': 'direct'},
        {'type': 'block', 'tag': 'block'},
      ],
      'route': {
        'auto_detect_interface': true,
        'find_process': true,
        'default_domain_resolver': 'proxy-dns',
        'rules': rules,
        'final': routeFinal,
      },
    };

    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Переводит один DNS-адрес из xray-синтаксиса в объект sing-box dns-сервера
  /// (формат 1.12+: `{type, server, server_port?, path?}`). Возвращает null,
  /// когда адрес нельзя гонять как сетевой upstream через прокси
  /// (localhost/fakedns/dhcp) — вызывающий тогда берёт дефолтный DoH.
  ///
  /// UDP через SOCKS хрупок (см. коммент выше про TCP:53), поэтому и «голый»
  /// адрес, и udp://-схему форсируем в TCP. Все серверы идут `detour: proxy`.
  static Map<String, dynamic>? _singBoxDnsServerFromXray(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();

    // Служебные xray-резолверы без сетевого upstream — их через прокси не гонишь.
    if (lower == 'localhost' || lower == 'fakedns' || lower.startsWith('dhcp')) {
      return null;
    }

    Map<String, dynamic> server(String type, String host, int? port,
            {String? path}) =>
        {
          'tag': 'proxy-dns',
          'type': type,
          'server': host,
          'server_port': ?port,
          if (path != null && path.isNotEmpty && path != '/') 'path': path,
          'detour': 'proxy',
        };

    // Схема вида `scheme://`. У xray scheme может нести суффикс (`https+local`,
    // `tcp+local`, …) — базой считаем часть до '+'.
    final schemeMatch = RegExp(r'^([a-z][a-z0-9.+-]*)://').firstMatch(lower);
    if (schemeMatch != null) {
      final base = schemeMatch.group(1)!.split('+').first;
      final uri = Uri.tryParse(trimmed);
      if (uri == null || uri.host.isEmpty) return null;
      final port = uri.hasPort ? uri.port : null;
      switch (base) {
        case 'https':
        case 'h2c':
          return server('https', uri.host, port, path: uri.path);
        case 'tls':
        case 'dot':
          return server('tls', uri.host, port);
        case 'quic':
        case 'doq':
          return server('quic', uri.host, port);
        case 'tcp':
          return server('tcp', uri.host, port);
        case 'udp':
        case 'dns':
          return server('tcp', uri.host, port); // UDP over SOCKS ненадёжен → TCP
        default:
          return null;
      }
    }

    // Без схемы: голый ip / host / host:port / [ipv6]:port → TCP:53 через прокси.
    String host = trimmed;
    int? port;
    final bracketed = RegExp(r'^\[([0-9a-fA-F:]+)\]:(\d+)$').firstMatch(trimmed);
    if (bracketed != null) {
      host = bracketed.group(1)!;
      port = int.parse(bracketed.group(2)!);
    } else if (RegExp(r'^[^:]+:\d+$').hasMatch(trimmed)) {
      // Ровно один ':' с числовым портом — иначе это голый IPv6, не host:port.
      final idx = trimmed.lastIndexOf(':');
      host = trimmed.substring(0, idx).trim();
      port = int.parse(trimmed.substring(idx + 1));
    }
    if (host.isEmpty) return null;
    return server('tcp', host, port);
  }
}
