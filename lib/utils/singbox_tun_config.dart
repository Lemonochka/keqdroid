import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';
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
    /// KpHTTP local SOCKS5 has no auth — omit username/password in outbound.
    bool localSocksNoAuth = false,
    /// this app's own exe (e.g. keqdroid.exe). routed direct so our tcp/url ping
    /// sockets measure latency from the local pc, not through the active server.
    String appProcessName = '',
  }) {
    List<String> parseList(String s) =>
        s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    Map<String, dynamic> buildProxyDnsServer() {
      final customDns = settings.xrayCore.dnsServers
          .split(RegExp(r'[\n,]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final first = customDns.isNotEmpty ? customDns.first : '1.1.1.1';
      final raw = first.trim();
      final lower = raw.toLowerCase();

      if (lower.startsWith('https://') || lower.startsWith('http://')) {
        final uri = Uri.tryParse(raw);
        if (uri != null && uri.host.isNotEmpty) {
          return {
            'tag': 'proxy-dns',
            'type': 'https',
            'server': uri.host,
            if (uri.hasPort) 'server_port': uri.port,
            if (uri.path.isNotEmpty && uri.path != '/') 'path': uri.path,
            'detour': 'proxy',
          };
        }
      }

      String host = raw;
      int? port;
      if (raw.contains(':') && !raw.contains('://')) {
        final idx = raw.lastIndexOf(':');
        final p = int.tryParse(raw.substring(idx + 1));
        if (p != null) {
          host = raw.substring(0, idx).trim();
          port = p;
        }
      }

      return {
        'tag': 'proxy-dns',
        'type': 'udp',
        'server': host,
        'server_port': ?port,
        'detour': 'proxy',
      };
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
    final bypassProcessNames = <String>{
      'xray.exe',
      'sing-box.exe',
      if (appProcessName.trim().isNotEmpty) appProcessName.trim().toLowerCase(),
    }.toList();
    rules.add({
      'process_name': bypassProcessNames,
      'outbound': 'direct',
    });

    if (routingMode == AppRoutingMode.allProxy) {
      rules.add({
        'process_name': [
          'tailscaled.exe',
          'wireguard.exe',
          'openvpn.exe',
          'openvpn-gui.exe',
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

    final tunInbound = <String, dynamic>{
      'type': 'tun',
      'tag': tunInboundTag,
      'mtu': 1400,
      'address': ['172.19.0.1/30'],
      'auto_route': true,
      // strict_route breaks routing when another vpn (e.g. tailscale) is active.
      'strict_route': !Platform.isWindows,
      'stack': 'system',
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
        'strategy': 'ipv4_only',
        'final': 'local-dns',
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
}
